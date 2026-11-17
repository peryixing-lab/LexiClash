// CoreController.ets — HarmonyOS CoreHandlerInterface & NAPI Bridge Controller
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  beginDelayJob,
  cancelDelayJob,
  inspectProfile,
  nativeInitCore,
  nativeInvokeMethod,
  nativeIsGoCoreLoaded,
  nativeGetCoreVersion,
  pollDelayJob,
  testProfileDelay
} from 'libclash_bridge.so';
import { CoreMemorySnapshot, CoreMethodNames, OutboundIpModel } from './CoreProtocol';

export interface SubscriptionFetchResult {
  ok: boolean;
  yamlContent: string;
  uploadBytes: number;
  downloadBytes: number;
  totalBytes: number;
  expireTimestamp: number;
  errorMessage: string;
}

interface LexiCoreReply {
  id: string | number;
  result: Object | null;
  error: string | LexiCoreMethodError | null;
}

interface LexiCoreMethodError { code: string; message: string; }
interface LexiYamlCommandArgs {
  yaml?: string;
  selectedMap?: Record<string, string>;
  testUrl?: string;
}
interface LexiCoreSetupBase { path: string; }
interface LexiCoreOptions { 'test-url': string; }
interface LexiCoreSetupArgs {
  base: LexiCoreSetupBase;
  'selected-map': Record<string, string>;
  options: LexiCoreOptions;
}

interface LexiDelayReply {
  value: number;
}

interface LexiOutboundProbeReply { body: string; error?: string; }
interface LexiIpConnection { isp: string; asn: number; }
interface LexiIpTimezone { id: string; }
interface LexiIpWhoReply {
  success: boolean;
  ip: string;
  country_code: string;
  country: string;
  connection: LexiIpConnection;
  timezone: LexiIpTimezone;
}

export interface LexiServiceCheckResult {
  name: string;
  status: string;
  region?: string;
  delay?: number;
}

export interface LexiIpIntelFlags {
  isHosting?: boolean;
  isDatacenter?: boolean;
  isMobile?: boolean;
  isProxy?: boolean;
  isTor?: boolean;
  isAbuser?: boolean;
  isBogon?: boolean;
  asnType?: string;
  companyType?: string;
  hasIntelFlags?: boolean;
}

export interface LexiIpClassification {
  ipType: string;
  qualityLevel: 'good' | 'normal' | 'risky';
}

export class CoreController {
  private static instance: CoreController | null = null;
  private reqIdCounter: number = 1;
  private initialized: boolean = false;
  private coreVersionText: string = '代理内核未安装';
  private lastError: string = '';
  private coreHomeDir: string = '';
  private stagedCounter: number = 0;
  private lastRuntimePath: string = '';
  private initializationAttempted: boolean = false;
  private isExternalGoLoaded: boolean = false;
  private lastInitRawResponse: string = '';
  private vpnTunnelActive: boolean = false;
  private runtimeProxyPort: number = 0;

  setRuntimeProxyPort(port: number): void {
    this.runtimeProxyPort = port;
  }

  private runtimeProxy(): boolean | http.HttpProxy {
    return this.runtimeProxyPort > 0
      ? { host: '127.0.0.1', port: this.runtimeProxyPort, exclusionList: [] } : false;
  }

  setVpnTunnelActive(active: boolean): void {
    this.vpnTunnelActive = active;
  }

  hasOfflineNativeProbes(): boolean {
    return this.isReady() && typeof testProfileDelay === 'function' && typeof beginDelayJob === 'function';
  }

  supportsVpnPrivacy(): boolean {
    const raw: string = this.invokeMethod('privacy.capabilities', '{}');
    if (this.responseError(raw).length > 0) { return false; }
    try {
      const reply: LexiCoreReply = JSON.parse(raw) as LexiCoreReply;
      const capabilities: Record<string, Object> = reply.result as Record<string, Object>;
      return Number(capabilities['version'] ?? 0) >= 1;
    } catch (_error) { return false; }
  }

  async inspectProfileNative(content: string): Promise<string> {
    if (typeof inspectProfile !== 'function') {
      return '';
    }
    try {
      return await inspectProfile(content);
    } catch (_err) {
      return '';
    }
  }

  async testOfflineDelayNative(content: string, nodeName: string): Promise<number> {
    if (typeof testProfileDelay !== 'function' || content.trim().length === 0) {
      return -1;
    }
    try {
      const raw: string = await testProfileDelay(content, nodeName);
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      if (parsed['error']) {
        return -1;
      }
      const delay: number = Number(parsed['delay'] ?? 0);
      return delay > 0 ? delay : -1;
    } catch (_err) {
      return -1;
    }
  }

  beginOfflineDelayJobNative(content: string, names: string[]): string {
    if (typeof beginDelayJob !== 'function' || content.trim().length === 0 || names.length === 0) {
      return '';
    }
    try {
      return beginDelayJob(content, JSON.stringify(names));
    } catch (_err) {
      return '';
    }
  }

  pollOfflineDelayJobNative(jobId: string): string {
    if (typeof pollDelayJob !== 'function' || jobId.length === 0) {
      return '{"results":[],"done":true,"total":0}';
    }
    try {
      return pollDelayJob(jobId);
    } catch (_err) {
      return '{"results":[],"done":true,"total":0}';
    }
  }

  cancelOfflineDelayJobNative(jobId: string): void {
    if (typeof cancelDelayJob !== 'function' || jobId.length === 0) {
      return;
    }
    try {
      cancelDelayJob(jobId);
    } catch (_err) {
      // ignore
    }
  }

  static getInstance(): CoreController {
    if (CoreController.instance === null) {
      CoreController.instance = new CoreController();
    }
    return CoreController.instance;
  }

  initCore(homeDir: string): string {
    this.coreHomeDir = homeDir;
    this.initializationAttempted = true;
    try {
      if (!fs.accessSync(homeDir)) { fs.mkdirSync(homeDir, true); }
      const resp: string = nativeInitCore(homeDir, 1);
      this.lastInitRawResponse = resp;
      this.isExternalGoLoaded = nativeIsGoCoreLoaded();
      this.coreVersionText = nativeGetCoreVersion();
      this.initialized = this.isExternalGoLoaded && this.responseError(resp).length === 0;
      return resp;
    } catch (e) {
      this.initialized = false;
      this.lastInitRawResponse = JSON.stringify({ id: 0, result: null, error: '代理内核初始化失败' });
      return this.lastInitRawResponse;
    }
  }

  invokeMethod(method: string, argsJson: string = '{}'): string {
    const id: number = this.reqIdCounter++;
    const envelope: string = `{"id":${JSON.stringify(String(id))},"method":${JSON.stringify(method)},"arguments":${argsJson}}`;
    try {
      const raw: string = nativeInvokeMethod(envelope);
      const reply: LexiCoreReply = JSON.parse(raw) as LexiCoreReply;
      if (String(reply.id) !== String(id)) {
        return JSON.stringify({ id: id, result: null, error: '内核响应与请求不匹配' });
      }
      return raw;
    } catch (e) {
      return JSON.stringify({ id: id, result: null, error: '代理内核调用失败' });
    }
  }

  responseError(raw: string): string {
    try {
      const reply: LexiCoreReply = JSON.parse(raw) as LexiCoreReply;
      if (reply.error !== null && reply.error !== undefined) {
        return typeof reply.error === 'string' ? reply.error : reply.error.message ?? JSON.stringify(reply.error);
      }
      if (reply.id === undefined || reply.result === undefined) { return '内核返回了无效响应'; }
      return '';
    } catch (error) { return '无法解析内核响应'; }
  }

  execute(method: string, argsJson: string = '{}'): string {
    if (!this.isReady()) { this.lastError = this.getUnavailableReason(); return this.lastError; }
    let stagedPath: string = '';
    try {
      if (method === CoreMethodNames.CONFIG_SETUP || method === CoreMethodNames.CONFIG_VALIDATE) {
        const command: LexiYamlCommandArgs = JSON.parse(argsJson) as LexiYamlCommandArgs;
        if (typeof command.yaml === 'string') {
          if (this.coreHomeDir.length === 0) { return '内核目录尚未初始化'; }
          stagedPath = this.coreHomeDir + '/runtime-' + (++this.stagedCounter) + '.yaml';
          const file: fs.File = fs.openSync(stagedPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          try { fs.writeSync(file.fd, command.yaml); } finally { fs.closeSync(file); }
          if (method === CoreMethodNames.CONFIG_VALIDATE) {
            argsJson = JSON.stringify({ path: stagedPath });
          } else {
            const setup: LexiCoreSetupArgs = {
              base: { path: stagedPath }, 'selected-map': command.selectedMap ?? {},
              options: { 'test-url': command.testUrl ?? '' }
            };
            argsJson = JSON.stringify(setup);
          }
        }
      }
      const raw: string = this.invokeMethod(method, argsJson);
      this.lastError = this.responseError(raw);
      if (this.lastError.length === 0 && method === CoreMethodNames.CONFIG_VALIDATE) {
        const reply: LexiCoreReply = JSON.parse(raw) as LexiCoreReply;
        if (typeof reply.result === 'string' && reply.result.length > 0) { this.lastError = reply.result; }
      }
      if (stagedPath.length > 0 && method === CoreMethodNames.CONFIG_SETUP && this.lastError.length === 0) {
        this.removeStagedFile(this.lastRuntimePath);
        this.lastRuntimePath = stagedPath;
        stagedPath = '';
      }
    } catch (error) { this.lastError = '内核操作失败：' + (error as Error).message; }
    finally { this.removeStagedFile(stagedPath); }
    return this.lastError;
  }

  private removeStagedFile(filePath: string): void {
    if (filePath.length === 0) { return; }
    try { fs.unlinkSync(filePath); } catch (error) { /* Cleanup must not hide a core error. */ }
  }

  isReady(): boolean { return this.initialized && this.isExternalGoLoaded; }

  getUnavailableReason(): string {
    return this.isReady() ? '' : '未安装兼容的代理内核，当前无法启动代理或连接代理链。';
  }

  getCoreVersion(): string {
    if (!this.initializationAttempted) {
      this.initCore('/data/storage/el2/base/files/clash');
    }
    return this.coreVersionText;
  }

  isGoLibraryPresent(): boolean {
    return this.isExternalGoLoaded;
  }

  getLastInitResponse(): string {
    return this.lastInitRawResponse;
  }

  forceGC(): string {
    return this.execute(CoreMethodNames.CORE_GC);
  }

  queryMemoryStats(isRunning: boolean): CoreMemorySnapshot {
    const empty: CoreMemorySnapshot = { appBytes: 0, coreRssBytes: 0, heapInuseBytes: 0,
      heapIdleBytes: 0, stackInuseBytes: 0, runtimeOtherBytes: 0 };
    if (!isRunning || !this.isReady()) { return empty; }
    const raw: string = this.invokeMethod(CoreMethodNames.CORE_MEMORY);
    if (this.responseError(raw).length > 0) { return empty; }
    const reply: LexiCoreReply = JSON.parse(raw) as LexiCoreReply;
    const stats: Record<string, number> = reply.result as Record<string, number>;
    if (!stats || typeof stats['rss'] !== 'number') { return empty; }
    return { appBytes: 0, coreRssBytes: stats['rss'], heapInuseBytes: stats['heap-inuse'] ?? 0,
      heapIdleBytes: stats['heap-idle'] ?? 0, stackInuseBytes: stats['stack-inuse'] ?? 0,
      runtimeOtherBytes: stats['runtime-other'] ?? 0 };
  }

  async testNodeDelay(nodeName: string, _regionCode: string, testUrl: string, timeoutMs: number): Promise<number> {
    if (!this.isReady()) { return -1; }
    const raw: string = this.invokeMethod(
      CoreMethodNames.PROXY_TEST_DELAY,
      JSON.stringify({ 'proxy-name': nodeName, 'test-url': testUrl, timeout: timeoutMs })
    );
    if (this.responseError(raw).length > 0) { return -1; }
    const reply: LexiCoreReply = JSON.parse(raw) as LexiCoreReply;
    const delay: LexiDelayReply = reply.result as LexiDelayReply;
    return delay && typeof delay.value === 'number' && delay.value > 0 ? delay.value : -1;
  }

  private static readonly DATACENTER_KEYWORDS: string[] = [
    'amazon', 'aws', 'google cloud', 'gcp', 'microsoft', 'azure', 'oracle',
    'digitalocean', 'linode', 'akamai connected', 'vultr', 'choopa', 'hetzner',
    'ovh', 'contabo', 'fdcservers', 'cogent', 'datacamp', 'cdn77', 'cloudflare',
    'fastly', 'leaseweb', 'zenlayer', 'gcore', 'm247', 'tzulo', 'quadranet',
    'psychz', 'multacom', 'colocation', 'hosting', 'datacenter', 'data center',
    'b2 net', 'constant company', 'racknerd', 'buyvm', 'frantech', 'bandwagon',
    'dmit', 'xtom', 'akari', 'packethub', 'global communication network',
    'alibaba', 'aliyun', 'tencent cloud', 'huawei cloud', 'ucloud', 'vps',
    'server', 'cloud', 'it7 networks', 'sakura internet', 'conoha', 'kamatera',
    'hostwinds', 'interserver', 'ionos', 'scaleway', 'upcloud', 'exoscale',
    'misaka', 'edgeone', 'bunnycdn', 'cdn', 'serverhub', 'hivelocity', 'tera',
    'layer7', 'eranium', 'cogent communications'
  ];

  private static readonly BUSINESS_KEYWORDS: string[] = [
    'university', 'college', 'academy', 'hospital', 'financial', 'bank',
    'government', 'ministry', 'enterprise'
  ];

  private static readonly MOBILE_KEYWORDS: string[] = [
    'cellular', 'wireless', '4g', '5g', 'lte', 'mobile communications',
    't-mobile', 'verizon wireless', 'docomo', 'kddi', 'softbank mobile',
    'far eastone', 'taiwan mobile', 'smartone', 'cmhk', 'china mobile hong kong'
  ];

  private static readonly RESIDENTIAL_KEYWORDS: string[] = [
    'chinanet', 'china telecom', 'china unicom', 'china mobile', 'cmnet', 'cncgroup',
    'comcast', 'xfinity', 'verizon', 'at&t', 'spectrum', 'charter', 'cox',
    'ntt', 'kddi', 'softbank', 'nuro', 'so-net', 'hinet', 'chunghwa',
    'pccw', 'netvigator', 'hkbn', 'hkt', 'singtel', 'starhub', 'm1 limited',
    'korea telecom', 'sk broadband', 'lg uplus', 'british telecom', 'bt ',
    'virgin media', 'talktalk', 'vodafone', 'orange', 'deutsche telekom',
    'telefonica', 'movistar', 'rogers', 'bell canada', 'telus', 'broadband',
    'fiber', 'fibre', 'ftth', 'adsl', 'residential', 'cablevision', 'optimum'
  ];

  private static includesAny(haystack: string, needles: string[]): boolean {
    for (let i: number = 0; i < needles.length; i++) {
      if (haystack.includes(needles[i])) {
        return true;
      }
    }
    return false;
  }

  static classifyOutboundIp(
    orgText: string,
    asnText: string,
    flags?: LexiIpIntelFlags
  ): LexiIpClassification {
    const asnType: string = (flags?.asnType ?? '').toLowerCase();
    const companyType: string = (flags?.companyType ?? '').toLowerCase();
    const isDcByType: boolean = asnType === 'hosting' || companyType === 'hosting';
    const isDcFlag: boolean = flags?.isHosting === true || flags?.isDatacenter === true || isDcByType;

    if (flags?.isTor === true || flags?.isAbuser === true || flags?.isBogon === true) {
      return {
        ipType: isDcFlag ? 'DataCenter' : 'Business',
        qualityLevel: 'risky'
      };
    }

    if (isDcFlag) {
      return {
        ipType: 'DataCenter',
        qualityLevel: flags?.isProxy === true ? 'risky' : 'normal'
      };
    }

    if (flags?.isMobile === true || asnType === 'mobile' || companyType === 'mobile') {
      return {
        ipType: 'Mobile',
        qualityLevel: flags?.isProxy === true ? 'risky' : 'good'
      };
    }

    const combined: string = `${orgText} ${asnText}`.toLowerCase();
    if (CoreController.includesAny(combined, CoreController.DATACENTER_KEYWORDS)) {
      return {
        ipType: 'DataCenter',
        qualityLevel: flags?.isProxy === true ? 'risky' : 'normal'
      };
    }

    if (CoreController.includesAny(combined, CoreController.BUSINESS_KEYWORDS) ||
      asnType === 'business' || companyType === 'business' ||
      asnType === 'education' || companyType === 'education' ||
      asnType === 'government' || companyType === 'government') {
      return {
        ipType: 'Business',
        qualityLevel: flags?.isProxy === true ? 'risky' : 'normal'
      };
    }

    if (flags?.isProxy === true) {
      return { ipType: 'DataCenter', qualityLevel: 'risky' };
    }

    if (CoreController.includesAny(combined, CoreController.MOBILE_KEYWORDS)) {
      return { ipType: 'Mobile', qualityLevel: 'good' };
    }

    if (asnType === 'isp' || companyType === 'isp' ||
      CoreController.includesAny(combined, CoreController.RESIDENTIAL_KEYWORDS) ||
      flags?.hasIntelFlags === true) {
      return { ipType: 'Residential', qualityLevel: 'good' };
    }

    return { ipType: '', qualityLevel: 'normal' };
  }

  private static extractObject(value: Object | undefined): Record<string, Object> | undefined {
    if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, Object>;
    }
    return undefined;
  }

  private async fetchIpApiIntel(ip: string): Promise<LexiIpIntelFlags | undefined> {
    if (ip.length === 0) {
      return undefined;
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(
        `http://ip-api.com/json/${encodeURIComponent(ip)}?fields=status,mobile,proxy,hosting,isp,org,as`,
        {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          reuseConnections: false,
          addressFamily: http.AddressFamily.ONLY_V4,
          header: { 'User-Agent': 'curl/8.4.0' },
          connectTimeout: 2500,
          readTimeout: 3500
        }
      );
      if (response.responseCode !== 200 || response.result === undefined) {
        return undefined;
      }
      const data: Record<string, Object> = JSON.parse(String(response.result)) as Record<string, Object>;
      if (data['status'] !== 'success') {
        return undefined;
      }
      return {
        isHosting: data['hosting'] === true,
        isMobile: data['mobile'] === true,
        isProxy: data['proxy'] === true,
        hasIntelFlags: typeof data['hosting'] === 'boolean' || typeof data['mobile'] === 'boolean'
      };
    } catch (_err) {
      return undefined;
    } finally {
      client.destroy();
    }
  }

  async probeOutboundIpInfo(): Promise<OutboundIpModel | null> {
    if (!this.isReady()) { return null; }
    if (this.vpnTunnelActive) {
      return await this.probeOutboundIpViaHttp();
    }
    const raw: string = this.invokeMethod(CoreMethodNames.PROBE_OUTBOUND_IP,
      JSON.stringify({ urls: ['https://ipwho.is/'], 'proxy-name': '', timeout: 4000 }));
    if (this.responseError(raw).length > 0) { return null; }
    const reply: LexiCoreReply = JSON.parse(raw) as LexiCoreReply;
    const result: LexiOutboundProbeReply = reply.result as LexiOutboundProbeReply;
    if (!result || result.error || typeof result.body !== 'string') { return null; }
    try {
      const info: LexiIpWhoReply = JSON.parse(result.body) as LexiIpWhoReply;
      if (!info.success || typeof info.ip !== 'string' || info.ip.length === 0) { return null; }
      const orgName: string = info.connection?.isp ?? '';
      const asnStr: string = info.connection?.asn ? 'AS' + info.connection.asn : '';
      const classified: LexiIpClassification = CoreController.classifyOutboundIp(orgName, asnStr);
      return { ip: info.ip, countryCode: info.country_code ?? '', countryName: info.country ?? '',
        ipType: classified.ipType, qualityLevel: classified.qualityLevel, qualityScore: 0,
        organization: orgName, asn: asnStr, timezone: info.timezone?.id ?? '' };
    } catch (error) { return null; }
  }

  private async probeOutboundIpViaHttp(): Promise<OutboundIpModel | null> {
    const endpoints: string[] = [
      'https://ipwho.is/?lang=zh-CN',
      'http://ip-api.com/json/?fields=status,country,countryCode,timezone,isp,org,as,mobile,proxy,hosting,query',
      'https://api.ipapi.is/',
      'https://api.ip.sb/geoip',
      'https://ipinfo.io/json'
    ];
    for (let i: number = 0; i < endpoints.length; i++) {
      const endpoint: string = endpoints[i];
      const client: http.HttpRequest = http.createHttp();
      try {
        const response: http.HttpResponse = await client.request(endpoint, {
          usingProxy: this.runtimeProxy(),
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          reuseConnections: false,
          addressFamily: http.AddressFamily.ONLY_V4,
          header: { 'User-Agent': 'curl/8.4.0' },
          connectTimeout: 5000,
          readTimeout: 7000
        });
        if (response.responseCode !== 200 || response.result === undefined) {
          continue;
        }
        const data: Record<string, Object> = JSON.parse(String(response.result)) as Record<string, Object>;
        if (data['success'] === false || data['status'] === 'fail') {
          continue;
        }
        const resolvedIp: string = String(data['ip'] ?? data['query'] ?? '');
        if (resolvedIp.length === 0) {
          continue;
        }
        const connObj: Record<string, Object> | undefined = CoreController.extractObject(data['connection']);
        const tzObj: Record<string, Object> | undefined = CoreController.extractObject(data['timezone']);
        const locObj: Record<string, Object> | undefined = CoreController.extractObject(data['location']);
        const asnObj: Record<string, Object> | undefined = CoreController.extractObject(data['asn']);
        const companyObj: Record<string, Object> | undefined = CoreController.extractObject(data['company']);

        const orgText: string = connObj && typeof connObj['isp'] === 'string'
          ? String(connObj['isp'])
          : (companyObj && typeof companyObj['name'] === 'string'
            ? String(companyObj['name'])
            : String(data['company'] ?? data['isp'] ?? data['organization'] ?? data['org'] ?? ''));

        let asnNum: number = connObj && typeof connObj['asn'] === 'number'
          ? Number(connObj['asn'])
          : (asnObj && typeof asnObj['asn'] === 'number'
            ? Number(asnObj['asn'])
            : Number(data['asn'] ?? 0));
        const asnCandidate: string = String(data['as'] ?? data['asn'] ?? orgText);
        if ((isNaN(asnNum) || asnNum <= 0) && asnCandidate.startsWith('AS')) {
          const sp: number = asnCandidate.indexOf(' ');
          const parsedAsn: number = Number(sp > 2 ? asnCandidate.substring(2, sp) : asnCandidate.substring(2));
          if (!isNaN(parsedAsn) && parsedAsn > 0) {
            asnNum = parsedAsn;
          }
        }
        const asnStr: string = !isNaN(asnNum) && asnNum > 0 ? `AS${asnNum}` : '';

        let flags: LexiIpIntelFlags = {
          isHosting: data['hosting'] === true,
          isDatacenter: data['is_datacenter'] === true,
          isMobile: data['mobile'] === true || data['is_mobile'] === true,
          isProxy: data['proxy'] === true || data['is_proxy'] === true || data['is_vpn'] === true,
          isTor: data['is_tor'] === true,
          isAbuser: data['is_abuser'] === true,
          isBogon: data['is_bogon'] === true,
          asnType: asnObj && typeof asnObj['type'] === 'string' ? String(asnObj['type']) : '',
          companyType: companyObj && typeof companyObj['type'] === 'string' ? String(companyObj['type']) : '',
          hasIntelFlags: typeof data['hosting'] === 'boolean' || typeof data['is_datacenter'] === 'boolean' || typeof data['mobile'] === 'boolean'
        };

        if (!flags.hasIntelFlags) {
          const enriched: LexiIpIntelFlags | undefined = await this.fetchIpApiIntel(resolvedIp);
          if (enriched !== undefined) {
            flags = enriched;
          }
        }

        const classified: LexiIpClassification = CoreController.classifyOutboundIp(orgText, asnStr, flags);
        return {
          ip: resolvedIp,
          countryCode: String(data['country_code'] ?? data['countryCode'] ?? locObj?.['country_code'] ?? data['country'] ?? ''),
          countryName: String(data['country'] ?? locObj?.['country'] ?? data['region'] ?? ''),
          ipType: classified.ipType,
          qualityLevel: classified.qualityLevel,
          qualityScore: 0,
          organization: orgText,
          asn: asnStr,
          timezone: tzObj && typeof tzObj['id'] === 'string'
            ? String(tzObj['id'])
            : String(data['timezone'] ?? locObj?.['timezone'] ?? '')
        };
      } catch (_err) {
        // retry next geoip endpoint
      } finally {
        client.destroy();
      }
    }
    return null;
  }

  async probeSingleServiceUrl(name: string, url: string): Promise<LexiServiceCheckResult> {
    const client: http.HttpRequest = http.createHttp();
    const startMs: number = Date.now();
    try {
      const resp: http.HttpResponse = await client.request(url, {
        usingProxy: this.runtimeProxy(),
        method: http.RequestMethod.GET,
        usingCache: false,
        reuseConnections: false,
        addressFamily: http.AddressFamily.ONLY_V4,
        header: { 'User-Agent': 'FlClash/v0.8.98' },
        connectTimeout: 6000,
        readTimeout: 6500
      });
      const elapsed: number = Math.max(1, Date.now() - startMs);
      if (resp.responseCode >= 200 && resp.responseCode < 500) {
        return { name: name, status: 'available', delay: elapsed };
      }
      return { name: name, status: 'restricted', delay: elapsed };
    } catch (_err) {
      return { name: name, status: 'unavailable', delay: -1 };
    } finally {
      client.destroy();
    }
  }

  async probeServiceAvailability(names: string[]): Promise<LexiServiceCheckResult[]> {
    if (!this.isReady()) { return []; }
    if (this.vpnTunnelActive) {
      const urlMap: Record<string, string> = {
        'google': 'https://www.google.com/generate_204',
        'github': 'https://api.github.com',
        'openai': 'https://chat.openai.com',
        'claude': 'https://claude.ai',
        'youtube': 'https://www.youtube.com',
        'netflix': 'https://www.netflix.com',
        'spotify': 'https://open.spotify.com',
        'disney': 'https://www.disneyplus.com',
        'gemini': 'https://gemini.google.com',
        'discord': 'https://discord.com',
        'bilibili': 'https://www.bilibili.com',
        'tiktok': 'https://www.tiktok.com'
      };
      const tasks: Promise<LexiServiceCheckResult>[] = [];
      for (let i: number = 0; i < names.length; i++) {
        const lower: string = names[i].toLowerCase();
        const targetUrl: string = urlMap[lower] ?? `https://www.${lower}.com`;
        tasks.push(this.probeSingleServiceUrl(names[i], targetUrl));
      }
      return await Promise.all(tasks);
    }
    const raw: string = this.invokeMethod(CoreMethodNames.PROBE_SERVICES,
      JSON.stringify({ names: names, 'proxy-name': '', timeout: 4000 }));
    if (this.responseError(raw).length > 0) { return []; }
    const reply: LexiCoreReply = JSON.parse(raw) as LexiCoreReply;
    return Array.isArray(reply.result) ? reply.result as LexiServiceCheckResult[] : [];
  }

  async fetchSubscriptionFromUrl(rawUrl: string): Promise<SubscriptionFetchResult> {
    let targetUrl: string = rawUrl.trim();
    if (
      targetUrl.startsWith('clash://install-config?url=') ||
      targetUrl.startsWith('flclash://install-config?url=') ||
      targetUrl.startsWith('clashmeta://install-config?url=')
    ) {
      const eqIdx: number = targetUrl.indexOf('url=');
      if (eqIdx >= 0) {
        try {
          targetUrl = decodeURIComponent(targetUrl.substring(eqIdx + 4).split('&')[0]);
        } catch (e) {
          targetUrl = targetUrl.substring(eqIdx + 4);
        }
      }
    }

    if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
      return {
        ok: false,
        yamlContent: '',
        uploadBytes: 0,
        downloadBytes: 0,
        totalBytes: 0,
        expireTimestamp: 0,
        errorMessage: '请输入以 http:// 或 https:// 开头的有效订阅链接'
      };
    }

    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await httpRequest.request(targetUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 8000,
        header: {
          'User-Agent': 'FlClash/v0.8.92 clash.meta/v1.19.15 mihomo/1.19.15'
        }
      });

      if (resp.responseCode >= 200 && resp.responseCode < 300 && typeof resp.result === 'string') {
        const body: string = resp.result as string;
        let upBytes: number = 0;
        let downBytes: number = 0;
        let totBytes: number = 0;
        let expSec: number = 0;

        const headerStr: string = JSON.stringify(resp.header ?? {});
        const upMatch: RegExpMatchArray | null = headerStr.match(/upload=(\d+)/i);
        const downMatch: RegExpMatchArray | null = headerStr.match(/download=(\d+)/i);
        const totMatch: RegExpMatchArray | null = headerStr.match(/total=(\d+)/i);
        const expMatch: RegExpMatchArray | null = headerStr.match(/expire=(\d+)/i);

        if (upMatch && upMatch.length > 1) upBytes = parseInt(upMatch[1], 10);
        if (downMatch && downMatch.length > 1) downBytes = parseInt(downMatch[1], 10);
        if (totMatch && totMatch.length > 1) totBytes = parseInt(totMatch[1], 10);
        if (expMatch && expMatch.length > 1) expSec = parseInt(expMatch[1], 10);

        return {
          ok: true,
          yamlContent: body,
          uploadBytes: upBytes,
          downloadBytes: downBytes,
          totalBytes: totBytes,
          expireTimestamp: expSec,
          errorMessage: ''
        };
      }

      return {
        ok: false,
        yamlContent: '',
        uploadBytes: 0,
        downloadBytes: 0,
        totalBytes: 0,
        expireTimestamp: 0,
        errorMessage: `服务器返回 HTTP ${resp.responseCode}`
      };
    } catch (e) {
      return {
        ok: false,
        yamlContent: '',
        uploadBytes: 0,
        downloadBytes: 0,
        totalBytes: 0,
        expireTimestamp: 0,
        errorMessage: '网络请求失败，请检查网络连接或订阅链接是否正确'
      };
    } finally { httpRequest.destroy(); }
  }
}

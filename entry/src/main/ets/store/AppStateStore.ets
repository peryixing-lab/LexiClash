// AppStateStore.ets — Clean Initial State & Real Runtime Store for LexiClash (FlClash Mobile)

import {
  AppAccessItem,
  ColorStyleKind,
  CoreLogRecordItem,
  CoreMemorySnapshot,
  CoreMethodNames,
  CoreStatusType,
  DashboardFeedKind,
  DashboardWidgetConfigItem,
  DnsQueryRecordItem,
  ExternalResourceItem,
  LogLevelKind,
  LexiProxyChainDraft,
  LexiSavedProxySelection,
  NavBarStyleKind,
  OutboundIpModel,
  OutboundModeType,
  OverrideRuleItem,
  ProfileSourceKind,
  ProfileSubscriptionModel,
  ProxiesLayoutDensity,
  ProxiesSortKind,
  ProxiesViewStyle,
  ProxyCardSizeKind,
  ProxyGroupItem,
  ProxyNodeItem,
  ServiceProbeItem,
  ThemeModeKind,
  TrackerRecordItem
} from '../core/CoreProtocol';
import { CoreController, LexiServiceCheckResult, SubscriptionFetchResult } from '../core/CoreController';
import { ParsedYamlSummary, YamlProfileParser } from '../core/YamlProfileParser';
import { ClashProxyEntry, ClashSeqEditResult, ClashUriBatchResult, ClashUriParser } from '../core/ClashUriParser';
import { LexiChainBuildResult, ProxyChainConfig } from '../core/ProxyChainConfig';
import { LexiControllerTraffic, LexiVpnRuntimeStatus, VpnRuntimeManager } from '../core/VpnRuntimeManager';
import { StateRepository } from './StateRepository';
import { LexiRuntimePolicy, RuntimeConfig } from '../core/RuntimeConfig';
import { AppAccessControl, LexiAppAccessMode, LexiAppAccessPolicy } from '../core/AppAccessControl';
import { LexiTunSettings, LexiTunStack, TunConfig } from '../core/TunConfig';

interface LexiPersistedState {
  tunSettings?: LexiTunSettings;
  accessControlEnabled?: boolean;
  accessControlMode?: LexiAppAccessMode;
  appAccessList?: AppAccessItem[];
  networkSettings?: LexiRuntimePolicy;
  version: number;
  profiles: ProfileSubscriptionModel[];
  currentProfileId: string;
  chains: LexiProxyChainDraft[];
  selections: LexiSavedProxySelection[];
  localeLang: string;
  themeMode: ThemeModeKind;
  seedColorId: string;
  colorStyle: ColorStyleKind;
  pureBlack: boolean;
  liquidGlass: boolean;
  navBarStyle: NavBarStyleKind;
  dashboardWidgets: DashboardWidgetConfigItem[];
  outboundMode: OutboundModeType;
  proxiesViewStyle: ProxiesViewStyle;
  proxiesSortKind: ProxiesSortKind;
  hideTimeoutProxies: boolean;
  testUrl: string;
  overrideRules: OverrideRuleItem[];
  autoRun: boolean;
  chainWarningAcknowledged?: boolean;
}

interface LexiProfileParseOutcome {
  ok: boolean;
  yamlContent: string;
  summary: ParsedYamlSummary;
  errorMessage: string;
}

interface LexiRuntimeConfiguration {
  yaml: string;
  selectedMap: Record<string, string>;
  testUrl: string;
}

export type StateChangeListener = () => void;

export class AppStateStore {
  private static instance: AppStateStore | null = null;
  private listeners: StateChangeListener[] = [];
  private core: CoreController = CoreController.getInstance();
  private repository: StateRepository = new StateRepository();
  private chains: LexiProxyChainDraft[] = [];
  private selections: LexiSavedProxySelection[] = [];
  private persistenceTimer: number = -1;
  private coreHomeDir: string = '';
  private vpnManager: VpnRuntimeManager = new VpnRuntimeManager();
  private lastTrafficSampleAt: number = 0;
  private lastUploadTotalSample: number = 0;
  private lastDownloadTotalSample: number = 0;
  private isPollingLiveStats: boolean = false;
  private managedRuntime: boolean = false;
  lastOperationError: string = '';
  isVpnTransitioning: boolean = false;
  isChainConnecting: boolean = false;
  chainWarningAcknowledged: boolean = false;
  chainConnected: boolean = false;
  private connectedChainNames: string[] = [];
  private connectedChainGroup: string = '';
  private connectedChainMode: OutboundModeType = 'rule';

  // Core & Tunnel lifecycle state (clean initial state on install: stopped, no profile)
  isRunning: boolean = false;
  coreStatus: CoreStatusType = 'disconnected';
  runTimeSeconds: number = 0;
  outboundMode: OutboundModeType = 'rule';
  vpnEnabled: boolean = false;
  systemProxyEnabled: boolean = false;
  allowLan: boolean = false;
  intranetIp: string = '—';
  hideIp: boolean = false;
  isProbingIp: boolean = false;
  outboundProbeFailed: boolean = false;

  // Network & Advanced config (mihomo defaults)
  mixedPort: number = 7890;
  socksPort: number = 7891;
  redirPort: number = 7892;
  tproxyPort: number = 7893;
  ipv6Enabled: boolean = false;
  tcpConcurrent: boolean = false;
  unifiedDelay: boolean = true;
  appendSystemDns: boolean = false;
  blockStun: boolean = true;
  bypassPrivateRoute: boolean = true;
  findProcessMode: string = 'off';
  tunStack: LexiTunStack = 'system';
  tunMtu: number = 1400;
  dnsHijack: string = 'any:53';
  dnsEnhancedMode: string = 'fake-ip';
  dnsNameserver: string = 'https://1.1.1.1/dns-query';
  dnsFallback: string = 'https://1.0.0.1/dns-query';
  snifferEnabled: boolean = true;
  forceDnsMapping: boolean = true;
  parsePureIp: boolean = true;
  ntpEnabled: boolean = false;
  ntpServer: string = 'time.apple.com';
  testUrl: string = 'https://www.gstatic.com/generate_204';
  userAgent: string = 'FlClash/v0.8.92 clash.meta/v1.19.15';
  externalControllerOpen: boolean = false;
  externalControllerAddress: string = '127.0.0.1:9090';
  externalControllerSecret: string = '';
  autoLaunch: boolean = false;
  autoRun: boolean = false;
  logcatEnabled: boolean = true;
  autoCloseConnections: boolean = true;
  onlyStatisticsProxy: boolean = false;
  developerMode: boolean = false;
  disclaimerAccepted: boolean = true;

  // Theme & UI preferences (mobile default)
  localeLang: string = 'zh_CN';
  themeMode: ThemeModeKind = 'dark';
  seedColorId: string = 'amber';
  colorStyle: ColorStyleKind = 'vivid';
  pureBlack: boolean = false;
  liquidGlass: boolean = true;
  navBarStyle: NavBarStyleKind = 'floating';
  dashboardFeed: DashboardFeedKind = 'connections';

  // Proxies view preferences
  proxiesViewStyle: ProxiesViewStyle = 'tab';
  proxiesSortKind: ProxiesSortKind = 'none';
  proxiesLayout: ProxiesLayoutDensity = 'standard';
  proxyCardSize: ProxyCardSizeKind = 'expand';
  hideTimeoutProxies: boolean = false;
  currentGroupId: string = '';

  // Traffic & Waveform state (all zero until tunnel starts)
  currentUploadSpeed: number = 0;
  currentDownloadSpeed: number = 0;
  peakUploadSpeed: number = 0;
  peakDownloadSpeed: number = 0;
  totalUploadBytes: number = 0;
  totalDownloadBytes: number = 0;
  uploadWaveHistory: number[] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ];
  downloadWaveHistory: number[] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ];

  // Memory state (core is 0 when stopped)
  memorySnapshot: CoreMemorySnapshot = {
    appBytes: 0,
    coreRssBytes: 0,
    heapInuseBytes: 0,
    heapIdleBytes: 0,
    stackInuseBytes: 0,
    runtimeOtherBytes: 0
  };

  // Outbound IP state (empty until probed)
  outboundIpInfo: OutboundIpModel = {
    ip: '',
    countryCode: '',
    countryName: '',
    ipType: '',
    qualityLevel: 'normal',
    qualityScore: 0,
    organization: '',
    asn: '',
    timezone: ''
  };

  // Mobile Dashboard widgets (matching FlClash Android DashboardWidget list)
  dashboardWidgets: DashboardWidgetConfigItem[] = [
    { id: 'currentOutbound', titleKey: 'status', descKey: '出口 IP、运行时长与启动按钮', enabled: true, removable: false, desktopOnly: false },
    { id: 'networkSpeed', titleKey: 'networkSpeed', descKey: '实时上传与下载速度统计', enabled: true, removable: true, desktopOnly: false },
    { id: 'outboundMode', titleKey: 'outboundMode', descKey: '规则 / 全局 / 直连 出站模式切换', enabled: true, removable: true, desktopOnly: false },
    { id: 'vpnButton', titleKey: 'VPN', descKey: 'VPN 开关控制', enabled: true, removable: true, desktopOnly: false },
    { id: 'profiles', titleKey: 'profile', descKey: '当前配置与订阅信息', enabled: true, removable: true, desktopOnly: false },
    { id: 'serviceStatus', titleKey: 'serviceStatus', descKey: '常用服务连通性状态检测', enabled: true, removable: true, desktopOnly: false },
    { id: 'proxyGroups', titleKey: 'proxyGroup', descKey: '策略组概览', enabled: true, removable: true, desktopOnly: false },
    { id: 'connectionStats', titleKey: 'liveConnections', descKey: '实时连接、最近请求与 DNS 查询统计', enabled: true, removable: true, desktopOnly: false },
    { id: 'intranetIp', titleKey: 'intranetIp', descKey: '内网 IP 与局域网代理开关', enabled: true, removable: true, desktopOnly: false },
    { id: 'memoryInfo', titleKey: 'memoryInfo', descKey: '应用与内核内存占用统计', enabled: true, removable: true, desktopOnly: false }
  ];

  // Service Probes (all pending / delayMs = 0 until tested)
  serviceProbes: ServiceProbeItem[] = [
    { id: 'srv_google', name: 'Google', iconName: 'google', url: 'https://www.google.com/generate_204', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_github', name: 'GitHub', iconName: 'github', url: 'https://api.github.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_openai', name: 'OpenAI', iconName: 'openai', url: 'https://chat.openai.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_claude', name: 'Claude', iconName: 'claude', url: 'https://claude.ai', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_youtube', name: 'YouTube', iconName: 'youtube', url: 'https://www.youtube.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_netflix', name: 'Netflix', iconName: 'netflix', url: 'https://www.netflix.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_spotify', name: 'Spotify', iconName: 'spotify', url: 'https://open.spotify.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_disney', name: 'Disney+', iconName: 'disneyplus', url: 'https://www.disneyplus.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_gemini', name: 'Gemini', iconName: 'gemini', url: 'https://gemini.google.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_discord', name: 'Discord', iconName: 'discord', url: 'https://discord.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_bilibili', name: 'Bilibili', iconName: 'bilibili', url: 'https://www.bilibili.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true },
    { id: 'srv_tiktok', name: 'TikTok', iconName: 'tiktok', url: 'https://www.tiktok.com', status: 'unavailable', delayMs: 0, regionCode: '', enabled: true }
  ];

  // Empty on install — populated only when user imports/creates a profile
  proxyNodes: ProxyNodeItem[] = [];
  proxyGroups: ProxyGroupItem[] = [];
  currentProfileId: string = '';
  profiles: ProfileSubscriptionModel[] = [];

  // Empty on install — populated only when running
  liveConnections: TrackerRecordItem[] = [];
  recentRequests: TrackerRecordItem[] = [];
  recentRequestsCount: number = 0;
  dnsQueriesCount: number = 0;
  dnsQueries: DnsQueryRecordItem[] = [];
  coreLogs: CoreLogRecordItem[] = [];
  externalResources: ExternalResourceItem[] = [];
  overrideRules: OverrideRuleItem[] = [];

  // Access Control (Disabled by default on install)
  accessControlEnabled: boolean = false;
  accessControlMode: LexiAppAccessMode = 'blacklist';
  appAccessList: AppAccessItem[] = [];

  // WebDAV Backup (Unbound by default on install)
  webdavUrl: string = '';
  webdavUser: string = '';
  webdavPassword: string = '';
  webdavConnected: boolean = false;
  lastBackupTimeText: string = '暂无信息';

  private tickerId: number = -1;
  private isAppInForeground: boolean = true;

  private constructor() {
    this.startLiveTicker();
  }

  setAppInForeground(inForeground: boolean): void {
    if (this.isAppInForeground === inForeground) {
      return;
    }
    this.isAppInForeground = inForeground;
    if (!inForeground) {
      if (this.tickerId !== -1) {
        clearInterval(this.tickerId);
        this.tickerId = -1;
      }
      this.persistState();
      return;
    }
    if (this.tickerId === -1) {
      this.resumeFromBackgroundAsync();
    } else {
      this.restoreExistingVpnSessionAsync();
    }
  }

  private async resumeFromBackgroundAsync(): Promise<void> {
    await this.restoreExistingVpnSessionAsync();
    if (!this.isAppInForeground) {
      return;
    }
    if (this.tickerId === -1) {
      this.startLiveTicker();
    }
    if (this.isRunning) {
      if (this.outboundIpInfo.ip.length === 0) {
        this.refreshOutboundIp();
      }
      await this.pollLiveVpnStatsAsync();
    }
  }

  async awaitStartupReadyAsync(maxWaitMs: number = 320): Promise<void> {
    let waitTimerId: number = -1;
    try {
      await Promise.race<void>([
        this.restoreExistingVpnSessionAsync(),
        new Promise<void>((resolve: () => void): void => {
          waitTimerId = setTimeout((): void => {
            waitTimerId = -1;
            resolve();
          }, Math.max(0, maxWaitMs));
        })
      ]);
    } finally {
      if (waitTimerId !== -1) {
        clearTimeout(waitTimerId);
      }
    }
  }

  initialize(filesDir: string): void {
    this.coreHomeDir = filesDir + '/clash';
    this.core.initCore(this.coreHomeDir);
    this.vpnManager.setFilesDir(filesDir);
    const raw: string = this.repository.initialize(filesDir);
    if (raw.length === 0) {
      this.refreshIntranetIpAsync();
      return;
    }
    try {
      const saved: LexiPersistedState = JSON.parse(raw) as LexiPersistedState;
      if (saved.version !== 1 || !Array.isArray(saved.profiles)) { throw new Error('本地配置版本不受支持'); }
      this.profiles = saved.profiles;
      this.currentProfileId = saved.currentProfileId;
      this.chains = saved.chains ?? [];
      this.selections = saved.selections ?? [];
      this.localeLang = saved.localeLang;
      this.themeMode = saved.themeMode;
      this.seedColorId = saved.seedColorId;
      this.colorStyle = saved.colorStyle;
      this.pureBlack = saved.pureBlack;
      this.liquidGlass = saved.liquidGlass;
      this.navBarStyle = saved.navBarStyle;
      this.dashboardWidgets = saved.dashboardWidgets;
      this.outboundMode = saved.outboundMode;
      this.proxiesViewStyle = saved.proxiesViewStyle;
      this.proxiesSortKind = saved.proxiesSortKind;
      this.hideTimeoutProxies = saved.hideTimeoutProxies;
      this.testUrl = saved.testUrl;
      this.overrideRules = saved.overrideRules ?? [];
      this.accessControlEnabled = saved.accessControlEnabled === true;
      this.accessControlMode = saved.accessControlMode === 'whitelist' ? 'whitelist' : 'blacklist';
      this.appAccessList = AppAccessControl.restoreEntries(saved.appAccessList);
      const tunSettings: LexiTunSettings = saved.tunSettings ?? TunConfig.defaults();
      if (TunConfig.validationError(tunSettings).length > 0) { throw new Error('保存的 TUN 配置无效'); }
      this.tunStack = tunSettings.stack;
      this.tunMtu = tunSettings.mtu;
      if (saved.networkSettings !== undefined) {
        const settings: LexiRuntimePolicy = saved.networkSettings;
        this.ipv6Enabled = settings.ipv6;
        this.blockStun = settings.blockStun;
        this.snifferEnabled = settings.sniffer;
        this.forceDnsMapping = settings.forceDnsMapping;
        this.parsePureIp = settings.parsePureIp;
        this.dnsEnhancedMode = settings.enhancedMode;
        this.dnsNameserver = settings.nameservers.join(', ');
        this.dnsFallback = settings.fallback.join(', ');
      }
      this.autoRun = saved.autoRun ?? false;
      this.chainWarningAcknowledged = saved.chainWarningAcknowledged ?? false;
      let repairedSavedProfiles: boolean = false;
      for (let i: number = 0; i < this.profiles.length; i++) {
        this.profiles[i].isUpdating = false;
        const healed: string = ClashUriParser.repairBrokenProxiesIndent(this.profiles[i].yamlContent);
        if (healed !== this.profiles[i].yamlContent) {
          this.profiles[i].yamlContent = healed;
          const healedSummary: ParsedYamlSummary = YamlProfileParser.parseYaml(healed);
          if (healedSummary.valid) {
            this.profiles[i].proxiesCount = healedSummary.proxiesCount;
            this.profiles[i].groupsCount = healedSummary.groupsCount;
            this.profiles[i].rulesCount = healedSummary.rulesCount;
          }
          repairedSavedProfiles = true;
        }
      }
      if (repairedSavedProfiles) {
        this.persistState();
      }
      const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
      if (profile !== null) {
        this.currentProfileId = profile.id;
        const summary: ParsedYamlSummary = YamlProfileParser.parseYaml(profile.yamlContent);
        if (summary.valid) {
          this.applyParsedProfileToRuntime(summary);
        } else if (this.core.hasOfflineNativeProbes()) {
          this.restoreSummaryFromNativeAsync(profile);
        }
      }
    } catch (error) {
      this.lastOperationError = '读取本地配置失败：' + (error as Error).message;
      this.appendLog('error', 'Storage', 'Load', this.lastOperationError);
    }
    this.refreshIntranetIpAsync();
    this.restoreExistingVpnSessionAsync();
    if (this.autoRun && this.core.isReady() && this.profiles.length > 0 && !this.isRunning) {
      this.toggleRunningAsync();
    }
  }

  persistState(): void {
    if (this.persistenceTimer !== -1) { clearTimeout(this.persistenceTimer); this.persistenceTimer = -1; }
    const state: LexiPersistedState = {
      tunSettings: this.getTunSettings(),
      accessControlEnabled: this.accessControlEnabled, accessControlMode: this.accessControlMode,
      appAccessList: this.appAccessList,
      networkSettings: this.networkPolicy(''),
      version: 1, profiles: this.profiles, currentProfileId: this.currentProfileId,
      chains: this.chains, selections: this.selections, localeLang: this.localeLang,
      themeMode: this.themeMode, seedColorId: this.seedColorId, colorStyle: this.colorStyle,
      pureBlack: this.pureBlack, liquidGlass: this.liquidGlass, navBarStyle: this.navBarStyle,
      dashboardWidgets: this.dashboardWidgets, outboundMode: this.outboundMode,
      proxiesViewStyle: this.proxiesViewStyle, proxiesSortKind: this.proxiesSortKind,
      hideTimeoutProxies: this.hideTimeoutProxies, testUrl: this.testUrl, overrideRules: this.overrideRules,
      autoRun: this.autoRun, chainWarningAcknowledged: this.chainWarningAcknowledged
    };
    this.repository.save(JSON.stringify(state));
    if (this.repository.errorMessage.length > 0) { this.lastOperationError = this.repository.errorMessage; }
  }

  static getInstance(): AppStateStore {
    if (AppStateStore.instance === null) {
      AppStateStore.instance = new AppStateStore();
    }
    return AppStateStore.instance;
  }

  subscribe(listener: StateChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: StateChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  notify(persist: boolean = true): void {
    if (persist && this.persistenceTimer === -1) {
      this.persistenceTimer = setTimeout((): void => { this.persistenceTimer = -1; this.persistState(); }, 250);
    }
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i]();
    }
  }

  hasProfiles(): boolean {
    return this.profiles.length > 0;
  }

  getRuntimeUnavailableReason(): string { return this.core.getUnavailableReason(); }

  private networkPolicy(dnsProxy: string): LexiRuntimePolicy {
    const rules: string[] = this.overrideRules.filter((rule: OverrideRuleItem): boolean => rule.enabled)
      .map((rule: OverrideRuleItem): string => rule.ruleType + ',' + rule.payload + ',' + rule.targetGroup + (rule.noResolve ? ',no-resolve' : ''));
    return {
      mixedPort: this.mixedPort, version: 1, mode: this.outboundMode, dnsProxy: dnsProxy, ipv6: this.ipv6Enabled,
      blockStun: this.blockStun, sniffer: this.snifferEnabled, forceDnsMapping: this.forceDnsMapping,
      parsePureIp: this.parsePureIp, enhancedMode: this.dnsEnhancedMode,
      nameservers: RuntimeConfig.servers(this.dnsNameserver), fallback: RuntimeConfig.servers(this.dnsFallback), rules: rules,
      selections: {}
    };
  }

  applyNetworkSettings(): void {
    this.notify();
    if (this.isRunning && this.hasManagedRuntime()) {
      this.restartVpnAfterConfigChangeAsync().catch((error: Error): void => {
        this.lastOperationError = error.message;
        this.notify(false);
      });
    }
  }

  private runtimeYaml(yaml: string, dnsProxy: string = ''): string {
    if (/^(ss|ssr|vmess|vless|trojan|hysteria2?|hy2|tuic|wireguard):\/\//m.test(yaml.trim())) {
      const parsed: ClashUriBatchResult = ClashUriParser.parseBatchUris(yaml);
      if (parsed.entries.length === 0) { throw new Error('无法编译节点订阅的隐私配置'); }
      return this.runtimeYaml(ClashUriParser.buildCompleteYamlFromEntries(parsed.entries), dnsProxy);
    }
    const selected: Record<string, string> = this.buildSelectedMap(yaml);
    const target: string = dnsProxy || this.resolvePreferredGlobalTarget(YamlProfileParser.parseYaml(yaml), selected);
    if (dnsProxy.length > 0) {
      selected[this.outboundMode === 'global' ? 'GLOBAL' : this.getProxyChainDraft().targetGroup] = dnsProxy;
    }
    const policy: LexiRuntimePolicy = this.networkPolicy(target);
    policy.selections = selected;
    return RuntimeConfig.attach(yaml, policy);
  }

  private buildVpnRuntimeYaml(yaml: string): string {
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    const nodes: string[] = this.isChainConnecting ? draft.nodeNames : this.connectedChainNames;
    const exit: string = (this.chainConnected || this.isChainConnecting) && nodes.length > 0
      ? nodes[nodes.length - 1] : '';
    return this.runtimeYaml(yaml, exit);
  }

  private setupRuntimeYaml(yaml: string, profileId: string = this.currentProfileId): string {
    const selected: Record<string, string> = {};
    const parsed: ParsedYamlSummary = YamlProfileParser.parseYaml(yaml);
    for (let i: number = 0; i < parsed.parsedGroups.length; i++) {
      const group: ProxyGroupItem = parsed.parsedGroups[i];
      const saved: LexiSavedProxySelection | undefined = this.selections.find((entry: LexiSavedProxySelection): boolean =>
        entry.profileId === profileId && entry.groupName === group.name && group.nodeNames.includes(entry.nodeName));
      selected[group.name] = saved?.nodeName ?? group.selectedName;
    }
    const global: LexiSavedProxySelection | undefined = this.selections.find((entry: LexiSavedProxySelection): boolean =>
      entry.profileId === profileId && entry.groupName === 'GLOBAL');
    if (global !== undefined && (global.nodeName === 'DIRECT' || parsed.parsedNodes.some((node: ProxyNodeItem): boolean => node.name === global.nodeName))) {
      selected['GLOBAL'] = global.nodeName;
    }
    if (!selected['GLOBAL'] || (this.outboundMode === 'global' && selected['GLOBAL'] === 'DIRECT')) {
      const globalTarget: string = this.resolvePreferredGlobalTarget(parsed, selected);
      if (globalTarget.length > 0) {
        selected['GLOBAL'] = globalTarget;
      }
    }
    const args: LexiRuntimeConfiguration = { yaml: this.runtimeYaml(yaml), selectedMap: selected, testUrl: this.testUrl };
    return this.core.execute(CoreMethodNames.CONFIG_SETUP, JSON.stringify(args));
  }

  private resolveGroupLeafFromList(
    startName: string,
    groups: ProxyGroupItem[],
    selectionsMap?: Record<string, string>,
    depth: number = 0
  ): string {
    if (depth > 8 || startName.length === 0) {
      return '';
    }
    const grp: ProxyGroupItem | undefined = groups.find((candidate: ProxyGroupItem): boolean => candidate.name === startName);
    if (grp === undefined) {
      return startName;
    }
    const picked: string = selectionsMap && selectionsMap[grp.name] ? selectionsMap[grp.name] : grp.selectedName;
    if (picked.length === 0) {
      return '';
    }
    return this.resolveGroupLeafFromList(picked, groups, selectionsMap, depth + 1);
  }

  private resolvePreferredGlobalTarget(parsed?: ParsedYamlSummary, selectionsMap?: Record<string, string>): string {
    if (this.chainConnected && this.connectedChainGroup === 'GLOBAL' && this.connectedChainNames.length > 0) {
      return this.connectedChainNames[this.connectedChainNames.length - 1];
    }
    const groups: ProxyGroupItem[] = parsed ? parsed.parsedGroups : this.proxyGroups;
    const nodes: ProxyNodeItem[] = parsed ? parsed.parsedNodes : this.proxyNodes;
    const isRealNode = (name: string): boolean =>
      name.length > 0 &&
        name !== 'DIRECT' &&
        name !== 'REJECT' &&
        nodes.some((n: ProxyNodeItem): boolean => n.name === name && n.port > 0 && n.providerName !== 'Group');

    if (!parsed && this.currentGroupId.length > 0) {
      const viewed: ProxyGroupItem | null = this.getGroupById(this.currentGroupId);
      if (viewed !== null && viewed.groupType === 'Selector') {
        const viewedLeaf: string = this.resolveGroupLeafFromList(viewed.name, groups, selectionsMap);
        if (isRealNode(viewedLeaf)) {
          return viewedLeaf;
        }
      }
    }
    for (let i: number = 0; i < groups.length; i++) {
      if (groups[i].groupType === 'Selector') {
        const leaf: string = this.resolveGroupLeafFromList(groups[i].name, groups, selectionsMap);
        if (isRealNode(leaf)) {
          return leaf;
        }
      }
    }
    const savedGlobal: LexiSavedProxySelection | undefined = this.selections.find(
      (entry: LexiSavedProxySelection): boolean => entry.profileId === this.currentProfileId && entry.groupName === 'GLOBAL'
    );
    if (savedGlobal !== undefined && isRealNode(savedGlobal.nodeName)) {
      return savedGlobal.nodeName;
    }
    for (let i: number = 0; i < nodes.length; i++) {
      if (
        nodes[i].port > 0 &&
          nodes[i].providerName !== 'Group' &&
          nodes[i].name !== 'DIRECT' &&
          nodes[i].name !== 'REJECT' &&
          !/^(剩余流量|距离下次重置|套餐到期)/.test(nodes[i].name)
      ) {
        return nodes[i].name;
      }
    }
    for (let i: number = 0; i < nodes.length; i++) {
      if (nodes[i].port > 0 && nodes[i].providerName !== 'Group' && nodes[i].name !== 'DIRECT' && nodes[i].name !== 'REJECT') {
        return nodes[i].name;
      }
    }
    return '';
  }

  private buildSelectedMap(yaml: string, profileId: string = this.currentProfileId): Record<string, string> {
    const selected: Record<string, string> = {};
    const parsed: ParsedYamlSummary = YamlProfileParser.parseYaml(yaml);
    for (let i: number = 0; i < parsed.parsedGroups.length; i++) {
      const group: ProxyGroupItem = parsed.parsedGroups[i];
      const saved: LexiSavedProxySelection | undefined = this.selections.find((entry: LexiSavedProxySelection): boolean =>
        entry.profileId === profileId && entry.groupName === group.name && group.nodeNames.includes(entry.nodeName));
      selected[group.name] = saved?.nodeName ?? group.selectedName;
    }
    for (let i: number = 0; i < this.proxyGroups.length; i++) {
      const g: ProxyGroupItem = this.proxyGroups[i];
      if (!selected[g.name] && g.selectedName.length > 0) {
        selected[g.name] = g.selectedName;
      }
    }
    const global: LexiSavedProxySelection | undefined = this.selections.find((entry: LexiSavedProxySelection): boolean =>
      entry.profileId === profileId && entry.groupName === 'GLOBAL');
    if (global !== undefined && (global.nodeName === 'DIRECT' || parsed.parsedNodes.some((node: ProxyNodeItem): boolean => node.name === global.nodeName) || this.proxyNodes.some((node: ProxyNodeItem): boolean => node.name === global.nodeName))) {
      selected['GLOBAL'] = global.nodeName;
    }
    if (!selected['GLOBAL'] || (this.outboundMode === 'global' && !this.chainConnected)) {
      const fallbackGlobal: string = this.resolvePreferredGlobalTarget(parsed, selected);
      if (fallbackGlobal.length > 0) {
        selected['GLOBAL'] = fallbackGlobal;
      }
    }
    return selected;
  }

  private async refreshIntranetIpAsync(): Promise<void> {
    const ip: string = await this.vpnManager.getLocalIntranetIp();
    if (ip !== this.intranetIp) {
      this.intranetIp = ip;
      this.notify(false);
    }
  }

  private async restoreExistingVpnSessionAsync(): Promise<void> {
    if (this.vpnManager.getFilesDir().length === 0) {
      return;
    }
    const healthy: boolean = await this.vpnManager.isSessionHealthy();
    if (!healthy) {
      return;
    }
    this.isRunning = true;
    this.managedRuntime = true;
    this.vpnEnabled = true;
    this.coreStatus = 'connected';
    this.core.setVpnTunnelActive(true);
    this.core.setRuntimeProxyPort(this.mixedPort);
    const startedAt: number = this.vpnManager.getSessionStartedAt();
    this.runTimeSeconds = startedAt > 0 ? Math.max(0, Math.floor((Date.now() - startedAt) / 1000)) : 0;
    this.lastTrafficSampleAt = 0;
    this.reportBackgroundError();
    this.appendLog('info', 'VPN', 'LexiVpnExtension', 'Reattached to running VPN session');
    this.notify(false);
    this.refreshOutboundIp();
  }

  private async restoreSummaryFromNativeAsync(profile: ProfileSubscriptionModel): Promise<void> {
    const summary: ParsedYamlSummary | null = await this.parseWithNativeFallback(profile.yamlContent);
    if (summary !== null && summary.valid && this.currentProfileId === profile.id) {
      this.applyParsedProfileToRuntime(summary);
      this.notify(false);
    }
  }

  private async parseWithNativeFallback(rawContent: string): Promise<ParsedYamlSummary | null> {
    if (!this.core.hasOfflineNativeProbes()) {
      return null;
    }
    const previewRaw: string = await this.core.inspectProfileNative(rawContent);
    if (previewRaw.length === 0) {
      return null;
    }
    try {
      const parsedObj: Record<string, Object> = JSON.parse(previewRaw) as Record<string, Object>;
      if (typeof parsedObj['error'] === 'string' && String(parsedObj['error']).length > 0) {
        return null;
      }
      const rawEntries: Array<Record<string, Object>> = Array.isArray(parsedObj['entries'])
        ? (parsedObj['entries'] as Array<Record<string, Object>>)
        : [];
      const rawGroups: Array<Record<string, Object>> = Array.isArray(parsedObj['groups'])
        ? (parsedObj['groups'] as Array<Record<string, Object>>)
        : [];
      if (rawEntries.length === 0 && rawGroups.length === 0) {
        return null;
      }
      const nodes: ProxyNodeItem[] = [];
      for (let i: number = 0; i < rawEntries.length; i++) {
        const e: Record<string, Object> = rawEntries[i];
        const name: string = String(e['name'] ?? '');
        const kind: string = String(e['type'] ?? 'Proxy');
        if (name.length === 0 || name === 'DIRECT' || name === 'REJECT') {
          continue;
        }
        nodes.push({
          id: `node_${i}_${name}`,
          name: name,
          protocol: kind.length > 0 ? kind : 'Proxy',
          regionCode: YamlProfileParser.inferRegionFromName(name),
          server: 'mihomo',
          port: 443,
          udp: true,
          delayMs: Number(e['delay'] ?? 0),
          isTesting: false,
          providerName: 'Profile'
        });
      }
      const groups: ProxyGroupItem[] = [];
      for (let i: number = 0; i < rawGroups.length; i++) {
        const g: Record<string, Object> = rawGroups[i];
        const gName: string = String(g['name'] ?? '');
        const rawType: string = String(g['type'] ?? 'select').toLowerCase();
        const allMembers: string[] = Array.isArray(g['all'])
          ? (g['all'] as Object[]).map((item: Object): string => String(item))
          : [];
        if (gName.length === 0 || allMembers.length === 0) {
          continue;
        }
        const groupType: 'Selector' | 'URLTest' | 'Fallback' | 'LoadBalance' =
          rawType === 'urltest' || rawType === 'url-test' ? 'URLTest'
            : rawType === 'fallback' ? 'Fallback'
              : rawType === 'load-balance' || rawType === 'loadbalance' ? 'LoadBalance'
                : 'Selector';
        const nowName: string = String(g['now'] ?? '');
        const defaultPick: string = (nowName.length > 0 && allMembers.includes(nowName))
          ? nowName
          : YamlProfileParser.pickDefaultSelected(allMembers);
        groups.push({
          id: `grp_${i}_${gName}`,
          name: gName,
          groupType: groupType,
          iconText: gName.substring(0, 1).toUpperCase(),
          selectedName: defaultPick,
          fixedName: '',
          testUrl: this.testUrl,
          isTestingGroup: false,
          nodeNames: allMembers,
          hidden: false
        });
      }
      return {
        valid: nodes.length > 0 || groups.length > 0,
        errorMessage: '',
        mixedPort: 7890,
        allowLan: false,
        mode: this.outboundMode,
        ipv6: false,
        proxiesCount: nodes.length,
        groupsCount: groups.length,
        rulesCount: 1,
        parsedNodes: nodes,
        parsedGroups: groups
      };
    } catch (_err) {
      return null;
    }
  }

  private startLiveTicker(): void {
    if (this.tickerId !== -1) {
      return;
    }
    this.tickerId = setInterval((): void => {
      if (this.isRunning) {
        if (this.hasManagedRuntime()) {
          const startedAt: number = this.vpnManager.getSessionStartedAt();
          this.runTimeSeconds = startedAt > 0 ? Math.max(0, Math.floor((Date.now() - startedAt) / 1000)) : this.runTimeSeconds + 1;
          this.pollLiveVpnStatsAsync();
        } else {
          this.runTimeSeconds += 1;
          this.memorySnapshot = this.core.queryMemoryStats(true);
        }
        this.notify(false);
      }
    }, 1000);
  }

  private reportBackgroundError(): void {
    const warning: string = this.vpnManager.getBackgroundError();
    if (warning.length > 0 && warning !== this.lastOperationError) {
      this.lastOperationError = warning;
      this.appendLog('warning', 'VPN', 'Background', warning);
    }
  }

  private async pollLiveVpnStatsAsync(): Promise<void> {
    if (this.isPollingLiveStats || !this.isRunning || !this.hasManagedRuntime() ||
      this.isVpnTransitioning) {
      return;
    }
    this.isPollingLiveStats = true;
    try {
      this.reportBackgroundError();
      const status: LexiVpnRuntimeStatus = this.vpnManager.getRuntimeStatus();
      if (status.status === 'stopped' || status.status === 'error') {
        this.isRunning = false;
        this.vpnEnabled = false;
        this.managedRuntime = false;
        this.coreStatus = 'disconnected';
        this.core.setVpnTunnelActive(false);
        this.core.setRuntimeProxyPort(0);
        this.vpnManager.stopKeepAlive();
        this.currentUploadSpeed = 0;
        this.currentDownloadSpeed = 0;
        if (status.error.length > 0) {
          this.lastOperationError = status.error;
        }
        this.notify(false);
        return;
      }
      const snap: LexiControllerTraffic = await this.vpnManager.getConnectionsSnapshot();
      const now: number = Date.now();
      const validWindow: boolean = this.lastTrafficSampleAt > 0 &&
        now > this.lastTrafficSampleAt &&
        now - this.lastTrafficSampleAt < 10000 &&
        snap.uploadTotal >= this.lastUploadTotalSample &&
        snap.downloadTotal >= this.lastDownloadTotalSample;
      const elapsedSec: number = Math.max(0.001, (now - this.lastTrafficSampleAt) / 1000);
      const upSpeed: number = validWindow ? (snap.uploadTotal - this.lastUploadTotalSample) / elapsedSec : 0;
      const downSpeed: number = validWindow ? (snap.downloadTotal - this.lastDownloadTotalSample) / elapsedSec : 0;
      this.currentUploadSpeed = Math.max(0, Math.round(upSpeed));
      this.currentDownloadSpeed = Math.max(0, Math.round(downSpeed));
      this.peakUploadSpeed = Math.max(this.peakUploadSpeed, this.currentUploadSpeed);
      this.peakDownloadSpeed = Math.max(this.peakDownloadSpeed, this.currentDownloadSpeed);
      this.totalUploadBytes = snap.uploadTotal;
      this.totalDownloadBytes = snap.downloadTotal;
      this.lastUploadTotalSample = snap.uploadTotal;
      this.lastDownloadTotalSample = snap.downloadTotal;
      this.lastTrafficSampleAt = now;
      this.uploadWaveHistory = this.uploadWaveHistory.slice(1).concat([this.currentUploadSpeed]);
      this.downloadWaveHistory = this.downloadWaveHistory.slice(1).concat([this.currentDownloadSpeed]);

      const mappedConnections: TrackerRecordItem[] = [];
      for (let i: number = 0; i < snap.connections.length; i++) {
        const entry: Record<string, Object> = snap.connections[i];
        const metaRaw: Object | undefined = entry['metadata'];
        const meta: Record<string, Object> = (metaRaw !== undefined && metaRaw !== null && typeof metaRaw === 'object')
          ? (metaRaw as Record<string, Object>)
          : ({} as Record<string, Object>);
        const chainsRaw: Object[] = Array.isArray(entry['chains']) ? (entry['chains'] as Object[]) : [];
        const chainStrings: string[] = chainsRaw.map((c: Object): string => String(c));
        const exitNode: string = chainStrings.length > 0 ? chainStrings[chainStrings.length - 1] : 'DIRECT';
        const netUpper: string = String(meta['network'] ?? 'TCP').toUpperCase();
        const netType: 'TCP' | 'UDP' = netUpper === 'UDP' ? 'UDP' : 'TCP';
        const srcName: string = String(meta['process'] ?? meta['sourceIP'] ?? 'System');
        const dstIp: string = String(meta['destinationIP'] ?? '');
        const hostName: string = String(meta['host'] ?? (dstIp.length > 0 ? dstIp : 'unknown'));
        const item: TrackerRecordItem = {
          id: String(entry['id'] ?? `${i}`),
          sourceProcess: srcName,
          sourceIconLetter: srcName.length > 0 ? srcName.substring(0, 1).toUpperCase() : 'S',
          targetHost: hostName,
          destinationIp: dstIp,
          network: netType,
          ruleName: String(entry['rule'] ?? 'MATCH'),
          rulePayload: String(entry['rulePayload'] ?? ''),
          exitNodeName: exitNode,
          exitRegionCode: YamlProfileParser.inferRegionFromName(exitNode),
          downloadBytes: Number(entry['download'] ?? 0),
          uploadBytes: Number(entry['upload'] ?? 0),
          downloadSpeed: 0,
          uploadSpeed: 0,
          startTimeText: String(entry['start'] ?? ''),
          durationSeconds: 0,
          asnInfo: String(meta['type'] ?? ''),
          proxyChain: chainStrings,
          isActive: true
        };
        mappedConnections.push(item);
      }
      this.liveConnections = mappedConnections;
      if (mappedConnections.length > 0) {
        const seenIds: Set<string> = new Set<string>();
        for (let i: number = 0; i < this.recentRequests.length; i++) {
          seenIds.add(this.recentRequests[i].id);
        }
        const newlyAdded: TrackerRecordItem[] = [];
        for (let i: number = 0; i < mappedConnections.length; i++) {
          const item: TrackerRecordItem = mappedConnections[i];
          if (!seenIds.has(item.id)) {
            seenIds.add(item.id);
            newlyAdded.push(item);
          }
        }
        if (newlyAdded.length > 0) {
          this.recentRequests = newlyAdded.concat(this.recentRequests).slice(0, 200);
        }
      }
      this.recentRequestsCount = this.recentRequests.length;
      this.dnsQueriesCount = this.dnsQueries.length;
      this.notify(false);
    } catch (_err) {
      // Transient controller query failures must not tear down VPN UI state immediately.
    } finally {
      this.isPollingLiveStats = false;
    }
  }

  getAppAccessPolicy(): LexiAppAccessPolicy {
    return { enabled: this.accessControlEnabled, mode: this.accessControlMode,
      bundleNames: this.appAccessList.filter((app: AppAccessItem): boolean => app.isSelected)
        .map((app: AppAccessItem): string => app.bundleName) };
  }

  getTunSettings(): LexiTunSettings {
    return { stack: this.tunStack, mtu: this.tunMtu };
  }

  getActiveTunSettings(): LexiTunSettings {
    return this.vpnManager.getRuntimeStatus().tun ?? TunConfig.defaults();
  }

  setTunSettings(stack: LexiTunStack, mtu: number): string {
    if (this.isVpnTransitioning) { return 'VPN 正在连接，请稍后修改'; }
    const settings: LexiTunSettings = { stack: stack, mtu: mtu };
    const error: string = TunConfig.validationError(settings);
    if (error.length > 0) { return error; }
    this.tunStack = stack;
    this.tunMtu = mtu;
    this.notify();
    return '';
  }

  hasPendingTunChanges(): boolean {
    if (!this.isRunning || !this.vpnEnabled) { return false; }
    const applied: LexiTunSettings = this.getActiveTunSettings();
    return TunConfig.fingerprint(applied) !== TunConfig.fingerprint(this.getTunSettings());
  }

  hasManagedRuntime(): boolean {
    return this.managedRuntime || this.vpnEnabled;
  }

  async applyTunSettingsAsync(): Promise<boolean> {
    const error: string = TunConfig.validationError(this.getTunSettings());
    if (error.length > 0) { this.lastOperationError = error; this.notify(false); return false; }
    if (this.isVpnTransitioning) { return false; }
    this.persistState();
    if (!this.isRunning || !this.vpnEnabled) { return true; }
    if (!this.hasPendingTunChanges() && !this.hasPendingAppAccessChanges()) { return true; }
    return this.toggleRunningAsync(true);
  }

  hasPendingAppAccessChanges(): boolean {
    if (!this.isRunning || !this.vpnEnabled) { return false; }
    const applied: LexiAppAccessPolicy = this.vpnManager.getRuntimeStatus().accessControl ?? AppAccessControl.unrestricted();
    return AppAccessControl.fingerprint(applied) !== AppAccessControl.fingerprint(this.getAppAccessPolicy());
  }

  setAppAccessEnabled(nextEnabled: boolean): void {
    if (this.isVpnTransitioning) { return; }
    this.accessControlEnabled = nextEnabled;
    this.notify();
  }

  setAppAccessMode(nextMode: LexiAppAccessMode): void {
    if (this.isVpnTransitioning) { return; }
    this.accessControlMode = nextMode;
    this.notify();
  }

  addAppAccessEntry(bundleInput: string, nameInput: string): string {
    if (this.isVpnTransitioning) { return 'VPN 正在连接，请稍后修改'; }
    const bundleName: string = bundleInput.trim();
    if (!AppAccessControl.isBundleName(bundleName)) { return '请输入正确的应用包名，例如 com.example.app'; }
    if (this.appAccessList.some((app: AppAccessItem): boolean => app.bundleName === bundleName)) {
      return '该应用已在列表中';
    }
    if (this.appAccessList.length >= AppAccessControl.MAX_APPS) { return '最多可添加 256 个应用'; }
    const appName: string = nameInput.trim().slice(0, 64) || bundleName;
    this.appAccessList.push({ bundleName: bundleName, appName: appName, iconLetter: appName.charAt(0),
      iconBgColor: '', isSystemApp: false, isSelected: true });
    this.notify();
    return '';
  }

  setAppAccessSelected(bundleName: string, nextSelected: boolean): void {
    if (this.isVpnTransitioning) { return; }
    const app: AppAccessItem | undefined = this.appAccessList.find((entry: AppAccessItem): boolean =>
      entry.bundleName === bundleName);
    if (app) { app.isSelected = nextSelected; this.notify(); }
  }

  removeAppAccessEntry(bundleName: string): void {
    if (this.isVpnTransitioning) { return; }
    this.appAccessList = this.appAccessList.filter((app: AppAccessItem): boolean => app.bundleName !== bundleName);
    this.notify();
  }

  async applyAppAccessChangesAsync(): Promise<boolean> {
    if (this.isVpnTransitioning) { return false; }
    const error: string = AppAccessControl.validationError(this.getAppAccessPolicy());
    if (error.length > 0) { this.lastOperationError = error; this.notify(false); return false; }
    this.persistState();
    if (!this.isRunning || !this.hasManagedRuntime() ||
      (!this.hasPendingAppAccessChanges() && !this.hasPendingTunChanges())) { return true; }
    // Recreate the system connection: a mihomo YAML reload cannot update per-app routes.
    // Starting directly preserves the active proxy-chain draft and selected exit.
    return this.toggleRunningAsync(true);
  }

  async toggleRunningAsync(reconnect: boolean = false): Promise<boolean> {
    if (this.isVpnTransitioning) {
      return this.isRunning;
    }
    this.lastOperationError = '';
    if (!this.isRunning || reconnect) {
      const accessError: string = AppAccessControl.validationError(this.getAppAccessPolicy());
      if (accessError.length > 0) { this.lastOperationError = accessError; this.notify(false); return false; }
      const tunError: string = TunConfig.validationError(this.getTunSettings());
      if (tunError.length > 0) { this.lastOperationError = tunError; this.notify(false); return false; }
      if (this.profiles.length === 0) {
        this.lastOperationError = '请先添加配置';
        this.notify(false);
        return false;
      }
      if (!this.core.isReady()) {
        this.lastOperationError = this.core.getUnavailableReason();
        this.appendLog('error', 'Core', 'Start', this.lastOperationError);
        this.notify(false);
        return false;
      }
      if (!this.core.supportsVpnPrivacy()) {
        this.lastOperationError = '当前原生内核不支持防泄露策略，请安装包含新版内核的应用';
        this.notify(false);
        return false;
      }
      const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
      if (profile === null) {
        this.lastOperationError = '当前配置不存在';
        this.notify(false);
        return false;
      }
      let yamlToRun: string = this.buildVpnRuntimeYaml(profile.yamlContent);
      if ((this.chainConnected || this.isChainConnecting) && this.getProxyChainValidationError().length === 0) {
        const compiled: LexiChainBuildResult = ProxyChainConfig.build(yamlToRun,
          this.isChainConnecting ? this.getProxyChainDraft().nodeNames : this.connectedChainNames);
        if (compiled.errorMessage.length === 0 && compiled.yamlContent.length > 0) {
          yamlToRun = compiled.yamlContent;
        }
      }
      const selectedMap: Record<string, string> = this.buildSelectedMap(yamlToRun, profile.id);

      this.isVpnTransitioning = true;
      this.coreStatus = 'connecting';
      this.notify(false);
      try {
        await this.vpnManager.startVpn(yamlToRun, selectedMap, this.getAppAccessPolicy(), this.getTunSettings());
        this.isRunning = true;
        this.vpnEnabled = true;
        this.managedRuntime = true;
        this.coreStatus = 'connected';
        this.core.setVpnTunnelActive(true);
        this.core.setRuntimeProxyPort(this.mixedPort);
        const startedAt: number = this.vpnManager.getSessionStartedAt();
        this.runTimeSeconds = startedAt > 0 ? Math.max(0, Math.floor((Date.now() - startedAt) / 1000)) : 0;
        this.lastTrafficSampleAt = 0;
        this.lastUploadTotalSample = 0;
        this.lastDownloadTotalSample = 0;
        this.appendLog('info', 'Core', 'Runtime', 'VPN TUN & mihomo connected');
        this.notify();
        this.refreshOutboundIp();
        this.recheckAllServices();
        return true;
      } catch (err) {
        this.isRunning = false;
        this.vpnEnabled = false;
        this.managedRuntime = false;
        this.coreStatus = 'disconnected';
        this.core.setVpnTunnelActive(false);
        this.core.setRuntimeProxyPort(0);
        this.lastOperationError = err instanceof Error ? err.message : String(err);
        this.appendLog('error', 'VPN', 'Start', this.lastOperationError);
        this.notify(false);
        return false;
      } finally {
        this.isVpnTransitioning = false;
        this.notify(false);
      }
    } else {
      this.isVpnTransitioning = true;
      this.notify(false);
      try {
        await this.vpnManager.stopVpn();
      } catch (err) {
        this.lastOperationError = err instanceof Error ? err.message : String(err);
        this.appendLog('error', 'VPN', 'Stop', this.lastOperationError);
      } finally {
        this.isVpnTransitioning = false;
        this.isRunning = false;
        this.vpnEnabled = false;
        this.managedRuntime = false;
        this.coreStatus = 'disconnected';
        this.core.setVpnTunnelActive(false);
        this.core.setRuntimeProxyPort(0);
        this.runTimeSeconds = 0;
        this.currentUploadSpeed = 0;
        this.currentDownloadSpeed = 0;
        this.liveConnections = [];
        this.chainConnected = false;
        this.connectedChainNames = [];
        this.appendLog('info', 'VPN', 'LexiVpnExtension', 'VPN stopped');
        this.notify();
      }
      return true;
    }
  }

  toggleRunning(): boolean {
    this.lastOperationError = '';
    if (!this.isRunning && this.profiles.length === 0) {
      this.lastOperationError = '请先添加配置';
      return false;
    }
    if (!this.isRunning && !this.core.isReady()) {
      this.lastOperationError = this.core.getUnavailableReason();
      this.appendLog('error', 'Core', 'Start', this.lastOperationError);
      this.notify(false);
      return false;
    }
    if (!this.isRunning) {
      const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
      if (profile === null) { return false; }
      const setupError: string = this.setupRuntimeYaml(profile.yamlContent);
      if (setupError.length > 0) { this.lastOperationError = setupError; return false; }
    }
    const error: string = this.core.execute(this.isRunning ? CoreMethodNames.LISTENER_STOP : CoreMethodNames.LISTENER_START);
    if (error.length > 0) { this.lastOperationError = error; return false; }
    this.isRunning = !this.isRunning;
    if (this.isRunning) {
      this.coreStatus = 'connected';
      this.runTimeSeconds = 0;
      this.memorySnapshot = this.core.queryMemoryStats(true);
      this.appendLog('info', 'Core', 'mihomo', 'Listener started on 127.0.0.1:' + this.mixedPort);
      this.refreshOutboundIp();
      this.recheckAllServices();
    } else {
      this.coreStatus = 'disconnected';
      this.runTimeSeconds = 0;
      this.currentUploadSpeed = 0;
      this.currentDownloadSpeed = 0;
      this.memorySnapshot = this.core.queryMemoryStats(false);
      this.chainConnected = false;
      this.connectedChainNames = [];
      this.appendLog('info', 'Core', 'mihomo', 'Listener stopped');
    }
    this.notify();
    return true;
  }

  restartCore(): void {
    const wasRunning: boolean = this.isRunning;
    if (wasRunning && !this.toggleRunning()) { return; }
    this.core.initCore(this.coreHomeDir);
    this.lastOperationError = this.core.getUnavailableReason();
    if (wasRunning && this.core.isReady()) { this.toggleRunning(); }
    this.notify(false);
  }

  private async applyOutboundModeWhileVpnRunningAsync(mode: OutboundModeType, needDisconnectChain: boolean): Promise<void> {
    try {
      if (needDisconnectChain) {
        const err: string = await this.disconnectProxyChainAsync();
        if (err.length > 0) {
          this.lastOperationError = err;
          this.notify(false);
          return;
        }
      }
      const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
      if (profile === null) { throw new Error('当前配置不存在'); }
      const yaml: string = this.buildVpnRuntimeYaml(profile.yamlContent);
      await this.vpnManager.reloadRuntimeConfig(yaml, this.buildSelectedMap(yaml, profile.id), mode);
      if (mode === 'global') {
        const globalTarget: string = this.resolvePreferredGlobalTarget();
        if (globalTarget.length > 0) {
          await this.vpnManager.selectProxy('GLOBAL', globalTarget);
          this.rememberProxySelection('GLOBAL', globalTarget);
        }
      }
      try {
        await this.vpnManager.closeAllConnections();
      } catch (_closeErr) {
        // ignore benign close errors
      }
      this.liveConnections = [];
      this.notify();
      this.refreshOutboundIp();
      this.recheckAllServices();
    } catch (err) {
      this.lastOperationError = err instanceof Error ? err.message : String(err);
      this.notify(false);
    }
  }

  setOutboundMode(mode: OutboundModeType): void {
    if (this.isChainConnecting || this.isVpnTransitioning) { return; }
    this.lastOperationError = '';
    if (this.outboundMode === mode) {
      return;
    }
    if (this.isRunning && this.hasManagedRuntime()) {
      const wasChained: boolean = this.chainConnected;
      this.outboundMode = mode;
      this.appendLog('info', 'Config', 'Mode', `Outbound mode set to ${mode}`);
      this.notify();
      this.applyOutboundModeWhileVpnRunningAsync(mode, wasChained);
      return;
    }
    if (this.chainConnected) {
      const error: string = this.disconnectProxyChain();
      if (error.length > 0) { this.lastOperationError = error; return; }
    }
    if (this.isRunning) {
      const error: string = this.core.execute(CoreMethodNames.CONFIG_UPDATE, JSON.stringify({ mode: mode }));
      if (error.length > 0) { this.lastOperationError = error; return; }
    }
    this.outboundMode = mode;
    if (this.isRunning) {
      this.appendLog('info', 'Config', 'Mode', `Outbound mode set to ${mode}`);
    }
    this.notify();
  }

  async refreshOutboundIp(): Promise<void> {
    if (this.isProbingIp) {
      return;
    }
    this.isProbingIp = true;
    this.outboundProbeFailed = false;
    this.notify();

    const info: OutboundIpModel | null = this.isRunning ? await this.core.probeOutboundIpInfo() : null;
    if (info !== null) {
      this.outboundIpInfo = info;
      this.outboundProbeFailed = false;
    } else {
      this.outboundProbeFailed = true;
    }
    this.isProbingIp = false;
    this.notify();
  }

  async recheckAllServices(): Promise<void> {
    const requested: string[] = [];
    for (let i: number = 0; i < this.serviceProbes.length; i++) {
      const item: ServiceProbeItem = this.serviceProbes[i];
      if (item.enabled) { item.status = 'checking'; requested.push(item.id.substring(4)); }
    }
    this.notify(false);
    const results: LexiServiceCheckResult[] = this.isRunning
      ? await this.core.probeServiceAvailability(requested) : [];
    for (let i: number = 0; i < this.serviceProbes.length; i++) {
      const item: ServiceProbeItem = this.serviceProbes[i];
      if (!item.enabled) { continue; }
      const result: LexiServiceCheckResult | undefined = results.find((entry: LexiServiceCheckResult): boolean => entry.name === item.id.substring(4));
      item.status = result?.status === 'available' ? 'available'
        : (result && ['restricted', 'blocked', 'unsupported-region', 'disallowed-isp', 'originals-only'].includes(result.status) ? 'restricted' : 'unavailable');
      item.delayMs = result?.delay ?? -1;
      item.regionCode = result?.region ?? '';
    }
    this.notify(false);
  }

  releaseMemoryGC(): number {
    this.lastOperationError = this.core.forceGC();
    if (this.lastOperationError.length > 0) { return 0; }
    const beforeBytes: number = this.memorySnapshot.appBytes + this.memorySnapshot.coreRssBytes;
    this.memorySnapshot = this.core.queryMemoryStats(this.isRunning);
    const afterBytes: number = this.memorySnapshot.appBytes + this.memorySnapshot.coreRssBytes;
    this.notify();
    return Math.max(0, beforeBytes - afterBytes);
  }

  getGroupById(groupId: string): ProxyGroupItem | null {
    for (let i = 0; i < this.proxyGroups.length; i++) {
      if (this.proxyGroups[i].id === groupId) {
        return this.proxyGroups[i];
      }
    }
    return groupId.length === 0 && this.proxyGroups.length > 0 ? this.proxyGroups[0] : null;
  }

  selectCurrentGroup(groupId: string): void {
    const grp: ProxyGroupItem | null = this.getGroupById(groupId);
    if (grp === null || this.currentGroupId === grp.id) {
      return;
    }
    this.currentGroupId = grp.id;
    this.notify(false);
  }

  private groupHasDirectProxyNodes(group: ProxyGroupItem): boolean {
    for (let i: number = 0; i < group.nodeNames.length; i++) {
      const node: ProxyNodeItem | null = this.getNodeByName(group.nodeNames[i]);
      if (node !== null && node.port > 0 && node.providerName !== 'Group') {
        return true;
      }
    }
    return false;
  }

  private resolveLeafSelectedNodeName(groupName: string, depth: number = 0): string {
    if (depth > 8 || groupName.length === 0) {
      return '';
    }
    const grp: ProxyGroupItem | undefined = this.proxyGroups.find(
      (candidate: ProxyGroupItem): boolean => candidate.name === groupName
    );
    if (grp === undefined) {
      return '';
    }
    const picked: string = grp.selectedName;
    if (picked.length === 0) {
      return '';
    }
    const subGroup: ProxyGroupItem | undefined = this.proxyGroups.find(
      (candidate: ProxyGroupItem): boolean => candidate.name === picked
    );
    if (subGroup !== undefined) {
      return this.resolveLeafSelectedNodeName(subGroup.name, depth + 1);
    }
    return picked;
  }

  getImportedProfileNodes(): ProxyNodeItem[] {
    return this.proxyNodes.filter((node: ProxyNodeItem): boolean =>
      node.port > 0 && node.providerName !== 'Group' && node.name !== 'DIRECT' && node.name !== 'REJECT'
    );
  }

  getActiveSelectedProxyNode(): ProxyNodeItem | null {
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    let candidateName: string = '';
    if (this.outboundMode === 'global') {
      const globalPick: LexiSavedProxySelection | undefined = this.selections.find(
        (s: LexiSavedProxySelection): boolean => s.profileId === this.currentProfileId && s.groupName === 'GLOBAL'
      );
      if (globalPick !== undefined && globalPick.nodeName.length > 0) {
        candidateName = globalPick.nodeName;
      }
    }
    if (candidateName.length === 0 && draft.targetGroup.length > 0) {
      candidateName = this.resolveLeafSelectedNodeName(draft.targetGroup);
    }
    if (candidateName.length === 0) {
      const viewedGroup: ProxyGroupItem | null = this.getGroupById(this.currentGroupId);
      if (viewedGroup !== null) {
        candidateName = this.resolveLeafSelectedNodeName(viewedGroup.name);
      }
    }
    if (candidateName.length > 0) {
      const exact: ProxyNodeItem | null = this.getNodeByName(candidateName);
      if (exact !== null && exact.port > 0 && exact.providerName !== 'Group') {
        return exact;
      }
    }
    const imported: ProxyNodeItem[] = this.getImportedProfileNodes();
    return imported.length > 0 ? imported[0] : null;
  }

  getProxyChainDraft(): LexiProxyChainDraft {
    for (let i: number = 0; i < this.chains.length; i++) {
      if (this.chains[i].profileId === this.currentProfileId) { return this.chains[i]; }
    }
    const viewedGroup: ProxyGroupItem | null = this.getGroupById(this.currentGroupId);
    let defaultGroup: string = '';
    if (viewedGroup !== null && viewedGroup.groupType === 'Selector' && this.groupHasDirectProxyNodes(viewedGroup)) {
      defaultGroup = viewedGroup.name;
    } else {
      const firstDirectSelector: ProxyGroupItem | undefined = this.proxyGroups.find(
        (group: ProxyGroupItem): boolean => group.groupType === 'Selector' && this.groupHasDirectProxyNodes(group)
      );
      if (firstDirectSelector !== undefined) {
        defaultGroup = firstDirectSelector.name;
      } else {
        const first: ProxyGroupItem | undefined = this.proxyGroups.find(
          (group: ProxyGroupItem): boolean => group.groupType === 'Selector'
        );
        defaultGroup = first?.name ?? '';
      }
    }
    const draft: LexiProxyChainDraft = { profileId: this.currentProfileId, targetGroup: defaultGroup, nodeNames: [] };
    if (this.currentProfileId.length > 0) { this.chains.push(draft); }
    return draft;
  }

  getChainCandidates(): ProxyNodeItem[] {
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    const group: ProxyGroupItem | undefined = this.proxyGroups.find((candidate: ProxyGroupItem): boolean => candidate.name === draft.targetGroup);
    return this.proxyNodes.filter((node: ProxyNodeItem): boolean => node.port > 0 && node.providerName !== 'Group' &&
      (this.outboundMode === 'global' || (group !== undefined && group.nodeNames.includes(node.name))));
  }

  addProxyChainNode(nodeName: string): string {
    if (this.isChainConnecting || this.isVpnTransitioning) { return '正在应用代理链，请稍后修改'; }
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    if (draft.nodeNames.includes(nodeName)) { return '不能重复添加同一个节点'; }
    if (!this.getChainCandidates().some((node: ProxyNodeItem): boolean => node.name === nodeName)) {
      return '只能添加当前代理组中的独立代理节点';
    }
    draft.nodeNames = draft.nodeNames.concat([nodeName]);
    this.notify();
    return '';
  }

  moveProxyChainNode(fromIndex: number, toIndex: number): void {
    if (this.isChainConnecting || this.isVpnTransitioning) { return; }
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    if (fromIndex < 0 || fromIndex >= draft.nodeNames.length || toIndex < 0 || toIndex >= draft.nodeNames.length) { return; }
    const next: string[] = draft.nodeNames.slice();
    const moved: string = next.splice(fromIndex, 1)[0];
    next.splice(toIndex, 0, moved);
    draft.nodeNames = next;
    this.notify();
  }

  removeProxyChainNode(nodeName: string): void {
    if (this.isChainConnecting || this.isVpnTransitioning) { return; }
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    draft.nodeNames = draft.nodeNames.filter((candidate: string): boolean => candidate !== nodeName);
    this.notify();
  }

  setProxyChainGroup(groupName: string): string {
    if (this.isChainConnecting || this.isVpnTransitioning) { return '正在应用代理链，请稍后修改'; }
    if (this.getProxyChainDraft().targetGroup === groupName) { return ''; }
    if (this.chainConnected) {
      if (this.hasManagedRuntime()) {
        this.disconnectProxyChainAsync();
      } else {
        const error: string = this.disconnectProxyChain();
        if (error.length > 0) { return error; }
      }
    }
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    draft.targetGroup = groupName;
    draft.nodeNames = [];
    this.notify();
    return '';
  }

  clearProxyChain(): string {
    if (this.isChainConnecting || this.isVpnTransitioning) { return '正在应用代理链，请稍后修改'; }
    if (this.chainConnected) {
      if (this.hasManagedRuntime()) {
        this.disconnectProxyChainAsync();
      } else {
        const error: string = this.disconnectProxyChain();
        if (error.length > 0) { return error; }
      }
    }
    this.getProxyChainDraft().nodeNames = [];
    this.notify();
    return '';
  }

  buildProxyChainPreview(): LexiChainBuildResult {
    const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
    if (profile === null) { return { yamlContent: '', errorMessage: '请先添加配置' }; }
    const names: string[] = this.getProxyChainDraft().nodeNames;
    const exit: string = names.length > 0 ? names[names.length - 1] : '';
    return ProxyChainConfig.build(this.runtimeYaml(profile.yamlContent, exit), names);
  }

  getProxyChainValidationError(): string {
    if (this.outboundMode === 'direct') { return '直连模式无法使用链式代理，请切换为规则或全局模式'; }
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    if (draft.nodeNames.length < 2) { return '至少添加两个节点'; }
    if (this.outboundMode === 'rule') {
      const group: ProxyGroupItem | undefined = this.proxyGroups.find((candidate: ProxyGroupItem): boolean => candidate.name === draft.targetGroup);
      if (group === undefined || group.groupType !== 'Selector') { return '请选择一个手动选择代理组'; }
    }
    const candidates: string[] = this.getChainCandidates().map((node: ProxyNodeItem): string => node.name);
    if (draft.nodeNames.some((name: string): boolean => !candidates.includes(name))) { return '链中包含已失效或不属于当前代理组的节点，请移除后重选'; }
    return this.buildProxyChainPreview().errorMessage;
  }

  getProxyChainUdpWarning(): string {
    const names: string[] = this.getProxyChainDraft().nodeNames;
    const limited: string[] = names.filter((name: string): boolean => {
      const node: ProxyNodeItem | null = this.getNodeByName(name);
      return node !== null && (!node.udp || node.protocol.toLowerCase() === 'http');
    });
    return limited.length > 0 ? '链中存在仅支持 TCP 或关闭 UDP 的节点：' + limited.join('、') + '。不支持的 UDP 将被拒绝，不会回落直连。' : '';
  }

  isProxyChainDraftApplied(): boolean {
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    return this.chainConnected && this.connectedChainMode === this.outboundMode &&
      this.connectedChainGroup === (this.outboundMode === 'global' ? 'GLOBAL' : draft.targetGroup) &&
      JSON.stringify(this.connectedChainNames) === JSON.stringify(draft.nodeNames);
  }

  setChainWarningAcknowledged(accepted: boolean): void {
    this.chainWarningAcknowledged = accepted;
    this.notify();
  }

  private async restartVpnAfterConfigChangeAsync(): Promise<void> {
    if (!this.isRunning || !this.hasManagedRuntime()) {
      return;
    }
    const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
    if (profile !== null) {
      let yamlToRun: string = this.buildVpnRuntimeYaml(profile.yamlContent);
      if ((this.chainConnected || this.isChainConnecting) && this.getProxyChainValidationError().length === 0) {
        const compiled: LexiChainBuildResult = ProxyChainConfig.build(yamlToRun,
          this.isChainConnecting ? this.getProxyChainDraft().nodeNames : this.connectedChainNames);
        if (compiled.errorMessage.length === 0 && compiled.yamlContent.length > 0) {
          yamlToRun = compiled.yamlContent;
        }
      }
      const selectedMap: Record<string, string> = this.buildSelectedMap(yamlToRun, profile.id);
      try {
        if (await this.vpnManager.isSessionHealthy()) {
          await this.vpnManager.reloadRuntimeConfig(yamlToRun, selectedMap, this.outboundMode);
          this.liveConnections = [];
          this.refreshOutboundIp();
          return;
        }
      } catch (reloadError) {
        // Keep the established tunnel and last valid policy on rejected reloads.
        this.lastOperationError = '配置未应用，已保留当前 VPN：' + String(reloadError);
        this.notify(false);
        return;
      }
    }
    // A control-plane outage must not tear down an otherwise capturing VPN.
    // Keep its routes installed until the user explicitly reconnects.
    this.lastOperationError = '控制器暂不可用，已保留当前 VPN；请恢复连接后重试';
    this.notify(false);
  }

  private async disconnectChainAndSelectAsync(targetGroup: string, nodeName: string): Promise<void> {
    const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
    if (profile === null) { return; }
    const cleared: LexiChainBuildResult = ProxyChainConfig.build(this.runtimeYaml(profile.yamlContent), []);
    const nextYaml: string = cleared.errorMessage.length === 0 && cleared.yamlContent.length > 0
      ? cleared.yamlContent
      : this.runtimeYaml(profile.yamlContent);
    this.chainConnected = false;
    this.connectedChainNames = [];
    const selectedMap: Record<string, string> = this.buildSelectedMap(nextYaml, profile.id);
    selectedMap[targetGroup] = nodeName;
    try {
      await this.vpnManager.reloadRuntimeConfig(nextYaml, selectedMap, this.outboundMode, targetGroup, nodeName);
      this.liveConnections = [];
      this.appendLog('info', 'ProxyChain', targetGroup, `已断开链式代理并切换为 ${nodeName}`);
      this.refreshOutboundIp();
    } catch (err) {
      this.lastOperationError = err instanceof Error ? err.message : String(err);
    }
    this.notify();
  }

  async connectProxyChainAsync(): Promise<string> {
    if (this.isChainConnecting || this.isVpnTransitioning) { return '连接正在更新，请稍后重试'; }
    const invalid: string = this.getProxyChainValidationError();
    if (invalid.length > 0) { return invalid; }
    if (!this.core.isReady()) { return this.core.getUnavailableReason(); }
    const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
    if (profile === null) { return '请先添加配置'; }
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    const chainNames: string[] = draft.nodeNames.slice();
    const compiled: LexiChainBuildResult = this.buildProxyChainPreview();
    if (compiled.errorMessage.length > 0) { return compiled.errorMessage; }
    const targetGroup: string = this.outboundMode === 'global' ? 'GLOBAL' : draft.targetGroup;
    const exit: string = chainNames[chainNames.length - 1];

    if (this.isRunning && !this.hasManagedRuntime()) {
      return this.connectProxyChain();
    }

    const prevChainConnected: boolean = this.chainConnected;
    const prevChainNames: string[] = this.connectedChainNames.slice();
    const prevChainGroup: string = this.connectedChainGroup;
    const prevChainMode: OutboundModeType = this.connectedChainMode;
    const prevSelectionObj: LexiSavedProxySelection | undefined = this.selections.find(
      (s: LexiSavedProxySelection): boolean => s.profileId === this.currentProfileId && s.groupName === targetGroup
    );
    const prevSelectionName: string = prevSelectionObj?.nodeName ?? '';

    this.isChainConnecting = true;
    this.notify(false);
    try {
      if (!this.isRunning) {
        this.rememberProxySelection(targetGroup, exit);
        const started: boolean = await this.toggleRunningAsync();
        if (!started) {
          this.chainConnected = prevChainConnected;
          this.connectedChainNames = prevChainNames;
          this.connectedChainGroup = prevChainGroup;
          this.connectedChainMode = prevChainMode;
          if (prevSelectionName.length > 0) { this.rememberProxySelection(targetGroup, prevSelectionName); }
          this.notify(false);
          return this.lastOperationError.length > 0 ? this.lastOperationError : '启动系统 VPN 与代理链失败';
        }
        this.chainConnected = true;
        this.connectedChainNames = chainNames.slice();
        this.connectedChainGroup = targetGroup;
        this.connectedChainMode = this.outboundMode;
        this.appendLog('info', 'ProxyChain', targetGroup, '已连接：' + chainNames.join(' → '));
        this.notify();
        return '';
      }

      const selectedMap: Record<string, string> = this.buildSelectedMap(compiled.yamlContent, profile.id);
      selectedMap[targetGroup] = exit;
      await this.vpnManager.reloadRuntimeConfig(compiled.yamlContent, selectedMap, this.outboundMode, targetGroup, exit);
      this.chainConnected = true;
      this.connectedChainNames = chainNames.slice();
      this.connectedChainGroup = targetGroup;
      this.connectedChainMode = this.outboundMode;
      this.rememberProxySelection(targetGroup, exit);
      this.liveConnections = [];
      this.appendLog('info', 'ProxyChain', targetGroup, '已连接：' + chainNames.join(' → '));
      this.notify();
      this.refreshOutboundIp();
      return '';
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      this.chainConnected = prevChainConnected;
      this.connectedChainNames = prevChainNames;
      this.connectedChainGroup = prevChainGroup;
      this.connectedChainMode = prevChainMode;
      if (prevSelectionName.length > 0) { this.rememberProxySelection(targetGroup, prevSelectionName); }
      this.lastOperationError = msg;
      this.appendLog('error', 'ProxyChain', targetGroup, msg);
      this.notify(false);
      return msg;
    } finally {
      this.isChainConnecting = false;
      this.notify(false);
    }
  }

  async disconnectProxyChainAsync(): Promise<string> {
    if (!this.chainConnected) { return ''; }
    if (!this.hasManagedRuntime()) {
      return this.disconnectProxyChain();
    }
    if (this.isChainConnecting) { return ''; }
    const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
    if (profile === null) { return '当前配置不存在'; }
    const cleared: LexiChainBuildResult = ProxyChainConfig.build(this.runtimeYaml(profile.yamlContent), []);
    if (cleared.errorMessage.length > 0) { return cleared.errorMessage; }
    const groupName: string = this.connectedChainGroup.length > 0
      ? this.connectedChainGroup
      : (this.outboundMode === 'global' ? 'GLOBAL' : this.getProxyChainDraft().targetGroup);
    const group: ProxyGroupItem | undefined = this.proxyGroups.find((candidate: ProxyGroupItem): boolean => candidate.name === groupName);
    const fallback: string = group === undefined || group.nodeNames.includes('DIRECT')
      ? 'DIRECT'
      : (this.connectedChainNames.length > 0 ? this.connectedChainNames[0] : 'DIRECT');

    this.isChainConnecting = true;
    this.notify(false);
    try {
      const selectedMap: Record<string, string> = this.buildSelectedMap(cleared.yamlContent, profile.id);
      selectedMap[groupName] = fallback;
      if (this.isRunning) {
        await this.vpnManager.reloadRuntimeConfig(cleared.yamlContent, selectedMap, this.outboundMode, groupName, fallback);
      }
      this.rememberProxySelection(groupName, fallback);
      this.chainConnected = false;
      this.connectedChainNames = [];
      this.liveConnections = [];
      this.appendLog('info', 'ProxyChain', groupName, '已断开链式代理');
      this.notify();
      if (this.isRunning) { this.refreshOutboundIp(); }
      return '';
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      this.lastOperationError = msg;
      this.appendLog('error', 'ProxyChain', groupName, '断开链式代理失败：' + msg);
      return msg;
    } finally {
      this.isChainConnecting = false;
      this.notify(false);
    }
  }

  connectProxyChain(): string {
    const invalid: string = this.getProxyChainValidationError();
    if (invalid.length > 0) { return invalid; }
    if (!this.core.isReady()) { return this.core.getUnavailableReason(); }
    if (!this.isRunning) { return '请先在仪表盘启动 VPN 连接，再连接代理链'; }
    const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
    if (profile === null) { return '请先添加配置'; }
    const draft: LexiProxyChainDraft = this.getProxyChainDraft();
    const compiled: LexiChainBuildResult = this.buildProxyChainPreview();
    const targetGroup: string = this.outboundMode === 'global' ? 'GLOBAL' : draft.targetGroup;
    const exit: string = draft.nodeNames[draft.nodeNames.length - 1];
    if (this.hasManagedRuntime()) {
      this.chainConnected = true;
      this.connectedChainNames = draft.nodeNames.slice();
      this.connectedChainGroup = targetGroup;
      this.connectedChainMode = this.outboundMode;
      this.rememberProxySelection(targetGroup, exit);
      this.appendLog('info', 'ProxyChain', targetGroup, '已连接：' + draft.nodeNames.join(' → '));
      this.notify();
      this.restartVpnAfterConfigChangeAsync();
      return '';
    }
    let error: string = this.core.execute(CoreMethodNames.CONFIG_VALIDATE, JSON.stringify({ yaml: compiled.yamlContent }));
    if (error.length > 0) { return error; }
    error = this.setupRuntimeYaml(compiled.yamlContent);
    if (error.length > 0) { return error; }
    error = this.core.execute(CoreMethodNames.PROXY_SELECT, JSON.stringify({ 'group-name': targetGroup, 'proxy-name': exit }));
    if (error.length > 0) {
      const previous: LexiChainBuildResult = this.chainConnected
        ? ProxyChainConfig.build(this.runtimeYaml(profile.yamlContent), this.connectedChainNames)
        : { yamlContent: this.runtimeYaml(profile.yamlContent), errorMessage: '' };
      const rollback: string = this.setupRuntimeYaml(previous.yamlContent);
      if (rollback.length > 0) { this.chainConnected = false; this.notify(false); return error + '；回滚失败：' + rollback; }
      return error;
    }
    this.chainConnected = true;
    this.connectedChainNames = draft.nodeNames.slice();
    this.connectedChainGroup = targetGroup;
    this.connectedChainMode = this.outboundMode;
    this.rememberProxySelection(targetGroup, exit);
    this.appendLog('info', 'ProxyChain', targetGroup, '已连接：' + draft.nodeNames.join(' → '));
    this.notify();
    return '';
  }

  disconnectProxyChain(): string {
    if (!this.chainConnected) { return ''; }
    const profile: ProfileSubscriptionModel | null = this.getCurrentProfile();
    if (profile === null) { return '当前配置不存在'; }
    const cleared: LexiChainBuildResult = ProxyChainConfig.build(this.runtimeYaml(profile.yamlContent), []);
    if (cleared.errorMessage.length > 0) { return cleared.errorMessage; }
    const group: ProxyGroupItem | undefined = this.proxyGroups.find((candidate: ProxyGroupItem): boolean => candidate.name === this.connectedChainGroup);
    const fallback: string = group === undefined || group.nodeNames.includes('DIRECT') ? 'DIRECT' : this.connectedChainNames[0];
    if (this.hasManagedRuntime()) {
      this.rememberProxySelection(this.connectedChainGroup, fallback);
      this.chainConnected = false;
      this.connectedChainNames = [];
      this.appendLog('info', 'ProxyChain', this.connectedChainGroup, '已断开链式代理');
      this.notify();
      this.restartVpnAfterConfigChangeAsync();
      return '';
    }
    const error: string = this.setupRuntimeYaml(cleared.yamlContent);
    if (error.length > 0) { return error; }
    const selectError: string = this.core.execute(CoreMethodNames.PROXY_SELECT,
      JSON.stringify({ 'group-name': this.connectedChainGroup, 'proxy-name': fallback }));
    if (selectError.length > 0) {
      const previous: LexiChainBuildResult = ProxyChainConfig.build(this.runtimeYaml(profile.yamlContent), this.connectedChainNames);
      const rollback: string = this.setupRuntimeYaml(previous.yamlContent);
      if (rollback.length > 0) { this.chainConnected = false; this.notify(false); }
      return selectError + (rollback.length > 0 ? '；回滚失败：' + rollback : '');
    }
    this.rememberProxySelection(this.connectedChainGroup, fallback);
    this.chainConnected = false;
    this.connectedChainNames = [];
    const closeError: string = this.core.execute(CoreMethodNames.CONNECTION_CLOSE_ALL);
    if (closeError.length === 0) { this.liveConnections = []; }
    this.appendLog('info', 'ProxyChain', this.connectedChainGroup, '已断开链式代理');
    this.notify();
    return closeError.length > 0 ? '链式代理已断开，但关闭旧连接失败：' + closeError : '';
  }

  private rememberProxySelection(groupName: string, nodeName: string): void {
    this.selections = this.selections.filter((saved: LexiSavedProxySelection): boolean =>
      saved.profileId !== this.currentProfileId || saved.groupName !== groupName);
    this.selections.push({ profileId: this.currentProfileId, groupName: groupName, nodeName: nodeName });
    const group: ProxyGroupItem | undefined = this.proxyGroups.find((candidate: ProxyGroupItem): boolean => candidate.name === groupName);
    if (group !== undefined) { group.selectedName = nodeName; }
  }

  getNodeByName(name: string): ProxyNodeItem | null {
    for (let i = 0; i < this.proxyNodes.length; i++) {
      if (this.proxyNodes[i].name === name) {
        return this.proxyNodes[i];
      }
    }
    return null;
  }

  private async selectProxyWhileVpnRunningAsync(groupName: string, nodeName: string): Promise<void> {
    try {
      await this.vpnManager.selectProxy(groupName, nodeName);
      if (this.outboundMode === 'global') {
        const resolvedLeaf: string = (nodeName === 'DIRECT' || nodeName === 'REJECT')
          ? nodeName
          : (this.resolveGroupLeafFromList(nodeName, this.proxyGroups) || nodeName);
        if (resolvedLeaf.length > 0) {
          await this.vpnManager.selectProxy('GLOBAL', resolvedLeaf);
          this.rememberProxySelection('GLOBAL', resolvedLeaf);
        }
      }
      try {
        await this.vpnManager.closeAllConnections();
      } catch (_closeErr) {
        // ignore benign close errors
      }
      this.liveConnections = [];
      await this.restartVpnAfterConfigChangeAsync();
      this.refreshOutboundIp();
      this.recheckAllServices();
    } catch (err) {
      this.lastOperationError = err instanceof Error ? err.message : String(err);
      this.notify(false);
    }
  }

  selectProxyInGroup(groupId: string, nodeName: string): void {
    this.lastOperationError = '';
    const targetGrp: ProxyGroupItem | null = this.getGroupById(groupId);
    if (!targetGrp) {
      this.lastOperationError = '代理组不存在';
      return;
    }
    if (!targetGrp.nodeNames.includes(nodeName) || targetGrp.groupType === 'LoadBalance') {
      this.lastOperationError = '此代理组不支持选择该节点'; return;
    }
    if (this.chainConnected) {
      if (this.hasManagedRuntime()) {
        this.rememberProxySelection(targetGrp.name, nodeName);
        this.disconnectChainAndSelectAsync(targetGrp.name, nodeName);
      } else {
        const error: string = this.disconnectProxyChain();
        if (error.length > 0) { this.lastOperationError = error; return; }
      }
    }
    if (this.isRunning && this.hasManagedRuntime()) {
      if (!this.chainConnected) {
        this.selectProxyWhileVpnRunningAsync(targetGrp.name, nodeName);
      }
    } else if (this.isRunning) {
      const error: string = this.core.execute(CoreMethodNames.PROXY_SELECT,
        JSON.stringify({ 'group-name': targetGrp.name, 'proxy-name': nodeName }));
      if (error.length > 0) { this.lastOperationError = error; return; }
    }
    const targetId: string = targetGrp.id;
    const nextGroups: ProxyGroupItem[] = [];
    for (let i = 0; i < this.proxyGroups.length; i++) {
      const g: ProxyGroupItem = this.proxyGroups[i];
      if (g.id === targetId) {
        nextGroups.push({
          id: g.id,
          name: g.name,
          groupType: g.groupType,
          iconText: g.iconText,
          selectedName: nodeName,
          fixedName: (g.groupType === 'URLTest' || g.groupType === 'Fallback') ? nodeName : g.fixedName,
          testUrl: g.testUrl,
          isTestingGroup: g.isTestingGroup,
          nodeNames: g.nodeNames.slice(),
          hidden: g.hidden
        });
      } else {
        nextGroups.push(g);
      }
    }
    this.proxyGroups = nextGroups;
    this.rememberProxySelection(targetGrp.name, nodeName);
    if (this.isRunning) {
      this.appendLog('info', 'Proxy', targetGrp.name, `Selected ${nodeName}`);
    }
    this.notify();
  }

  async testSingleNodeDelay(nodeName: string): Promise<void> {
    const node: ProxyNodeItem = this.storeNodeOrEnsure(nodeName);
    if (node.isTesting) {
      return;
    }
    node.isTesting = true;
    this.notify(false);

    let delay: number = -1;
    if (this.isRunning && this.hasManagedRuntime()) {
      delay = await this.vpnManager.testProxyDelay(node.name, this.testUrl, 10000);
    } else if (this.core.hasOfflineNativeProbes()) {
      const prof: ProfileSubscriptionModel | null = this.getCurrentProfile();
      if (prof !== null) {
        delay = await this.core.testOfflineDelayNative(prof.yamlContent, node.name);
      }
    } else {
      delay = await this.core.testNodeDelay(node.name, node.regionCode, this.testUrl, 5000);
    }
    node.delayMs = delay;
    node.isTesting = false;
    this.notify(false);
  }

  async testGroupDelays(groupId: string): Promise<void> {
    const grp: ProxyGroupItem | null = this.getGroupById(groupId);
    if (!grp || grp.isTestingGroup) {
      return;
    }
    grp.isTestingGroup = true;
    const targets: string[] = [];
    for (let i = 0; i < grp.nodeNames.length; i++) {
      const memberName: string = grp.nodeNames[i];
      const node: ProxyNodeItem = this.storeNodeOrEnsure(memberName);
      node.isTesting = true;
      if (memberName !== 'REJECT' && !targets.includes(memberName)) {
        targets.push(memberName);
      }
    }
    this.notify(false);

    if (this.isRunning && this.hasManagedRuntime()) {
      let cursor: number = 0;
      const workers: Promise<void>[] = [];
      const workerCount: number = Math.min(8, targets.length);
      for (let w: number = 0; w < workerCount; w++) {
        workers.push((async (): Promise<void> => {
          while (cursor < targets.length) {
            const name: string = targets[cursor++];
            const node: ProxyNodeItem = this.storeNodeOrEnsure(name);
            node.delayMs = await this.vpnManager.testProxyDelay(name, grp.testUrl || this.testUrl, 10000);
            node.isTesting = false;
            this.notify(false);
          }
        })());
      }
      await Promise.all(workers);
    } else if (this.core.hasOfflineNativeProbes()) {
      const prof: ProfileSubscriptionModel | null = this.getCurrentProfile();
      if (prof !== null && targets.length > 0) {
        const jobId: string = this.core.beginOfflineDelayJobNative(prof.yamlContent, targets);
        if (jobId.length > 0) {
          while (true) {
            const rawSnap: string = this.core.pollOfflineDelayJobNative(jobId);
            const snap: Record<string, Object> = JSON.parse(rawSnap) as Record<string, Object>;
            const results: Array<Record<string, Object>> = Array.isArray(snap['results'])
              ? (snap['results'] as Array<Record<string, Object>>)
              : [];
            for (let i: number = 0; i < results.length; i++) {
              const res: Record<string, Object> = results[i];
              const targetNode: ProxyNodeItem = this.storeNodeOrEnsure(String(res['name'] ?? ''));
              const errStr: string = typeof res['error'] === 'string' ? String(res['error']) : '';
              const dVal: number = Number(res['delay'] ?? 0);
              targetNode.delayMs = errStr.length > 0 || dVal <= 0 ? -1 : dVal;
              targetNode.isTesting = false;
            }
            if (results.length > 0) {
              this.notify(false);
            }
            if (snap['done'] === true) {
              break;
            }
            await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 200); });
          }
        }
      }
      for (let i: number = 0; i < grp.nodeNames.length; i++) {
        const node: ProxyNodeItem = this.storeNodeOrEnsure(grp.nodeNames[i]);
        node.isTesting = false;
      }
    } else {
      const tasks: Promise<void>[] = [];
      for (let i = 0; i < grp.nodeNames.length; i++) {
        const node: ProxyNodeItem = this.storeNodeOrEnsure(grp.nodeNames[i]);
        const task: Promise<void> = this.core.testNodeDelay(node.name, node.regionCode, grp.testUrl, 5000)
          .then((ms: number): void => {
            node.delayMs = ms;
            node.isTesting = false;
            this.notify(false);
          });
        tasks.push(task);
      }
      await Promise.all(tasks);
    }
    grp.isTestingGroup = false;
    this.notify(false);
  }

  private storeNodeOrEnsure(name: string): ProxyNodeItem {
    const existing: ProxyNodeItem | null = this.getNodeByName(name);
    if (existing !== null) {
      return existing;
    }
    const created: ProxyNodeItem = {
      id: `node_${Date.now()}_${name}`,
      name: name,
      protocol: name === 'DIRECT' || name === 'REJECT' ? name : 'Proxy',
      regionCode: YamlProfileParser.inferRegionFromName(name),
      server: 'local',
      port: 0,
      udp: true,
      delayMs: 0,
      isTesting: false,
      providerName: 'Profile'
    };
    this.proxyNodes.push(created);
    return created;
  }

  getCurrentProfile(): ProfileSubscriptionModel | null {
    if (this.profiles.length === 0) {
      return null;
    }
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === this.currentProfileId) {
        return this.profiles[i];
      }
    }
    return this.profiles[0];
  }

  private applyParsedProfileToRuntime(summary: ParsedYamlSummary): void {
    this.mixedPort = summary.mixedPort;
    this.allowLan = summary.allowLan;
    this.proxyNodes = summary.parsedNodes.slice();
    if (!this.getNodeByName('DIRECT')) {
      this.proxyNodes.push({
        id: 'node_builtin_direct',
        name: 'DIRECT',
        protocol: 'Direct',
        regionCode: 'CN',
        server: 'localhost',
        port: 0,
        udp: true,
        delayMs: 0,
        isTesting: false,
        providerName: 'Builtin'
      });
    }
    if (!this.getNodeByName('REJECT')) {
      this.proxyNodes.push({
        id: 'node_builtin_reject',
        name: 'REJECT',
        protocol: 'Reject',
        regionCode: 'GL',
        server: 'localhost',
        port: 0,
        udp: false,
        delayMs: 0,
        isTesting: false,
        providerName: 'Builtin'
      });
    }
    if (summary.parsedGroups.length > 0) {
      this.proxyGroups = summary.parsedGroups.slice();
    } else {
      const names: string[] = [];
      for (let i = 0; i < summary.parsedNodes.length; i++) {
        names.push(summary.parsedNodes[i].name);
      }
      names.push('DIRECT');
      names.push('REJECT');
      this.proxyGroups = [
        {
          id: 'grp_proxy',
          name: 'Proxy',
          groupType: 'Selector',
          iconText: 'P',
          selectedName: names[0],
          fixedName: '',
          testUrl: this.testUrl,
          isTestingGroup: false,
          nodeNames: names,
          hidden: false
        }
      ];
    }

    // Ensure every group name and group member is backed by a ProxyNodeItem in this.proxyNodes
    for (let gIdx = 0; gIdx < this.proxyGroups.length; gIdx++) {
      const g: ProxyGroupItem = this.proxyGroups[gIdx];
      if (!this.getNodeByName(g.name)) {
        this.proxyNodes.push({
          id: `node_grp_${g.id}`,
          name: g.name,
          protocol: g.groupType,
          regionCode: YamlProfileParser.inferRegionFromName(g.name),
          server: 'group',
          port: 0,
          udp: true,
          delayMs: 0,
          isTesting: false,
          providerName: 'Group'
        });
      }
    }
    for (let gIdx = 0; gIdx < this.proxyGroups.length; gIdx++) {
      const g: ProxyGroupItem = this.proxyGroups[gIdx];
      for (let mIdx = 0; mIdx < g.nodeNames.length; mIdx++) {
        this.storeNodeOrEnsure(g.nodeNames[mIdx]);
      }
      for (let sIdx = 0; sIdx < this.selections.length; sIdx++) {
        const saved: LexiSavedProxySelection = this.selections[sIdx];
        if (saved.profileId === this.currentProfileId && saved.groupName === g.name && g.nodeNames.includes(saved.nodeName)) {
          g.selectedName = saved.nodeName;
          break;
        }
      }
    }

    this.currentGroupId = this.proxyGroups.length > 0 ? this.proxyGroups[0].id : '';
  }

  selectProfile(profileId: string): void {
    this.lastOperationError = '';
    if (this.currentProfileId === profileId) {
      return;
    }
    const prof: ProfileSubscriptionModel | undefined = this.profiles.find((candidate: ProfileSubscriptionModel): boolean => candidate.id === profileId);
    if (prof === undefined) { this.lastOperationError = '配置不存在'; return; }
    const summary: ParsedYamlSummary = YamlProfileParser.parseYaml(prof.yamlContent);
    if (!summary.valid && !this.core.hasOfflineNativeProbes()) {
      this.lastOperationError = summary.errorMessage;
      return;
    }
    if (this.hasManagedRuntime()) {
      this.chainConnected = false;
      this.currentProfileId = profileId;
      if (summary.valid) {
        this.applyParsedProfileToRuntime(summary);
      } else {
        this.restoreSummaryFromNativeAsync(prof);
      }
      this.notify();
      this.restartVpnAfterConfigChangeAsync();
      return;
    }
    if (!summary.valid) { this.lastOperationError = summary.errorMessage; return; }
    const error: string = this.prepareProfileChange(prof.yamlContent, profileId);
    if (error.length > 0) { this.lastOperationError = error; return; }
    this.currentProfileId = profileId;
    this.applyParsedProfileToRuntime(summary);
    this.notify();
  }

  private prepareProfileChange(yaml: string, profileId: string = this.currentProfileId): string {
    if (!this.isRunning) { this.chainConnected = false; return ''; }
    if (this.hasManagedRuntime()) {
      this.chainConnected = false;
      return '';
    }
    if (this.chainConnected) {
      const error: string = this.disconnectProxyChain();
      if (error.length > 0) { return error; }
    }
    const error: string = this.core.execute(CoreMethodNames.CONFIG_VALIDATE, JSON.stringify({ yaml: this.runtimeYaml(yaml) }));
    if (error.length > 0) { return error; }
    return this.setupRuntimeYaml(yaml, profileId);
  }

  private async normalizeAndConvertProfileContent(rawInput: string): Promise<LexiProfileParseOutcome> {
    let yamlContent: string = YamlProfileParser.normalizeInput(rawInput);
    const hasProxiesSection: boolean = /^\s*proxies\s*:/m.test(yamlContent);
    if (!hasProxiesSection && ClashUriParser.hasAnySupportedUriLine(yamlContent)) {
      const batch: ClashUriBatchResult = ClashUriParser.parseBatchUris(yamlContent);
      if (batch.entries.length === 0) {
        return {
          ok: false,
          yamlContent: yamlContent,
          summary: YamlProfileParser.parseYaml(''),
          errorMessage: batch.errors.length > 0 ? batch.errors[0] : '无法解析节点链接，请检查 URI 格式'
        };
      }
      yamlContent = ClashUriParser.buildCompleteYamlFromEntries(batch.entries);
    }

    let summary: ParsedYamlSummary = YamlProfileParser.parseYaml(yamlContent);
    if (!summary.valid) {
      const nativeSummary: ParsedYamlSummary | null = await this.parseWithNativeFallback(yamlContent);
      if (nativeSummary !== null && nativeSummary.valid) {
        summary = nativeSummary;
      }
    }
    if (!summary.valid) {
      return {
        ok: false,
        yamlContent: yamlContent,
        summary: summary,
        errorMessage: summary.errorMessage.length > 0 ? summary.errorMessage : '配置内容无效，请输入完整的 Clash YAML 或支持的节点链接'
      };
    }
    return {
      ok: true,
      yamlContent: yamlContent,
      summary: summary,
      errorMessage: ''
    };
  }

  async syncProfileById(profileId: string): Promise<string> {
    let target: ProfileSubscriptionModel | null = null;
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === profileId) {
        target = this.profiles[i];
        break;
      }
    }
    if (!target || target.isUpdating) {
      return '';
    }
    target.isUpdating = true;
    this.notify();

    const fetchRes: SubscriptionFetchResult = await this.core.fetchSubscriptionFromUrl(target.url);
    target.isUpdating = false;
    if (!fetchRes.ok) {
      this.notify();
      return fetchRes.errorMessage;
    }

    const converted: LexiProfileParseOutcome = await this.normalizeAndConvertProfileContent(fetchRes.yamlContent);
    if (!converted.ok) {
      this.notify();
      return converted.errorMessage;
    }
    const finalYaml: string = converted.yamlContent;
    const parsed: ParsedYamlSummary = converted.summary;

    if (!this.profiles.some((profile: ProfileSubscriptionModel): boolean => profile.id === profileId)) { return '配置已删除，已取消更新'; }
    if (this.currentProfileId === target.id && !this.hasManagedRuntime()) {
      const error: string = this.prepareProfileChange(finalYaml);
      if (error.length > 0) { this.notify(); return error; }
    }
    target.yamlContent = finalYaml;
    target.usedUploadBytes = fetchRes.uploadBytes;
    target.usedDownloadBytes = fetchRes.downloadBytes;
    target.totalBytes = fetchRes.totalBytes;
    target.expireTimestamp = fetchRes.expireTimestamp;
    target.groupsCount = parsed.groupsCount;
    target.proxiesCount = parsed.proxiesCount;
    target.rulesCount = parsed.rulesCount;
    target.lastUpdatedText = '刚刚';

    if (this.currentProfileId === target.id) {
      this.applyParsedProfileToRuntime(parsed);
      if (this.hasManagedRuntime()) {
        this.restartVpnAfterConfigChangeAsync();
      }
    }
    this.notify();
    return '';
  }

  async addNewProfile(label: string, url: string, sourceType: ProfileSourceKind, customYaml: string): Promise<string> {
    const id: string = 'prof_' + Date.now() + '_' + Math.floor(Math.random() * 1000000);
    let yamlContent: string = customYaml;
    let upBytes: number = 0;
    let downBytes: number = 0;
    let totBytes: number = 0;
    let expSec: number = 0;

    if (sourceType === 'url') {
      const fetchRes: SubscriptionFetchResult = await this.core.fetchSubscriptionFromUrl(url);
      if (!fetchRes.ok) {
        return fetchRes.errorMessage;
      }
      yamlContent = fetchRes.yamlContent;
      upBytes = fetchRes.uploadBytes;
      downBytes = fetchRes.downloadBytes;
      totBytes = fetchRes.totalBytes;
      expSec = fetchRes.expireTimestamp;
    } else if (sourceType === 'file') {
      if (yamlContent.trim().length === 0) {
        return '请粘贴或输入有效的 YAML 配置或节点链接';
      }
    } else {
      if (yamlContent.trim().length === 0) {
        yamlContent = YamlProfileParser.getBlankCustomYaml();
      }
    }

    const converted: LexiProfileParseOutcome = await this.normalizeAndConvertProfileContent(yamlContent);
    if (!converted.ok) {
      return converted.errorMessage;
    }
    yamlContent = converted.yamlContent;
    const summary: ParsedYamlSummary = converted.summary;

    if (!this.hasManagedRuntime()) {
      const runtimeError: string = this.prepareProfileChange(yamlContent, id);
      if (runtimeError.length > 0) { return runtimeError; }
    } else {
      this.chainConnected = false;
    }
    const finalLabel: string = label.trim().length > 0
      ? label.trim()
      : (sourceType === 'custom' ? '自定义配置' : `配置 ${this.profiles.length + 1}`);

    const newProf: ProfileSubscriptionModel = {
      id: id,
      label: finalLabel,
      sourceType: sourceType,
      url: sourceType === 'url' ? url.trim() : '',
      usedUploadBytes: upBytes,
      usedDownloadBytes: downBytes,
      totalBytes: totBytes,
      expireTimestamp: expSec,
      lastUpdatedText: '刚刚',
      autoUpdate: sourceType === 'url',
      autoUpdateIntervalMinutes: 1440,
      isUpdating: false,
      groupsCount: summary.groupsCount,
      proxiesCount: summary.proxiesCount,
      rulesCount: summary.rulesCount,
      yamlContent: yamlContent
    };

    this.profiles.push(newProf);
    this.currentProfileId = id;
    this.applyParsedProfileToRuntime(summary);
    this.notify();
    if (this.hasManagedRuntime()) {
      this.restartVpnAfterConfigChangeAsync();
    }
    return '';
  }

  saveProfileYaml(profileId: string, newYaml: string): ParsedYamlSummary {
    newYaml = YamlProfileParser.normalizeInput(newYaml);
    const summary: ParsedYamlSummary = YamlProfileParser.parseYaml(newYaml);
    if (!summary.valid) {
      return summary;
    }
    if (!this.profiles.some((profile: ProfileSubscriptionModel): boolean => profile.id === profileId)) {
      summary.valid = false; summary.errorMessage = '配置不存在'; return summary;
    }
    if (this.currentProfileId === profileId && !this.hasManagedRuntime()) {
      const error: string = this.prepareProfileChange(newYaml);
      if (error.length > 0) { summary.valid = false; summary.errorMessage = error; return summary; }
    }
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id === profileId) {
        const prof: ProfileSubscriptionModel = this.profiles[i];
        prof.yamlContent = newYaml;
        prof.lastUpdatedText = '刚刚';
        prof.proxiesCount = summary.proxiesCount;
        prof.groupsCount = summary.groupsCount;
        prof.rulesCount = summary.rulesCount;
        break;
      }
    }
    if (this.currentProfileId === profileId) {
      this.applyParsedProfileToRuntime(summary);
      if (this.hasManagedRuntime()) {
        this.restartVpnAfterConfigChangeAsync();
      }
    }
    this.notify();
    return summary;
  }

  applyProfileProxiesEdit(
    profileId: string,
    prepend: ClashProxyEntry[],
    append: ClashProxyEntry[],
    deleteNames: string[]
  ): string {
    const target: ProfileSubscriptionModel | undefined = this.profiles.find(
      (p: ProfileSubscriptionModel): boolean => p.id === profileId
    );
    if (target === undefined) {
      return '配置不存在';
    }
    const seqResult: ClashSeqEditResult = ClashUriParser.applyProxiesSequenceEdit(
      target.yamlContent, prepend, append, deleteNames
    );
    if (seqResult.errorMessage.length > 0) {
      return seqResult.errorMessage;
    }
    const saved: ParsedYamlSummary = this.saveProfileYaml(profileId, seqResult.yamlContent);
    if (!saved.valid) {
      return saved.errorMessage.length > 0 ? saved.errorMessage : '更新节点序列后 YAML 无效';
    }
    this.appendLog('info', 'Profile', target.label, `已更新节点（新增 ${seqResult.addedCount}，移除 ${seqResult.removedCount}）`);
    return '';
  }

  importNodesToProfile(
    profileId: string,
    position: 'prepend' | 'append',
    entries: ClashProxyEntry[]
  ): string {
    if (entries.length === 0) {
      return '没有可导入的有效节点';
    }
    return this.applyProfileProxiesEdit(
      profileId,
      position === 'prepend' ? entries : [],
      position === 'append' ? entries : [],
      []
    );
  }

  importUriTextToProfile(
    profileId: string,
    position: 'prepend' | 'append',
    rawInput: string
  ): string {
    const trimmed: string = rawInput.trim();
    if (trimmed.length === 0) {
      return '请输入或粘贴节点 URI 链接（支持 Base64 / 多行）';
    }
    const batch: ClashUriBatchResult = ClashUriParser.parseBatchUris(trimmed);
    if (batch.entries.length === 0) {
      return batch.errors.length > 0 ? batch.errors[0] : '未识别到有效节点链接';
    }
    return this.importNodesToProfile(profileId, position, batch.entries);
  }

  deleteProfile(profileId: string): void {
    this.lastOperationError = '';
    const deletingCurrentRunning: boolean = this.currentProfileId === profileId && this.isRunning;
    if (deletingCurrentRunning && !this.hasManagedRuntime() && !this.toggleRunning()) { return; }
    const next: ProfileSubscriptionModel[] = [];
    for (let i = 0; i < this.profiles.length; i++) {
      if (this.profiles[i].id !== profileId) {
        next.push(this.profiles[i]);
      }
    }
    this.profiles = next;
    this.chains = this.chains.filter((draft: LexiProxyChainDraft): boolean => draft.profileId !== profileId);
    this.selections = this.selections.filter((saved: LexiSavedProxySelection): boolean => saved.profileId !== profileId);
    if (this.profiles.length === 0) {
      this.currentProfileId = '';
      this.proxyNodes = [];
      this.proxyGroups = [];
      this.currentGroupId = '';
      if (this.isRunning) {
        if (this.hasManagedRuntime()) {
          this.toggleRunningAsync();
        } else {
          this.toggleRunning();
        }
      }
    } else if (this.currentProfileId === profileId) {
      this.selectProfile(this.profiles[0].id);
    }
    this.notify();
  }

  closeConnectionById(connId: string): void {
    if (this.isRunning && this.hasManagedRuntime()) {
      this.vpnManager.closeConnection(connId).catch((err: Object): void => {
        this.lastOperationError = err instanceof Error ? err.message : String(err);
      });
    } else {
      this.lastOperationError = this.core.execute(CoreMethodNames.CONNECTION_CLOSE, JSON.stringify({ id: connId }));
      if (this.lastOperationError.length > 0) { return; }
    }
    const next: TrackerRecordItem[] = [];
    for (let i = 0; i < this.liveConnections.length; i++) {
      if (this.liveConnections[i].id !== connId) {
        next.push(this.liveConnections[i]);
      }
    }
    this.liveConnections = next;
    this.notify();
  }

  closeAllConnections(): void {
    if (this.isRunning && this.hasManagedRuntime()) {
      this.vpnManager.closeAllConnections().catch((err: Object): void => {
        this.lastOperationError = err instanceof Error ? err.message : String(err);
      });
    } else {
      this.lastOperationError = this.core.execute(CoreMethodNames.CONNECTION_CLOSE_ALL);
      if (this.lastOperationError.length > 0) { return; }
    }
    this.liveConnections = [];
    this.notify();
  }

  clearDnsCache(): void {
    if (this.isRunning && this.hasManagedRuntime()) {
      this.vpnManager.flushDnsCache().catch((error: Error): void => {
        this.lastOperationError = error.message;
        this.notify(false);
      });
    } else if (this.isRunning) {
      this.lastOperationError = this.core.execute(CoreMethodNames.DNS_CLEAR_CACHE);
      if (this.lastOperationError.length > 0) { return; }
    }
    this.dnsQueries = [];
    this.dnsQueriesCount = 0;
    this.notify();
  }

  updateExternalResource(resId: string): void {
    for (let i = 0; i < this.externalResources.length; i++) {
      if (this.externalResources[i].id === resId) {
        const item: ExternalResourceItem = this.externalResources[i];
        item.isUpdating = true;
        this.notify();
        this.lastOperationError = this.core.execute(CoreMethodNames.PROVIDER_UPDATE, JSON.stringify({ name: item.name }));
        item.isUpdating = false;
        if (this.lastOperationError.length === 0) {
          item.updatedAtText = '刚刚';
        }
        this.notify();
        break;
      }
    }
  }

  moveDashboardWidget(index: number, delta: number): void {
    const targetIdx: number = index + delta;
    if (targetIdx < 0 || targetIdx >= this.dashboardWidgets.length) {
      return;
    }
    const temp: DashboardWidgetConfigItem = this.dashboardWidgets[index];
    this.dashboardWidgets[index] = this.dashboardWidgets[targetIdx];
    this.dashboardWidgets[targetIdx] = temp;
    this.notify();
  }

  toggleDashboardWidget(id: string): void {
    for (let i = 0; i < this.dashboardWidgets.length; i++) {
      if (this.dashboardWidgets[i].id === id && this.dashboardWidgets[i].removable) {
        this.dashboardWidgets[i].enabled = !this.dashboardWidgets[i].enabled;
        break;
      }
    }
    this.notify();
  }

  appendLog(level: LogLevelKind, tag: string, sourceText: string, payloadText: string): void {
    if (!this.logcatEnabled) {
      return;
    }
    const now: Date = new Date();
    const h: string = now.getHours() < 10 ? `0${now.getHours()}` : `${now.getHours()}`;
    const m: string = now.getMinutes() < 10 ? `0${now.getMinutes()}` : `${now.getMinutes()}`;
    const s: string = now.getSeconds() < 10 ? `0${now.getSeconds()}` : `${now.getSeconds()}`;
    const entry: CoreLogRecordItem = {
      id: 'log_' + Date.now() + '_' + Math.floor(Math.random() * 1000),
      timeText: `${h}:${m}:${s}`,
      level: level,
      tag: tag,
      sourceText: sourceText,
      payloadText: payloadText
    };
    const next: CoreLogRecordItem[] = [entry];
    for (let i = 0; i < Math.min(this.coreLogs.length, 99); i++) {
      next.push(this.coreLogs[i]);
    }
    this.coreLogs = next;
  }
}

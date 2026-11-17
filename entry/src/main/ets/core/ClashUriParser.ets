// Clash / Mihomo multi-protocol URI parser & lossless profile proxy sequence editor
// Aligned with clash-verge-rev URI parsers (socks5/http/ss/ssr/vmess/vless/trojan/hy/hy2/tuic/wg/anytls)

import { buffer } from '@kit.ArkTS';
import { LexiYamlField, ProxyChainConfig } from './ProxyChainConfig';

export interface ClashWsOpts {
  path?: string;
  headers?: Record<string, string>;
  v2rayHttpUpgrade?: boolean;
  v2rayHttpUpgradeFastOpen?: boolean;
}

export interface ClashH2Opts {
  host?: string;
  path?: string;
}

export interface ClashHttpOpts {
  path?: string[];
  hostHeaders?: string[];
}

export interface ClashGrpcOpts {
  serviceName: string;
}

export interface ClashXHttpOpts {
  host?: string;
  path?: string;
  mode?: string;
}

export interface ClashRealityOpts {
  publicKey?: string;
  shortId?: string;
}

export interface ClashSsOpts {
  enabled: boolean;
  method: string;
  password: string;
}

export interface ClashPluginOpts {
  mode?: string;
  host?: string;
  path?: string;
  tls?: boolean;
  rawJson?: string;
}

export interface ClashProxyEntry {
  name: string;
  type: string;
  server: string;
  port: number;
  username?: string;
  password?: string;
  uuid?: string;
  cipher?: string;
  alterId?: number;
  tls?: boolean;
  skipCertVerify?: boolean;
  udp?: boolean;
  tfo?: boolean;
  fastOpen?: boolean;
  udpOverTcp?: boolean;
  ipVersion?: string;
  fingerprint?: string;
  clientFingerprint?: string;
  sni?: string;
  servername?: string;
  alpn?: string[];
  network?: string;
  flow?: string;
  encryption?: string;
  protocol?: string;
  protocolParam?: string;
  obfs?: string;
  obfsParam?: string;
  obfsPassword?: string;
  ports?: string;
  authStr?: string;
  up?: string;
  down?: string;
  recvWindowConn?: number;
  recvWindow?: number;
  ca?: string;
  caStr?: string;
  disableMtuDiscovery?: boolean;
  token?: string;
  ip?: string;
  ipv6?: string;
  heartbeatInterval?: number;
  disableSni?: boolean;
  reduceRtt?: boolean;
  requestTimeout?: number;
  udpRelayMode?: string;
  congestionController?: string;
  maxUdpRelayPacketSize?: number;
  maxOpenStreams?: number;
  privateKey?: string;
  publicKey?: string;
  allowedIps?: string[];
  preSharedKey?: string;
  reserved?: number[];
  mtu?: number;
  dialerProxy?: string;
  remoteDnsResolve?: boolean;
  dns?: string[];
  idleSessionCheckInterval?: number;
  idleSessionTimeout?: number;
  minIdleSession?: number;
  plugin?: string;
  pluginOpts?: ClashPluginOpts;
  wsOpts?: ClashWsOpts;
  h2Opts?: ClashH2Opts;
  httpOpts?: ClashHttpOpts;
  grpcOpts?: ClashGrpcOpts;
  xhttpOpts?: ClashXHttpOpts;
  realityOpts?: ClashRealityOpts;
  ssOpts?: ClashSsOpts;
}

export interface ClashUriBatchResult {
  entries: ClashProxyEntry[];
  errors: string[];
}

export interface ManualProxyNodeForm {
  protocol: string;
  name: string;
  server: string;
  port: number;
  username: string;
  password: string;
  uuid: string;
  cipher: string;
  sni: string;
  tls: boolean;
  skipCertVerify: boolean;
  udp: boolean;
  network: string;
  wsHost: string;
  wsPath: string;
  flow: string;
  clientFingerprint: string;
  publicKey: string;
  shortId: string;
  obfs: string;
  obfsPassword: string;
  privateKey: string;
  peerPublicKey: string;
  localIp: string;
}

export interface ClashProfileProxyItem {
  name: string;
  protocol: string;
  rawBlockLines: string[];
  isFlow: boolean;
  indent: number;
}

export interface ClashSeqEditResult {
  yamlContent: string;
  errorMessage: string;
  addedCount: number;
  removedCount: number;
}

interface NormalizedUriScheme {
  uri: string;
  scheme: string;
}

interface ParsedUrlParts {
  auth: string;
  host: string;
  portText: string;
  query: string;
  fragment: string;
}

const KNOWN_CIPHERS: Set<string> = new Set<string>([
  'none', 'auto', 'dummy',
  'aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm',
  'lea-128-gcm', 'lea-192-gcm', 'lea-256-gcm',
  'aes-128-gcm-siv', 'aes-256-gcm-siv',
  '2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm',
  'aes-128-cfb', 'aes-192-cfb', 'aes-256-cfb',
  'aes-128-ctr', 'aes-192-ctr', 'aes-256-ctr',
  'chacha20', 'chacha20-ietf', 'chacha20-ietf-poly1305',
  '2022-blake3-chacha20-poly1305', 'rabbit128-poly1305',
  'xchacha20-ietf-poly1305', 'xchacha20',
  'aegis-128l', 'aegis-256', 'aez-384',
  'deoxys-ii-256-128', 'rc4-md5'
]);

const IP_VERSIONS: string[] = ['dual', 'ipv4', 'ipv6', 'ipv4-prefer', 'ipv6-prefer'];

export class ClashUriParser {
  private static normalizeUriAndGetScheme(input: string): NormalizedUriScheme {
    const trimmed: string = input.trim();
    const match: RegExpExecArray | null = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\//.exec(trimmed);
    if (match === null) {
      const idx: number = trimmed.indexOf('://');
      const guess: string = (idx >= 0 ? trimmed.substring(0, idx) : trimmed).toLowerCase();
      return { uri: trimmed, scheme: guess };
    }
    const scheme: string = match[1].toLowerCase();
    return { uri: scheme + trimmed.substring(match[1].length), scheme: scheme };
  }

  private static stripUriScheme(uri: string, expected: string[], errMsg: string): string {
    const match: RegExpExecArray | null = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\//.exec(uri);
    if (match === null) {
      throw new Error(errMsg);
    }
    const scheme: string = match[1].toLowerCase();
    if (!expected.includes(scheme)) {
      throw new Error(errMsg);
    }
    return uri.substring(match[0].length);
  }

  private static safeDecodeURIComponent(value: string): string {
    if (value.length === 0) {
      return '';
    }
    try {
      return decodeURIComponent(value);
    } catch (_err) {
      return value;
    }
  }

  private static decodeAndTrim(value: string): string {
    if (value.length === 0) {
      return '';
    }
    return ClashUriParser.safeDecodeURIComponent(value).trim();
  }

  private static splitOnce(input: string, delimiter: string): string[] {
    const idx: number = input.indexOf(delimiter);
    if (idx === -1) {
      return [input];
    }
    return [input.substring(0, idx), input.substring(idx + delimiter.length)];
  }

  private static normalizeHost(host: string): string {
    return host.startsWith('[') && host.endsWith(']') ? host.substring(1, host.length - 1) : host;
  }

  private static parseUrlLike(input: string, requireAuth: boolean, errMsg: string): ParsedUrlParts {
    const match: RegExpExecArray | null =
      /^(?:(.*?)@)?(\[[^\]]+\]|[^:/?#]+)(?::(\d+))?\/?(?:\?(.*?))?(?:#(.*?))?$/.exec(input);
    if (match === null || match[2] === undefined || match[2].trim().length === 0) {
      throw new Error(errMsg);
    }
    const auth: string = (match[1] ?? '').trim();
    if (requireAuth && auth.length === 0) {
      throw new Error(errMsg);
    }
    return {
      auth: auth,
      host: ClashUriParser.normalizeHost(match[2].trim()),
      portText: (match[3] ?? '').trim(),
      query: match[4] ?? '',
      fragment: match[5] ?? ''
    };
  }

  private static parseQueryNormalized(query: string, normalizeKey: boolean = true): Map<string, string> {
    const out: Map<string, string> = new Map<string, string>();
    if (query.length === 0) {
      return out;
    }
    const parts: string[] = query.split('&');
    for (let i: number = 0; i < parts.length; i++) {
      const part: string = parts[i];
      if (part.length === 0) {
        continue;
      }
      const pair: string[] = ClashUriParser.splitOnce(part, '=');
      const rawKey: string = pair[0].trim();
      if (rawKey.length === 0) {
        continue;
      }
      const key: string = normalizeKey ? rawKey.replace(/_/g, '-') : rawKey;
      const val: string = pair.length > 1 ? ClashUriParser.safeDecodeURIComponent(pair[1]) : '__PRESENT__';
      out.set(key, val);
    }
    return out;
  }

  private static parseBoolOrPresence(value: string | undefined): boolean {
    if (value === undefined || value === '__PRESENT__' || value.trim().length === 0) {
      return true;
    }
    return /^(?:true|1)$/i.test(value.trim());
  }

  private static parseBoolStrict(value: string | undefined): boolean | undefined {
    if (value === undefined || value === '__PRESENT__') {
      return undefined;
    }
    return /^(?:true|1)$/i.test(value.trim());
  }

  private static parseInteger(value: string | undefined): number | undefined {
    if (value === undefined || value === '__PRESENT__') {
      return undefined;
    }
    const trimmed: string = value.trim();
    if (!/^-?\d+$/.test(trimmed)) {
      return undefined;
    }
    const n: number = Number.parseInt(trimmed, 10);
    return Number.isNaN(n) ? undefined : n;
  }

  private static parseRequiredPort(raw: string, errMsg: string): number {
    const trimmed: string = raw.trim();
    if (!/^\d+$/.test(trimmed)) {
      throw new Error(errMsg);
    }
    const p: number = Number.parseInt(trimmed, 10);
    if (!Number.isSafeInteger(p) || p < 1 || p > 65535) {
      throw new Error(errMsg);
    }
    return p;
  }

  private static parsePortOrDefault(raw: string, dft: number): number {
    const trimmed: string = raw.trim();
    if (trimmed.length === 0) {
      return dft;
    }
    const parsed: number | undefined = ClashUriParser.parseInteger(trimmed);
    return parsed !== undefined && parsed >= 1 && parsed <= 65535 ? parsed : dft;
  }

  private static parseIpVersion(value: string | undefined): string {
    if (value !== undefined && IP_VERSIONS.includes(value)) {
      return value;
    }
    return 'dual';
  }

  private static parseVlessFlow(value: string | undefined): string | undefined {
    if (value === undefined || value === '__PRESENT__') {
      return undefined;
    }
    const flow: string = value.trim();
    if (flow.length === 0 || /^none$/i.test(flow) || !/^[a-zA-Z0-9][a-zA-Z0-9-]*$/.test(flow)) {
      return undefined;
    }
    return flow;
  }

  private static decodeBase64Strict(str: string): string {
    const clean: string = str.replace(/[\r\n\s]/g, '').replace(/-/g, '+').replace(/_/g, '/');
    if (clean.length === 0) {
      return '';
    }
    const padLen: number = clean.length % 4;
    const padded: string = padLen === 0 ? clean : clean + '='.repeat(4 - padLen);
    try {
      const decoded: string = buffer.from(padded, 'base64').toString('utf-8');
      if (decoded.length === 0) {
        return '';
      }
      for (let i: number = 0; i < decoded.length; i++) {
        const code: number = decoded.charCodeAt(i);
        if (code === 9 || code === 10 || code === 13) {
          continue;
        }
        if (code < 32 || code === 127 || code === 0xFFFD) {
          return '';
        }
      }
      return decoded;
    } catch (_err) {
      return '';
    }
  }

  private static decodeBase64OrOriginal(str: string): string {
    const decoded: string = ClashUriParser.decodeBase64Strict(str);
    return decoded.length > 0 ? decoded : str;
  }

  private static getCipher(value: string | undefined): string {
    if (value === undefined) {
      return 'none';
    }
    const aliased: string = value === 'chacha20-poly1305' ? 'chacha20-ietf-poly1305' : value;
    return KNOWN_CIPHERS.has(aliased) ? aliased : 'auto';
  }

  private static parseAuthCredentials(authRaw: string, defaultPass: string = ''): string[] {
    let decoded: string = ClashUriParser.safeDecodeURIComponent(authRaw);
    if (!decoded.includes(':')) {
      const b64: string = ClashUriParser.decodeBase64Strict(decoded);
      if (b64.includes(':')) {
        decoded = b64;
      }
    }
    const parts: string[] = ClashUriParser.splitOnce(decoded, ':');
    return [parts[0], parts.length > 1 ? parts[1] : defaultPass];
  }

  private static parseSocks(line: string): ClashProxyEntry {
    const rawAfter: string = ClashUriParser.stripUriScheme(line, ['socks5', 'socks'], '无效的 SOCKS URI');
    if (rawAfter.length === 0) {
      throw new Error('无效的 SOCKS URI');
    }
    let afterScheme: string = rawAfter;
    if (!afterScheme.includes('@')) {
      const splitHash: string[] = ClashUriParser.splitOnce(afterScheme, '#');
      const splitQ: string[] = ClashUriParser.splitOnce(splitHash[0], '?');
      const maybeDecoded: string = ClashUriParser.decodeBase64Strict(splitQ[0]);
      if (maybeDecoded.includes(':')) {
        afterScheme = maybeDecoded + (splitQ.length > 1 ? '?' + splitQ[1] : '') + (splitHash.length > 1 ? '#' + splitHash[1] : '');
      }
    }
    const parts: ParsedUrlParts = ClashUriParser.parseUrlLike(afterScheme, false, '无效的 SOCKS URI');
    const portNum: number = ClashUriParser.parsePortOrDefault(parts.portText, 443);
    const name: string = ClashUriParser.decodeAndTrim(parts.fragment) || `SOCKS5 ${parts.host}:${portNum}`;
    const proxy: ClashProxyEntry = {
      type: 'socks5',
      name: name,
      server: parts.host,
      port: portNum
    };
    if (parts.auth.length > 0) {
      const creds: string[] = ClashUriParser.parseAuthCredentials(parts.auth);
      proxy.username = creds[0];
      proxy.password = creds[1];
    }
    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parts.query);
    if (params.has('tls')) {
      proxy.tls = ClashUriParser.parseBoolOrPresence(params.get('tls'));
    }
    if (params.has('fingerprint') && (params.get('fingerprint') ?? '') !== '__PRESENT__') {
      proxy.fingerprint = params.get('fingerprint');
    }
    if (params.has('skip-cert-verify')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('skip-cert-verify'));
    }
    if (params.has('udp')) {
      proxy.udp = ClashUriParser.parseBoolOrPresence(params.get('udp'));
    }
    if (params.has('ip-version')) {
      proxy.ipVersion = ClashUriParser.parseIpVersion(params.get('ip-version'));
    }
    return proxy;
  }

  private static parseHttp(line: string): ClashProxyEntry {
    const normalized: NormalizedUriScheme = ClashUriParser.normalizeUriAndGetScheme(line);
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['http', 'https'], '无效的 HTTP URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 HTTP URI');
    }
    const parts: ParsedUrlParts = ClashUriParser.parseUrlLike(afterScheme, false, '无效的 HTTP URI');
    const defaultPort: number = normalized.scheme === 'https' ? 443 : 80;
    const portNum: number = ClashUriParser.parsePortOrDefault(parts.portText, defaultPort);
    const name: string = ClashUriParser.decodeAndTrim(parts.fragment) || `HTTP ${parts.host}:${portNum}`;
    const proxy: ClashProxyEntry = {
      type: 'http',
      name: name,
      server: parts.host,
      port: portNum
    };
    if (normalized.scheme === 'https') {
      proxy.tls = true;
    }
    if (parts.auth.length > 0) {
      const creds: string[] = ClashUriParser.parseAuthCredentials(parts.auth);
      proxy.username = creds[0];
      proxy.password = creds[1];
    }
    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parts.query);
    if (params.has('tls')) {
      proxy.tls = ClashUriParser.parseBoolOrPresence(params.get('tls'));
    }
    if (params.has('fingerprint') && (params.get('fingerprint') ?? '') !== '__PRESENT__') {
      proxy.fingerprint = params.get('fingerprint');
    }
    if (params.has('skip-cert-verify')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('skip-cert-verify'));
    }
    if (params.has('ip-version')) {
      proxy.ipVersion = ClashUriParser.parseIpVersion(params.get('ip-version'));
    }
    return proxy;
  }

  private static parseSs(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['ss'], '无效的 SS URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 SS URI');
    }
    const hashSplit: string[] = ClashUriParser.splitOnce(afterScheme, '#');
    const nameFromHash: string = hashSplit.length > 1 ? ClashUriParser.decodeAndTrim(hashSplit[1]) : '';
    const qSplit: string[] = ClashUriParser.splitOnce(hashSplit[0], '?');
    const queryParams: Map<string, string> = ClashUriParser.parseQueryNormalized(qSplit.length > 1 ? qSplit[1] : '', false);

    const mainRaw: string = qSplit[0];
    const main: string = mainRaw.includes('@') ? mainRaw : ClashUriParser.decodeBase64OrOriginal(mainRaw);
    const atIdx: number = main.lastIndexOf('@');
    if (atIdx === -1) {
      throw new Error("无效的 SS URI: 缺少 '@'");
    }
    const userInfoStr: string = ClashUriParser.decodeBase64OrOriginal(main.substring(0, atIdx));
    const serverAndPort: string = main.substring(atIdx + 1).split('/')[0];
    const portIdx: number = serverAndPort.lastIndexOf(':');
    if (portIdx === -1) {
      throw new Error('无效的 SS URI: 缺少端口');
    }
    const server: string = ClashUriParser.normalizeHost(serverAndPort.substring(0, portIdx));
    const port: number = ClashUriParser.parseRequiredPort(serverAndPort.substring(portIdx + 1), '无效的 SS URI: 端口无效');
    const userMatch: string[] = ClashUriParser.splitOnce(userInfoStr, ':');

    const proxy: ClashProxyEntry = {
      name: nameFromHash.length > 0 ? nameFromHash : `SS ${server}:${port}`,
      type: 'ss',
      server: server,
      port: port,
      cipher: ClashUriParser.getCipher(userMatch[0]),
      password: userMatch.length > 1 ? userMatch[1] : ''
    };

    const pluginParam: string | undefined = queryParams.get('plugin');
    if (pluginParam !== undefined && pluginParam !== '__PRESENT__' && pluginParam.length > 0) {
      const pluginParts: string[] = pluginParam.split(';');
      const pluginName: string = pluginParts[0];
      const pluginValues: Map<string, string> = new Map<string, string>();
      for (let i: number = 1; i < pluginParts.length; i++) {
        const rawOpt: string = pluginParts[i];
        if (rawOpt.length === 0) {
          continue;
        }
        const kv: string[] = ClashUriParser.splitOnce(rawOpt, '=');
        if (kv[0].length > 0) {
          pluginValues.set(kv[0], kv.length > 1 && kv[1].length > 0 ? kv[1] : '__TRUE__');
        }
      }
      if (pluginName === 'obfs-local' || pluginName === 'simple-obfs') {
        proxy.plugin = 'obfs';
        proxy.pluginOpts = {
          mode: pluginValues.get('obfs'),
          host: pluginValues.get('obfs-host')
        };
      } else if (pluginName === 'v2ray-plugin') {
        proxy.plugin = 'v2ray-plugin';
        const hostVal: string | undefined = pluginValues.get('obfs-host') ?? pluginValues.get('host');
        proxy.pluginOpts = {
          mode: 'websocket',
          host: hostVal,
          path: pluginValues.get('path'),
          tls: pluginValues.has('tls') ? true : undefined
        };
      } else {
        throw new Error(`不支持的 SS 插件类型: ${pluginName}`);
      }
    }

    const v2rayPluginParam: string | undefined = queryParams.get('v2ray-plugin');
    if (proxy.plugin === undefined && v2rayPluginParam !== undefined && v2rayPluginParam !== '__PRESENT__') {
      proxy.plugin = 'v2ray-plugin';
      proxy.pluginOpts = { rawJson: ClashUriParser.decodeBase64OrOriginal(v2rayPluginParam) };
    }
    if (queryParams.has('uot') && ClashUriParser.parseBoolOrPresence(queryParams.get('uot'))) {
      proxy.udpOverTcp = true;
    }
    if (queryParams.has('tfo') && ClashUriParser.parseBoolOrPresence(queryParams.get('tfo'))) {
      proxy.tfo = true;
    }
    return proxy;
  }

  private static parseSsr(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['ssr'], '无效的 SSR URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 SSR URI');
    }
    const decoded: string = ClashUriParser.decodeBase64OrOriginal(afterScheme);
    let splitIdx: number = decoded.indexOf(':origin');
    if (splitIdx === -1) {
      splitIdx = decoded.indexOf(':auth_');
    }
    if (splitIdx === -1) {
      throw new Error('无效的 SSR URI');
    }
    const serverAndPort: string = decoded.substring(0, splitIdx);
    const portIdx: number = serverAndPort.lastIndexOf(':');
    if (portIdx === -1) {
      throw new Error('无效的 SSR URI: 缺少端口');
    }
    const server: string = ClashUriParser.normalizeHost(serverAndPort.substring(0, portIdx));
    const port: number = ClashUriParser.parseRequiredPort(serverAndPort.substring(portIdx + 1), '无效的 SSR URI: 端口无效');

    const bodyAndQuery: string[] = decoded.substring(splitIdx + 1).split('/?');
    const params: string[] = bodyAndQuery[0].split(':');
    if (params.length < 4) {
      throw new Error('无效的 SSR URI: 参数不足');
    }
    const queryMap: Map<string, string> = ClashUriParser.parseQueryNormalized(bodyAndQuery.length > 1 ? bodyAndQuery[1] : '', false);
    const rawRemarks: string = queryMap.get('remarks') ?? '';
    const name: string = rawRemarks.length > 0 && rawRemarks !== '__PRESENT__'
      ? ClashUriParser.decodeBase64OrOriginal(rawRemarks).trim()
      : server;

    const protoParamRaw: string = queryMap.get('protoparam') ?? '';
    const obfsParamRaw: string = queryMap.get('obfsparam') ?? '';
    const protoParam: string = protoParamRaw.length > 0 && protoParamRaw !== '__PRESENT__'
      ? ClashUriParser.decodeBase64OrOriginal(protoParamRaw).replace(/\s/g, '') : '';
    const obfsParam: string = obfsParamRaw.length > 0 && obfsParamRaw !== '__PRESENT__'
      ? ClashUriParser.decodeBase64OrOriginal(obfsParamRaw).replace(/\s/g, '') : '';

    return {
      name: name.length > 0 ? name : `SSR ${server}:${port}`,
      type: 'ssr',
      server: server,
      port: port,
      protocol: params[0],
      cipher: ClashUriParser.getCipher(params[1]),
      obfs: params[2],
      password: ClashUriParser.decodeBase64OrOriginal(params[3]),
      protocolParam: protoParam.length > 0 ? protoParam : undefined,
      obfsParam: obfsParam.length > 0 ? obfsParam : undefined
    };
  }

  private static parseTrojan(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['trojan'], '无效的 Trojan URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 Trojan URI');
    }
    const parts: ParsedUrlParts = ClashUriParser.parseUrlLike(afterScheme, true, '无效的 Trojan URI');
    const portNum: number = ClashUriParser.parsePortOrDefault(parts.portText, 443);
    const password: string = ClashUriParser.safeDecodeURIComponent(parts.auth);
    const name: string = ClashUriParser.decodeAndTrim(parts.fragment) || `Trojan ${parts.host}:${portNum}`;
    const proxy: ClashProxyEntry = {
      type: 'trojan',
      name: name,
      server: parts.host,
      port: portNum,
      password: password
    };

    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parts.query);
    const networkRaw: string = params.get('type') ?? '';
    if (networkRaw === 'ws' || networkRaw === 'grpc' || networkRaw === 'h2' || networkRaw === 'tcp') {
      proxy.network = networkRaw;
    }
    const hostVal: string = (params.get('host') ?? '').trim();
    const pathVal: string = (params.get('path') ?? '').trim();
    const alpnVal: string = (params.get('alpn') ?? '').trim();
    if (alpnVal.length > 0 && alpnVal !== '__PRESENT__') {
      proxy.alpn = alpnVal.split(',');
    }
    const sniVal: string = (params.get('sni') ?? '').trim();
    if (sniVal.length > 0 && sniVal !== '__PRESENT__') {
      proxy.sni = sniVal;
    }
    if (params.has('skip-cert-verify')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('skip-cert-verify'));
    }
    const fp: string = (params.get('fingerprint') ?? params.get('fp') ?? '').trim();
    if (fp.length > 0 && fp !== '__PRESENT__') {
      proxy.fingerprint = fp;
    }
    const clientFp: string = (params.get('client-fingerprint') ?? '').trim();
    if (clientFp.length > 0 && clientFp !== '__PRESENT__') {
      proxy.clientFingerprint = clientFp;
    }
    const enc: string = (params.get('encryption') ?? '').trim();
    if (enc.length > 0) {
      const encParts: string[] = enc.split(';');
      if (encParts.length === 3) {
        proxy.ssOpts = { enabled: true, method: encParts[1], password: encParts[2] };
      }
    }
    if (proxy.network === 'ws') {
      const wsOpts: ClashWsOpts = {};
      if (hostVal.length > 0 && hostVal !== '__PRESENT__') {
        const headers: Record<string, string> = {};
        headers['Host'] = hostVal;
        wsOpts.headers = headers;
      }
      if (pathVal.length > 0 && pathVal !== '__PRESENT__') {
        wsOpts.path = pathVal;
      }
      if (wsOpts.headers !== undefined || wsOpts.path !== undefined) {
        proxy.wsOpts = wsOpts;
      }
    } else if (proxy.network === 'grpc' && pathVal.length > 0 && pathVal !== '__PRESENT__') {
      proxy.grpcOpts = { serviceName: pathVal };
    }
    return proxy;
  }

  private static parseVless(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['vless'], '无效的 VLESS URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 VLESS URI');
    }
    let rest: string = afterScheme;
    let isShadowrocket: boolean = false;
    let parsed: ParsedUrlParts;
    try {
      parsed = ClashUriParser.parseUrlLike(rest, true, '无效的 VLESS URI');
      ClashUriParser.parseRequiredPort(parsed.portText, '无效的 VLESS URI: 缺少端口');
    } catch (_firstErr) {
      const shadowMatch: RegExpExecArray | null = /^(.*?)(\?.*?)$/.exec(rest);
      if (shadowMatch === null) {
        throw new Error('无效的 VLESS URI');
      }
      rest = ClashUriParser.decodeBase64OrOriginal(shadowMatch[1]) + shadowMatch[2];
      parsed = ClashUriParser.parseUrlLike(rest, true, '无效的 VLESS URI');
      ClashUriParser.parseRequiredPort(parsed.portText, '无效的 VLESS URI: 端口无效');
      isShadowrocket = true;
    }

    const port: number = ClashUriParser.parseRequiredPort(parsed.portText, '无效的 VLESS URI: 端口无效');
    let uuid: string = parsed.auth;
    if (isShadowrocket) {
      uuid = uuid.replace(/^.*?:/g, '');
    }
    uuid = ClashUriParser.safeDecodeURIComponent(uuid);

    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parsed.query);
    const remarksRaw: string = (params.get('remarks') ?? params.get('remark') ?? '').trim();
    const name: string = ClashUriParser.decodeAndTrim(parsed.fragment) ||
      (remarksRaw.length > 0 && remarksRaw !== '__PRESENT__' ? remarksRaw : `VLESS ${parsed.host}:${port}`);

    const proxy: ClashProxyEntry = {
      type: 'vless',
      name: name,
      server: parsed.host,
      port: port,
      uuid: uuid
    };
    const encVal: string | undefined = params.get('encryption');
    if (encVal !== undefined && encVal !== '__PRESENT__') {
      proxy.encryption = encVal === 'none' ? '' : encVal;
    }
    const secVal: string = params.get('security') ?? '';
    if (secVal.length > 0 && secVal !== 'none' && secVal !== '__PRESENT__') {
      proxy.tls = true;
    }
    if (isShadowrocket && ClashUriParser.parseBoolStrict(params.get('tls')) === true) {
      proxy.tls = true;
      if (secVal.length === 0) {
        params.set('security', 'reality');
      }
    }
    const sniVal: string = (params.get('sni') ?? params.get('peer') ?? '').trim();
    if (sniVal.length > 0 && sniVal !== '__PRESENT__') {
      proxy.servername = sniVal;
    }
    proxy.flow = ClashUriParser.parseVlessFlow(params.get('flow'));
    const fpVal: string = (params.get('fp') ?? '').trim();
    if (fpVal.length > 0 && fpVal !== '__PRESENT__') {
      proxy.clientFingerprint = fpVal;
    }
    const alpnVal: string = (params.get('alpn') ?? '').trim();
    if (alpnVal.length > 0 && alpnVal !== '__PRESENT__') {
      proxy.alpn = alpnVal.split(',');
    }
    if (params.has('allowInsecure')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('allowInsecure'));
    } else if (params.has('skip-cert-verify')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('skip-cert-verify'));
    }

    if (params.get('security') === 'reality') {
      const pbk: string = (params.get('pbk') ?? '').trim();
      const sid: string = (params.get('sid') ?? '').trim();
      if (pbk.length > 0 || sid.length > 0) {
        proxy.realityOpts = {
          publicKey: pbk.length > 0 ? pbk : undefined,
          shortId: sid.length > 0 ? sid : undefined
        };
      }
    }

    let httpupgrade: boolean = false;
    let network: string = 'tcp';
    if (params.get('headerType') === 'http') {
      network = 'http';
    } else {
      let typeVal: string = (params.get('type') ?? '').trim();
      if (typeVal === 'websocket' || (isShadowrocket && typeVal === 'sw')) {
        typeVal = 'ws';
      }
      if (typeVal === 'httpupgrade') {
        network = 'ws';
        httpupgrade = true;
      } else if (typeVal === 'tcp' || typeVal === 'ws' || typeVal === 'http' || typeVal === 'grpc' || typeVal === 'h2' || typeVal === 'xhttp') {
        network = typeVal;
      }
      if (params.get('type') === 'ws') {
        httpupgrade = true;
      }
    }
    proxy.network = network;

    if (network !== 'tcp' && network !== 'none') {
      const hostVal: string = (params.get('host') ?? params.get('obfsParam') ?? '').trim();
      const pathVal: string = (params.get('path') ?? '').trim();
      if (network === 'grpc' && pathVal.length > 0) {
        proxy.grpcOpts = { serviceName: pathVal };
      } else if (network === 'h2') {
        if (hostVal.length > 0 || pathVal.length > 0) {
          proxy.h2Opts = {
            host: hostVal.length > 0 ? hostVal : undefined,
            path: pathVal.length > 0 ? pathVal : undefined
          };
        }
      } else if (network === 'http') {
        if (hostVal.length > 0 || pathVal.length > 0) {
          proxy.httpOpts = {
            path: pathVal.length > 0 ? [pathVal] : undefined,
            hostHeaders: hostVal.length > 0 ? [hostVal] : undefined
          };
        }
      } else if (network === 'ws') {
        const wsOpts: ClashWsOpts = {};
        if (hostVal.length > 0) {
          const headers: Record<string, string> = {};
          headers['Host'] = hostVal;
          if (params.has('obfsParam')) {
            try {
              const obj: Record<string, Object> = JSON.parse(hostVal) as Record<string, Object>;
              const keys: string[] = Object.keys(obj);
              for (let k: number = 0; k < keys.length; k++) {
                headers[keys[k]] = String(obj[keys[k]] ?? '');
              }
            } catch (_ignoreErr) {
              headers['Host'] = hostVal;
            }
          }
          wsOpts.headers = headers;
        }
        if (pathVal.length > 0) {
          wsOpts.path = pathVal;
        }
        if (httpupgrade) {
          wsOpts.v2rayHttpUpgrade = true;
          wsOpts.v2rayHttpUpgradeFastOpen = true;
        }
        if (wsOpts.headers !== undefined || wsOpts.path !== undefined || wsOpts.v2rayHttpUpgrade) {
          proxy.wsOpts = wsOpts;
        }
      } else if (network === 'xhttp') {
        const modeVal: string = (params.get('mode') ?? '').trim();
        if (hostVal.length > 0 || pathVal.length > 0 || modeVal.length > 0) {
          proxy.xhttpOpts = {
            host: hostVal.length > 0 ? hostVal : undefined,
            path: pathVal.length > 0 ? pathVal : undefined,
            mode: modeVal.length > 0 ? modeVal : undefined
          };
        }
      }
    }

    if (proxy.tls && (proxy.servername === undefined || proxy.servername.length === 0)) {
      if (proxy.network === 'ws' && proxy.wsOpts?.headers !== undefined) {
        proxy.servername = proxy.wsOpts.headers['Host'];
      } else if (proxy.network === 'http' && proxy.httpOpts?.hostHeaders !== undefined && proxy.httpOpts.hostHeaders.length > 0) {
        proxy.servername = proxy.httpOpts.hostHeaders[0];
      } else if (proxy.network === 'h2' && proxy.h2Opts?.host !== undefined) {
        proxy.servername = proxy.h2Opts.host;
      }
    }
    return proxy;
  }

  private static parseVmess(line: string): ClashProxyEntry {
    const raw: string = ClashUriParser.stripUriScheme(line, ['vmess'], '无效的 VMess URI');
    if (raw.length === 0) {
      throw new Error('无效的 VMess URI');
    }
    const content: string = ClashUriParser.decodeBase64OrOriginal(raw);
    const params: Map<string, string> = new Map<string, string>();
    try {
      const obj: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      const keys: string[] = Object.keys(obj);
      for (let i: number = 0; i < keys.length; i++) {
        const val: Object | undefined = obj[keys[i]];
        if (val !== undefined && val !== null) {
          params.set(keys[i], typeof val === 'object' ? JSON.stringify(val) : String(val));
        }
      }
    } catch (_jsonErr) {
      const match: RegExpExecArray | null = /(^[^?]+?)\/?\?(.*)$/.exec(raw);
      if (match === null) {
        throw new Error('无效的 VMess URI');
      }
      const lineDecoded: string = ClashUriParser.decodeBase64OrOriginal(match[1]);
      const qsParams: Map<string, string> = ClashUriParser.parseQueryNormalized(match[2], false);
      qsParams.forEach((v: string, k: string): void => {
        params.set(k, v);
      });
      const srMatch: RegExpExecArray | null = /(^[^:]+?):([^:]+?)@(.*):(\d+)$/.exec(lineDecoded);
      if (srMatch !== null) {
        params.set('scy', srMatch[1]);
        params.set('id', srMatch[2]);
        params.set('add', srMatch[3]);
        params.set('port', srMatch[4]);
      }
    }

    const server: string = ClashUriParser.normalizeHost((params.get('add') ?? '').trim());
    if (server.length === 0) {
      throw new Error('无效的 VMess URI: 缺少服务器');
    }
    const port: number = ClashUriParser.parseRequiredPort(params.get('port') ?? '', '无效的 VMess URI: 端口无效');
    const nameCandidate: string = (params.get('ps') ?? params.get('remarks') ?? params.get('remark') ?? '').trim();
    const tlsRaw: string = (params.get('tls') ?? '').toLowerCase();
    const tlsEnabled: boolean = tlsRaw === 'tls' || tlsRaw === 'true' || tlsRaw === '1';
    const proxy: ClashProxyEntry = {
      name: nameCandidate.length > 0 ? nameCandidate : `VMess ${server}:${port}`,
      type: 'vmess',
      server: server,
      port: port,
      cipher: ClashUriParser.getCipher(params.get('scy') ?? 'auto'),
      uuid: params.get('id') ?? '',
      tls: tlsEnabled,
      alterId: ClashUriParser.parseInteger(params.get('aid') ?? params.get('alterId') ?? '0') ?? 0
    };
    const verifyCert: string | undefined = params.get('verify_cert');
    if (verifyCert !== undefined) {
      proxy.skipCertVerify = !(ClashUriParser.parseBoolStrict(verifyCert) ?? true);
    }
    const sni: string = (params.get('sni') ?? '').trim();
    if (proxy.tls && sni.length > 0) {
      proxy.servername = sni;
    }

    const net: string = (params.get('net') ?? '').trim();
    const obfs: string = (params.get('obfs') ?? '').trim();
    const pType: string = (params.get('type') ?? '').trim();
    let httpupgrade: boolean = false;
    if (net === 'ws' || obfs === 'websocket') {
      proxy.network = 'ws';
    } else if (net === 'http' || obfs === 'http' || pType === 'http') {
      proxy.network = 'http';
    } else if (net === 'grpc') {
      proxy.network = 'grpc';
    } else if (net === 'httpupgrade') {
      proxy.network = 'ws';
      httpupgrade = true;
    } else if (net === 'h2') {
      proxy.network = 'h2';
    }

    if (proxy.network !== undefined) {
      let hostFirst: string = (params.get('host') ?? params.get('obfsParam') ?? '').trim();
      if (hostFirst.startsWith('{')) {
        try {
          const parsedHostObj: Record<string, Object> = JSON.parse(hostFirst) as Record<string, Object>;
          const extractedHost: string = String(parsedHostObj['Host'] ?? '').trim();
          if (extractedHost.length > 0) {
            hostFirst = extractedHost;
          }
        } catch (_e) {
          // keep hostFirst
        }
      }
      const pathFirst: string = (params.get('path') ?? '').trim();
      if (proxy.network === 'grpc') {
        if (pathFirst.length > 0) {
          proxy.grpcOpts = { serviceName: pathFirst };
        } else if (hostFirst.length === 0) {
          proxy.network = undefined;
        }
      } else if (proxy.network === 'h2') {
        if (hostFirst.length > 0 || pathFirst.length > 0) {
          proxy.h2Opts = {
            host: hostFirst.length > 0 ? hostFirst : undefined,
            path: pathFirst.length > 0 ? pathFirst : undefined
          };
        } else {
          proxy.network = undefined;
        }
      } else if (proxy.network === 'http') {
        proxy.httpOpts = {
          path: [pathFirst.length > 0 ? pathFirst : '/'],
          hostHeaders: hostFirst.length > 0 ? [hostFirst] : undefined
        };
      } else if (proxy.network === 'ws') {
        if (hostFirst.length === 0 && pathFirst.length === 0 && !httpupgrade) {
          proxy.network = undefined;
        } else {
          const wsHeaders: Record<string, string> = {};
          if (hostFirst.length > 0) {
            wsHeaders['Host'] = hostFirst;
          }
          proxy.wsOpts = {
            path: pathFirst.length > 0 ? pathFirst : undefined,
            headers: hostFirst.length > 0 ? wsHeaders : undefined,
            v2rayHttpUpgrade: httpupgrade ? true : undefined,
            v2rayHttpUpgradeFastOpen: httpupgrade ? true : undefined
          };
        }
      }
      if (proxy.tls && (proxy.servername === undefined || proxy.servername.length === 0) && hostFirst.length > 0) {
        proxy.servername = hostFirst;
      }
    }
    return proxy;
  }

  private static parseHysteria(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['hysteria', 'hy'], '无效的 Hysteria URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 Hysteria URI');
    }
    const parts: ParsedUrlParts = ClashUriParser.parseUrlLike(afterScheme, false, '无效的 Hysteria URI');
    const portNum: number = ClashUriParser.parsePortOrDefault(parts.portText, 443);
    const name: string = ClashUriParser.decodeAndTrim(parts.fragment) || `Hysteria ${parts.host}:${portNum}`;
    const proxy: ClashProxyEntry = {
      type: 'hysteria',
      name: name,
      server: parts.host,
      port: portNum,
      protocol: 'udp'
    };
    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parts.query);
    if (params.has('alpn') && (params.get('alpn') ?? '') !== '__PRESENT__') {
      proxy.alpn = (params.get('alpn') ?? '').split(',');
    }
    if (params.has('insecure')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('insecure'));
    }
    if (params.has('auth') && (params.get('auth') ?? '') !== '__PRESENT__') {
      proxy.authStr = params.get('auth');
    }
    if (params.has('mport') && (params.get('mport') ?? '') !== '__PRESENT__') {
      proxy.ports = params.get('mport');
    }
    if (params.has('upmbps') && (params.get('upmbps') ?? '') !== '__PRESENT__') {
      proxy.up = params.get('upmbps');
    }
    if (params.has('downmbps') && (params.get('downmbps') ?? '') !== '__PRESENT__') {
      proxy.down = params.get('downmbps');
    }
    if (params.has('obfs')) {
      const obfsVal: string = params.get('obfs') ?? '';
      proxy.obfs = obfsVal === '__PRESENT__' ? '' : obfsVal;
    } else if (params.has('obfsParam') && (params.get('obfsParam') ?? '') !== '__PRESENT__') {
      proxy.obfs = params.get('obfsParam');
    }
    if (params.has('fast-open')) {
      proxy.fastOpen = ClashUriParser.parseBoolOrPresence(params.get('fast-open'));
    }
    if (params.has('sni') && (params.get('sni') ?? '') !== '__PRESENT__') {
      proxy.sni = params.get('sni');
    } else if (params.has('peer') && (params.get('peer') ?? '') !== '__PRESENT__') {
      proxy.sni = params.get('peer');
    }
    if (params.has('recv-window-conn')) {
      proxy.recvWindowConn = ClashUriParser.parseInteger(params.get('recv-window-conn'));
    }
    if (params.has('recv-window')) {
      proxy.recvWindow = ClashUriParser.parseInteger(params.get('recv-window'));
    }
    if (params.has('ca')) { proxy.ca = params.get('ca'); }
    if (params.has('ca-str')) { proxy.caStr = params.get('ca-str'); }
    if (params.has('disable-mtu-discovery')) {
      proxy.disableMtuDiscovery = ClashUriParser.parseBoolOrPresence(params.get('disable-mtu-discovery'));
    }
    if (params.has('fingerprint')) { proxy.fingerprint = params.get('fingerprint'); }
    if (params.has('protocol') && (params.get('protocol') ?? '') !== '__PRESENT__') {
      proxy.protocol = params.get('protocol');
    }
    return proxy;
  }

  private static parseHysteria2(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['hysteria2', 'hy2'], '无效的 Hysteria2 URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 Hysteria2 URI');
    }
    const parts: ParsedUrlParts = ClashUriParser.parseUrlLike(afterScheme, true, '无效的 Hysteria2 URI');
    const portNum: number = ClashUriParser.parsePortOrDefault(parts.portText, 443);
    const password: string = ClashUriParser.safeDecodeURIComponent(parts.auth);
    const name: string = ClashUriParser.decodeAndTrim(parts.fragment) || `Hysteria2 ${parts.host}:${portNum}`;
    const proxy: ClashProxyEntry = {
      type: 'hysteria2',
      name: name,
      server: parts.host,
      port: portNum,
      password: password
    };
    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parts.query);
    const sni: string = (params.get('sni') ?? params.get('peer') ?? '').trim();
    if (sni.length > 0 && sni !== '__PRESENT__') {
      proxy.sni = sni;
    }
    const obfs: string = (params.get('obfs') ?? '').trim();
    if (obfs.length > 0 && obfs !== 'none' && obfs !== '__PRESENT__') {
      proxy.obfs = obfs;
    }
    const mport: string = (params.get('mport') ?? '').trim();
    if (mport.length > 0 && mport !== '__PRESENT__') {
      proxy.ports = mport;
    }
    const obfsPwd: string = (params.get('obfs-password') ?? '').trim();
    if (obfsPwd.length > 0 && obfsPwd !== '__PRESENT__') {
      proxy.obfsPassword = obfsPwd;
    }
    if (params.has('insecure')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('insecure'));
    }
    if (params.has('fastopen')) {
      proxy.tfo = ClashUriParser.parseBoolOrPresence(params.get('fastopen'));
    }
    const fp: string = (params.get('pinSHA256') ?? '').trim();
    if (fp.length > 0 && fp !== '__PRESENT__') {
      proxy.fingerprint = fp;
    }
    return proxy;
  }

  private static parseTuic(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['tuic'], '无效的 TUIC URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 TUIC URI');
    }
    const parts: ParsedUrlParts = ClashUriParser.parseUrlLike(afterScheme, true, '无效的 TUIC URI');
    const creds: string[] = ClashUriParser.splitOnce(parts.auth, ':');
    if (creds.length < 2) {
      throw new Error('无效的 TUIC URI');
    }
    const portNum: number = ClashUriParser.parsePortOrDefault(parts.portText, 443);
    const password: string = ClashUriParser.safeDecodeURIComponent(creds[1]);
    const name: string = ClashUriParser.decodeAndTrim(parts.fragment) || `TUIC ${parts.host}:${portNum}`;
    const proxy: ClashProxyEntry = {
      type: 'tuic',
      name: name,
      server: parts.host,
      port: portNum,
      uuid: creds[0],
      password: password
    };
    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parts.query);
    if (params.has('token')) { proxy.token = params.get('token'); }
    if (params.has('ip')) { proxy.ip = params.get('ip'); }
    if (params.has('heartbeat-interval')) { proxy.heartbeatInterval = ClashUriParser.parseInteger(params.get('heartbeat-interval')); }
    if (params.has('alpn') && (params.get('alpn') ?? '') !== '__PRESENT__') {
      proxy.alpn = (params.get('alpn') ?? '').split(',');
    }
    if (params.has('disable-sni')) { proxy.disableSni = ClashUriParser.parseBoolOrPresence(params.get('disable-sni')); }
    if (params.has('reduce-rtt')) { proxy.reduceRtt = ClashUriParser.parseBoolOrPresence(params.get('reduce-rtt')); }
    if (params.has('request-timeout')) { proxy.requestTimeout = ClashUriParser.parseInteger(params.get('request-timeout')); }
    if (params.has('udp-relay-mode')) { proxy.udpRelayMode = params.get('udp-relay-mode'); }
    if (params.has('congestion-controller')) { proxy.congestionController = params.get('congestion-controller'); }
    if (params.has('max-udp-relay-packet-size')) { proxy.maxUdpRelayPacketSize = ClashUriParser.parseInteger(params.get('max-udp-relay-packet-size')); }
    if (params.has('fast-open')) { proxy.fastOpen = ClashUriParser.parseBoolOrPresence(params.get('fast-open')); }
    if (params.has('skip-cert-verify')) { proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('skip-cert-verify')); }
    if (params.has('allow-insecure')) { proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('allow-insecure')); }
    if (params.has('max-open-streams')) { proxy.maxOpenStreams = ClashUriParser.parseInteger(params.get('max-open-streams')); }
    if (params.has('sni')) { proxy.sni = params.get('sni'); }
    return proxy;
  }

  private static parseWireguard(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['wireguard', 'wg'], '无效的 WireGuard URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 WireGuard URI');
    }
    const parts: ParsedUrlParts = ClashUriParser.parseUrlLike(afterScheme, false, '无效的 WireGuard URI');
    const portNum: number = ClashUriParser.parsePortOrDefault(parts.portText, 443);
    const privKey: string = ClashUriParser.safeDecodeURIComponent(parts.auth);
    const name: string = ClashUriParser.decodeAndTrim(parts.fragment) || `WireGuard ${parts.host}:${portNum}`;
    const proxy: ClashProxyEntry = {
      type: 'wireguard',
      name: name,
      server: parts.host,
      port: portNum,
      privateKey: privKey,
      udp: true
    };
    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parts.query);
    const addrRaw: string = (params.get('address') ?? params.get('ip') ?? '').trim();
    if (addrRaw.length > 0 && addrRaw !== '__PRESENT__') {
      const addrParts: string[] = addrRaw.split(',');
      for (let i: number = 0; i < addrParts.length; i++) {
        const cleanedIp: string = addrParts[i].trim().replace(/\/\d+$/, '').replace(/^\[/, '').replace(/\]$/, '');
        if (/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/.test(cleanedIp)) {
          proxy.ip = cleanedIp;
        } else if (cleanedIp.includes(':')) {
          proxy.ipv6 = cleanedIp;
        }
      }
    }
    const pubKey: string = (params.get('publickey') ?? params.get('public-key') ?? '').trim();
    if (pubKey.length > 0 && pubKey !== '__PRESENT__') {
      proxy.publicKey = pubKey;
    }
    const allowedIps: string = (params.get('allowed-ips') ?? '').trim();
    if (allowedIps.length > 0 && allowedIps !== '__PRESENT__') {
      proxy.allowedIps = allowedIps.split(',');
    }
    const psk: string = (params.get('pre-shared-key') ?? '').trim();
    if (psk.length > 0 && psk !== '__PRESENT__') {
      proxy.preSharedKey = psk;
    }
    const resRaw: string = (params.get('reserved') ?? '').trim();
    if (resRaw.length > 0 && resRaw !== '__PRESENT__') {
      const resItems: string[] = resRaw.split(',');
      const nums: number[] = [];
      for (let i: number = 0; i < resItems.length; i++) {
        const n: number | undefined = ClashUriParser.parseInteger(resItems[i]);
        if (n !== undefined) {
          nums.push(n);
        }
      }
      if (nums.length === 3) {
        proxy.reserved = nums;
      }
    }
    if (params.has('udp')) { proxy.udp = ClashUriParser.parseBoolOrPresence(params.get('udp')); }
    if (params.has('mtu')) { proxy.mtu = ClashUriParser.parseInteger(params.get('mtu')); }
    if (params.has('dialer-proxy')) { proxy.dialerProxy = params.get('dialer-proxy'); }
    if (params.has('remote-dns-resolve')) { proxy.remoteDnsResolve = ClashUriParser.parseBoolOrPresence(params.get('remote-dns-resolve')); }
    const dnsRaw: string = (params.get('dns') ?? '').trim();
    if (dnsRaw.length > 0 && dnsRaw !== '__PRESENT__') {
      proxy.dns = dnsRaw.split(',');
    }
    return proxy;
  }

  private static parseAnyTls(line: string): ClashProxyEntry {
    const afterScheme: string = ClashUriParser.stripUriScheme(line, ['anytls'], '无效的 AnyTLS URI');
    if (afterScheme.length === 0) {
      throw new Error('无效的 AnyTLS URI');
    }
    const parts: ParsedUrlParts = ClashUriParser.parseUrlLike(afterScheme, false, '无效的 AnyTLS URI');
    const portNum: number = ClashUriParser.parsePortOrDefault(parts.portText, 443);
    const name: string = ClashUriParser.decodeAndTrim(parts.fragment) || `AnyTLS ${parts.host}:${portNum}`;
    const proxy: ClashProxyEntry = {
      type: 'anytls',
      name: name,
      server: parts.host,
      port: portNum,
      udp: true
    };
    if (parts.auth.length > 0) {
      const creds: string[] = ClashUriParser.parseAuthCredentials(parts.auth);
      proxy.password = creds[1].length > 0 ? creds[1] : creds[0];
    }
    const params: Map<string, string> = ClashUriParser.parseQueryNormalized(parts.query);
    const sni: string = (params.get('sni') ?? '').trim();
    if (sni.length > 0 && sni !== '__PRESENT__') { proxy.sni = sni; }
    const alpnRaw: string = (params.get('alpn') ?? '').trim();
    if (alpnRaw.length > 0 && alpnRaw !== '__PRESENT__') {
      proxy.alpn = alpnRaw.split(',').map((s: string): string => s.trim()).filter((s: string): boolean => s.length > 0);
    }
    const fp: string = (params.get('fingerprint') ?? params.get('hpkp') ?? '').trim();
    if (fp.length > 0 && fp !== '__PRESENT__') { proxy.fingerprint = fp; }
    const clientFp: string = (params.get('client-fingerprint') ?? params.get('fp') ?? '').trim();
    if (clientFp.length > 0 && clientFp !== '__PRESENT__') { proxy.clientFingerprint = clientFp; }
    if (params.has('skip-cert-verify')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('skip-cert-verify'));
    } else if (params.has('insecure')) {
      proxy.skipCertVerify = ClashUriParser.parseBoolOrPresence(params.get('insecure'));
    }
    if (params.has('udp')) {
      proxy.udp = ClashUriParser.parseBoolOrPresence(params.get('udp'));
    }
    if (params.has('idle-session-check-interval')) {
      proxy.idleSessionCheckInterval = ClashUriParser.parseInteger(params.get('idle-session-check-interval'));
    }
    if (params.has('idle-session-timeout')) {
      proxy.idleSessionTimeout = ClashUriParser.parseInteger(params.get('idle-session-timeout'));
    }
    if (params.has('min-idle-session')) {
      proxy.minIdleSession = ClashUriParser.parseInteger(params.get('min-idle-session'));
    }
    return proxy;
  }

  static parseUri(uri: string): ClashProxyEntry {
    const info: NormalizedUriScheme = ClashUriParser.normalizeUriAndGetScheme(uri);
    const scheme: string = info.scheme;
    if (scheme === 'socks5' || scheme === 'socks') { return ClashUriParser.parseSocks(info.uri); }
    if (scheme === 'http' || scheme === 'https') { return ClashUriParser.parseHttp(info.uri); }
    if (scheme === 'ss') { return ClashUriParser.parseSs(info.uri); }
    if (scheme === 'ssr') { return ClashUriParser.parseSsr(info.uri); }
    if (scheme === 'vmess') { return ClashUriParser.parseVmess(info.uri); }
    if (scheme === 'vless') { return ClashUriParser.parseVless(info.uri); }
    if (scheme === 'trojan') { return ClashUriParser.parseTrojan(info.uri); }
    if (scheme === 'hysteria' || scheme === 'hy') { return ClashUriParser.parseHysteria(info.uri); }
    if (scheme === 'hysteria2' || scheme === 'hy2') { return ClashUriParser.parseHysteria2(info.uri); }
    if (scheme === 'tuic') { return ClashUriParser.parseTuic(info.uri); }
    if (scheme === 'wireguard' || scheme === 'wg') { return ClashUriParser.parseWireguard(info.uri); }
    if (scheme === 'anytls') { return ClashUriParser.parseAnyTls(info.uri); }
    throw new Error(`不支持的节点协议 URI: ${scheme}`);
  }

  static isUriSchemeSupported(uri: string): boolean {
    const scheme: string = ClashUriParser.normalizeUriAndGetScheme(uri).scheme;
    return scheme === 'socks5' || scheme === 'socks' || scheme === 'http' || scheme === 'https' ||
      scheme === 'ss' || scheme === 'ssr' || scheme === 'vmess' || scheme === 'vless' ||
      scheme === 'trojan' || scheme === 'hysteria' || scheme === 'hy' ||
      scheme === 'hysteria2' || scheme === 'hy2' || scheme === 'tuic' ||
      scheme === 'wireguard' || scheme === 'wg' || scheme === 'anytls';
  }

  static hasAnySupportedUriLine(input: string): boolean {
    const decoded: string = ClashUriParser.decodeBatchText(input);
    const lines: string[] = decoded.split(/\r?\n/);
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length > 0 && ClashUriParser.isUriSchemeSupported(line)) {
        return true;
      }
    }
    return false;
  }

  private static decodeBatchText(rawInput: string): string {
    const trimmed: string = rawInput.replace(/^\uFEFF/, '').trim();
    if (trimmed.length === 0 || trimmed.includes('://')) {
      return trimmed;
    }
    const decoded: string = ClashUriParser.decodeBase64Strict(trimmed);
    return decoded.includes('://') ? decoded : trimmed;
  }

  static parseBatchUris(rawInput: string): ClashUriBatchResult {
    const text: string = ClashUriParser.decodeBatchText(rawInput);
    const lines: string[] = text.split(/\r?\n/);
    const entries: ClashProxyEntry[] = [];
    const errors: string[] = [];
    const seenNames: Set<string> = new Set<string>();
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      try {
        const entry: ClashProxyEntry = ClashUriParser.parseUri(line);
        let uniqueName: string = entry.name;
        if (seenNames.has(uniqueName)) {
          let suffix: number = 2;
          while (seenNames.has(`${entry.name} (${suffix})`)) {
            suffix++;
          }
          uniqueName = `${entry.name} (${suffix})`;
          entry.name = uniqueName;
        }
        seenNames.add(uniqueName);
        entries.push(entry);
      } catch (err) {
        errors.push(`第 ${i + 1} 行: ${(err as Error).message}`);
      }
    }
    return { entries: entries, errors: errors };
  }

  static buildEntryFromManualForm(form: ManualProxyNodeForm): ClashProxyEntry {
    const server: string = form.server.trim();
    if (server.length === 0) {
      throw new Error('服务器地址不能为空');
    }
    const port: number = form.port;
    if (!Number.isSafeInteger(port) || port < 1 || port > 65535) {
      throw new Error('端口必须在 1 ~ 65535 之间');
    }
    const proto: string = form.protocol.trim().toLowerCase();
    const fallbackName: string = `${proto.toUpperCase()} ${server}:${port}`;
    const name: string = form.name.trim().length > 0 ? form.name.trim() : fallbackName;
    const entry: ClashProxyEntry = {
      name: name,
      type: proto,
      server: server,
      port: port,
      udp: form.udp
    };

    if (proto === 'socks5' || proto === 'http') {
      if (form.username.trim().length > 0) {
        entry.username = form.username.trim();
      }
      if (form.password.length > 0) {
        entry.password = form.password;
      }
      if (form.tls) {
        entry.tls = true;
      }
      if (form.skipCertVerify) {
        entry.skipCertVerify = true;
      }
      if (form.clientFingerprint.trim().length > 0) {
        entry.fingerprint = form.clientFingerprint.trim();
      }
    } else if (proto === 'ss') {
      entry.cipher = form.cipher.trim().length > 0 ? form.cipher.trim() : 'aes-256-gcm';
      entry.password = form.password;
    } else if (proto === 'trojan') {
      if (form.password.length === 0) {
        throw new Error('Trojan 节点必须填写密码');
      }
      entry.password = form.password;
      if (form.sni.trim().length > 0) { entry.sni = form.sni.trim(); }
      if (form.skipCertVerify) { entry.skipCertVerify = true; }
      if (form.clientFingerprint.trim().length > 0) { entry.clientFingerprint = form.clientFingerprint.trim(); }
    } else if (proto === 'vmess') {
      if (form.uuid.trim().length === 0) {
        throw new Error('VMess 节点必须填写 UUID');
      }
      entry.uuid = form.uuid.trim();
      entry.cipher = form.cipher.trim().length > 0 ? form.cipher.trim() : 'auto';
      entry.alterId = 0;
      if (form.tls) { entry.tls = true; }
      if (form.sni.trim().length > 0) { entry.servername = form.sni.trim(); }
      if (form.skipCertVerify) { entry.skipCertVerify = true; }
    } else if (proto === 'vless') {
      if (form.uuid.trim().length === 0) {
        throw new Error('VLESS 节点必须填写 UUID');
      }
      entry.uuid = form.uuid.trim();
      if (form.tls) { entry.tls = true; }
      if (form.sni.trim().length > 0) { entry.servername = form.sni.trim(); }
      if (form.flow.trim().length > 0) { entry.flow = form.flow.trim(); }
      if (form.skipCertVerify) { entry.skipCertVerify = true; }
      if (form.clientFingerprint.trim().length > 0) { entry.clientFingerprint = form.clientFingerprint.trim(); }
      if (form.publicKey.trim().length > 0) {
        entry.realityOpts = {
          publicKey: form.publicKey.trim(),
          shortId: form.shortId.trim().length > 0 ? form.shortId.trim() : undefined
        };
      }
    } else if (proto === 'hysteria2') {
      if (form.password.length === 0) {
        throw new Error('Hysteria2 节点必须填写密码');
      }
      entry.password = form.password;
      if (form.sni.trim().length > 0) { entry.sni = form.sni.trim(); }
      if (form.skipCertVerify) { entry.skipCertVerify = true; }
      if (form.obfs.trim().length > 0) {
        entry.obfs = form.obfs.trim();
        if (form.obfsPassword.length > 0) {
          entry.obfsPassword = form.obfsPassword;
        }
      }
    } else if (proto === 'tuic') {
      if (form.uuid.trim().length === 0) {
        throw new Error('TUIC 节点必须填写 UUID');
      }
      entry.uuid = form.uuid.trim();
      entry.password = form.password;
      if (form.sni.trim().length > 0) { entry.sni = form.sni.trim(); }
      if (form.skipCertVerify) { entry.skipCertVerify = true; }
    } else if (proto === 'anytls') {
      entry.password = form.password;
      if (form.sni.trim().length > 0) { entry.sni = form.sni.trim(); }
      if (form.skipCertVerify) { entry.skipCertVerify = true; }
      if (form.clientFingerprint.trim().length > 0) { entry.clientFingerprint = form.clientFingerprint.trim(); }
    } else if (proto === 'wireguard') {
      if (form.privateKey.trim().length === 0) {
        throw new Error('WireGuard 节点必须填写私钥');
      }
      entry.privateKey = form.privateKey.trim();
      if (form.peerPublicKey.trim().length > 0) { entry.publicKey = form.peerPublicKey.trim(); }
      if (form.localIp.trim().length > 0) { entry.ip = form.localIp.trim(); }
      entry.udp = true;
    } else {
      throw new Error(`不支持的节点协议类型: ${form.protocol}`);
    }

    if (form.network === 'ws' || form.network === 'grpc') {
      entry.network = form.network;
      if (form.network === 'ws' && (form.wsHost.trim().length > 0 || form.wsPath.trim().length > 0)) {
        const wsHeaders: Record<string, string> = {};
        if (form.wsHost.trim().length > 0) {
          wsHeaders['Host'] = form.wsHost.trim();
        }
        entry.wsOpts = {
          path: form.wsPath.trim().length > 0 ? form.wsPath.trim() : '/',
          headers: form.wsHost.trim().length > 0 ? wsHeaders : undefined
        };
      } else if (form.network === 'grpc' && form.wsPath.trim().length > 0) {
        entry.grpcOpts = { serviceName: form.wsPath.trim() };
      }
    }
    return entry;
  }

  static serializeProxyEntryYaml(entry: ClashProxyEntry, indent: string = '  '): string {
    const pad: string = indent + '  ';
    const nestedPad: string = pad + '  ';
    const lines: string[] = [
      `${indent}- name: ${JSON.stringify(entry.name)}`,
      `${pad}type: ${entry.type}`,
      `${pad}server: ${JSON.stringify(entry.server)}`,
      `${pad}port: ${entry.port}`
    ];

    if (entry.username !== undefined && entry.username.length > 0) {
      lines.push(`${pad}username: ${JSON.stringify(entry.username)}`);
    }
    if (entry.password !== undefined && entry.password.length > 0) {
      lines.push(`${pad}password: ${JSON.stringify(entry.password)}`);
    }
    if (entry.uuid !== undefined && entry.uuid.length > 0) {
      lines.push(`${pad}uuid: ${JSON.stringify(entry.uuid)}`);
    }
    if (entry.cipher !== undefined && entry.cipher.length > 0) {
      lines.push(`${pad}cipher: ${JSON.stringify(entry.cipher)}`);
    }
    if (entry.alterId !== undefined) {
      lines.push(`${pad}alterId: ${entry.alterId}`);
    }
    if (entry.encryption !== undefined) {
      lines.push(`${pad}encryption: ${JSON.stringify(entry.encryption)}`);
    }
    if (entry.flow !== undefined && entry.flow.length > 0) {
      lines.push(`${pad}flow: ${JSON.stringify(entry.flow)}`);
    }
    if (entry.tls !== undefined) {
      lines.push(`${pad}tls: ${entry.tls}`);
    }
    if (entry.sni !== undefined && entry.sni.length > 0) {
      lines.push(`${pad}sni: ${JSON.stringify(entry.sni)}`);
    }
    if (entry.servername !== undefined && entry.servername.length > 0) {
      lines.push(`${pad}servername: ${JSON.stringify(entry.servername)}`);
    }
    if (entry.skipCertVerify !== undefined) {
      lines.push(`${pad}skip-cert-verify: ${entry.skipCertVerify}`);
    }
    if (entry.udp !== undefined) {
      lines.push(`${pad}udp: ${entry.udp}`);
    }
    if (entry.tfo !== undefined) {
      lines.push(`${pad}tfo: ${entry.tfo}`);
    }
    if (entry.fastOpen !== undefined) {
      lines.push(`${pad}fast-open: ${entry.fastOpen}`);
    }
    if (entry.udpOverTcp !== undefined) {
      lines.push(`${pad}udp-over-tcp: ${entry.udpOverTcp}`);
    }
    if (entry.ipVersion !== undefined && entry.ipVersion.length > 0) {
      lines.push(`${pad}ip-version: ${JSON.stringify(entry.ipVersion)}`);
    }
    if (entry.fingerprint !== undefined && entry.fingerprint.length > 0) {
      lines.push(`${pad}fingerprint: ${JSON.stringify(entry.fingerprint)}`);
    }
    if (entry.clientFingerprint !== undefined && entry.clientFingerprint.length > 0) {
      lines.push(`${pad}client-fingerprint: ${JSON.stringify(entry.clientFingerprint)}`);
    }
    if (entry.alpn !== undefined && entry.alpn.length > 0) {
      lines.push(`${pad}alpn:`);
      for (let i: number = 0; i < entry.alpn.length; i++) {
        lines.push(`${nestedPad}- ${JSON.stringify(entry.alpn[i])}`);
      }
    }
    if (entry.network !== undefined && entry.network.length > 0) {
      lines.push(`${pad}network: ${JSON.stringify(entry.network)}`);
    }
    if (entry.protocol !== undefined && entry.protocol.length > 0) {
      lines.push(`${pad}protocol: ${JSON.stringify(entry.protocol)}`);
    }
    if (entry.protocolParam !== undefined && entry.protocolParam.length > 0) {
      lines.push(`${pad}protocol-param: ${JSON.stringify(entry.protocolParam)}`);
    }
    if (entry.obfs !== undefined && entry.obfs.length > 0) {
      lines.push(`${pad}obfs: ${JSON.stringify(entry.obfs)}`);
    }
    if (entry.obfsParam !== undefined && entry.obfsParam.length > 0) {
      lines.push(`${pad}obfs-param: ${JSON.stringify(entry.obfsParam)}`);
    }
    if (entry.obfsPassword !== undefined && entry.obfsPassword.length > 0) {
      lines.push(`${pad}obfs-password: ${JSON.stringify(entry.obfsPassword)}`);
    }
    if (entry.ports !== undefined && entry.ports.length > 0) {
      lines.push(`${pad}ports: ${JSON.stringify(entry.ports)}`);
    }
    if (entry.authStr !== undefined && entry.authStr.length > 0) {
      lines.push(`${pad}auth-str: ${JSON.stringify(entry.authStr)}`);
    }
    if (entry.up !== undefined && entry.up.length > 0) {
      lines.push(`${pad}up: ${JSON.stringify(entry.up)}`);
    }
    if (entry.down !== undefined && entry.down.length > 0) {
      lines.push(`${pad}down: ${JSON.stringify(entry.down)}`);
    }
    if (entry.recvWindowConn !== undefined) { lines.push(`${pad}recv-window-conn: ${entry.recvWindowConn}`); }
    if (entry.recvWindow !== undefined) { lines.push(`${pad}recv-window: ${entry.recvWindow}`); }
    if (entry.ca !== undefined && entry.ca.length > 0) { lines.push(`${pad}ca: ${JSON.stringify(entry.ca)}`); }
    if (entry.caStr !== undefined && entry.caStr.length > 0) { lines.push(`${pad}ca-str: ${JSON.stringify(entry.caStr)}`); }
    if (entry.disableMtuDiscovery !== undefined) { lines.push(`${pad}disable-mtu-discovery: ${entry.disableMtuDiscovery}`); }
    if (entry.token !== undefined && entry.token.length > 0) { lines.push(`${pad}token: ${JSON.stringify(entry.token)}`); }
    if (entry.ip !== undefined && entry.ip.length > 0) { lines.push(`${pad}ip: ${JSON.stringify(entry.ip)}`); }
    if (entry.ipv6 !== undefined && entry.ipv6.length > 0) { lines.push(`${pad}ipv6: ${JSON.stringify(entry.ipv6)}`); }
    if (entry.heartbeatInterval !== undefined) { lines.push(`${pad}heartbeat-interval: ${entry.heartbeatInterval}`); }
    if (entry.disableSni !== undefined) { lines.push(`${pad}disable-sni: ${entry.disableSni}`); }
    if (entry.reduceRtt !== undefined) { lines.push(`${pad}reduce-rtt: ${entry.reduceRtt}`); }
    if (entry.requestTimeout !== undefined) { lines.push(`${pad}request-timeout: ${entry.requestTimeout}`); }
    if (entry.udpRelayMode !== undefined && entry.udpRelayMode.length > 0) { lines.push(`${pad}udp-relay-mode: ${JSON.stringify(entry.udpRelayMode)}`); }
    if (entry.congestionController !== undefined && entry.congestionController.length > 0) { lines.push(`${pad}congestion-controller: ${JSON.stringify(entry.congestionController)}`); }
    if (entry.maxUdpRelayPacketSize !== undefined) { lines.push(`${pad}max-udp-relay-packet-size: ${entry.maxUdpRelayPacketSize}`); }
    if (entry.maxOpenStreams !== undefined) { lines.push(`${pad}max-open-streams: ${entry.maxOpenStreams}`); }
    if (entry.privateKey !== undefined && entry.privateKey.length > 0) { lines.push(`${pad}private-key: ${JSON.stringify(entry.privateKey)}`); }
    if (entry.publicKey !== undefined && entry.publicKey.length > 0) { lines.push(`${pad}public-key: ${JSON.stringify(entry.publicKey)}`); }
    if (entry.preSharedKey !== undefined && entry.preSharedKey.length > 0) { lines.push(`${pad}pre-shared-key: ${JSON.stringify(entry.preSharedKey)}`); }
    if (entry.allowedIps !== undefined && entry.allowedIps.length > 0) {
      lines.push(`${pad}allowed-ips:`);
      for (let i: number = 0; i < entry.allowedIps.length; i++) {
        lines.push(`${nestedPad}- ${JSON.stringify(entry.allowedIps[i])}`);
      }
    }
    if (entry.reserved !== undefined && entry.reserved.length > 0) {
      lines.push(`${pad}reserved: [${entry.reserved.join(', ')}]`);
    }
    if (entry.mtu !== undefined) { lines.push(`${pad}mtu: ${entry.mtu}`); }
    if (entry.dialerProxy !== undefined && entry.dialerProxy.length > 0) { lines.push(`${pad}dialer-proxy: ${JSON.stringify(entry.dialerProxy)}`); }
    if (entry.remoteDnsResolve !== undefined) { lines.push(`${pad}remote-dns-resolve: ${entry.remoteDnsResolve}`); }
    if (entry.dns !== undefined && entry.dns.length > 0) {
      lines.push(`${pad}dns:`);
      for (let i: number = 0; i < entry.dns.length; i++) {
        lines.push(`${nestedPad}- ${JSON.stringify(entry.dns[i])}`);
      }
    }
    if (entry.idleSessionCheckInterval !== undefined) { lines.push(`${pad}idle-session-check-interval: ${entry.idleSessionCheckInterval}`); }
    if (entry.idleSessionTimeout !== undefined) { lines.push(`${pad}idle-session-timeout: ${entry.idleSessionTimeout}`); }
    if (entry.minIdleSession !== undefined) { lines.push(`${pad}min-idle-session: ${entry.minIdleSession}`); }
    if (entry.plugin !== undefined && entry.plugin.length > 0) { lines.push(`${pad}plugin: ${JSON.stringify(entry.plugin)}`); }
    if (entry.pluginOpts !== undefined) {
      lines.push(`${pad}plugin-opts:`);
      if (entry.pluginOpts.mode !== undefined) { lines.push(`${nestedPad}mode: ${JSON.stringify(entry.pluginOpts.mode)}`); }
      if (entry.pluginOpts.host !== undefined) { lines.push(`${nestedPad}host: ${JSON.stringify(entry.pluginOpts.host)}`); }
      if (entry.pluginOpts.path !== undefined) { lines.push(`${nestedPad}path: ${JSON.stringify(entry.pluginOpts.path)}`); }
      if (entry.pluginOpts.tls !== undefined) { lines.push(`${nestedPad}tls: ${entry.pluginOpts.tls}`); }
    }
    if (entry.wsOpts !== undefined) {
      lines.push(`${pad}ws-opts:`);
      if (entry.wsOpts.path !== undefined) { lines.push(`${nestedPad}path: ${JSON.stringify(entry.wsOpts.path)}`); }
      if (entry.wsOpts.v2rayHttpUpgrade !== undefined) { lines.push(`${nestedPad}v2ray-http-upgrade: ${entry.wsOpts.v2rayHttpUpgrade}`); }
      if (entry.wsOpts.v2rayHttpUpgradeFastOpen !== undefined) { lines.push(`${nestedPad}v2ray-http-upgrade-fast-open: ${entry.wsOpts.v2rayHttpUpgradeFastOpen}`); }
      if (entry.wsOpts.headers !== undefined) {
        const headerKeys: string[] = Object.keys(entry.wsOpts.headers);
        if (headerKeys.length > 0) {
          lines.push(`${nestedPad}headers:`);
          for (let i: number = 0; i < headerKeys.length; i++) {
            const k: string = headerKeys[i];
            lines.push(`${nestedPad}  ${k}: ${JSON.stringify(entry.wsOpts.headers[k])}`);
          }
        }
      }
    }
    if (entry.h2Opts !== undefined) {
      lines.push(`${pad}h2-opts:`);
      if (entry.h2Opts.host !== undefined) { lines.push(`${nestedPad}host: ${JSON.stringify(entry.h2Opts.host)}`); }
      if (entry.h2Opts.path !== undefined) { lines.push(`${nestedPad}path: ${JSON.stringify(entry.h2Opts.path)}`); }
    }
    if (entry.httpOpts !== undefined) {
      lines.push(`${pad}http-opts:`);
      if (entry.httpOpts.path !== undefined && entry.httpOpts.path.length > 0) {
        lines.push(`${nestedPad}path:`);
        for (let i: number = 0; i < entry.httpOpts.path.length; i++) {
          lines.push(`${nestedPad}  - ${JSON.stringify(entry.httpOpts.path[i])}`);
        }
      }
      if (entry.httpOpts.hostHeaders !== undefined && entry.httpOpts.hostHeaders.length > 0) {
        lines.push(`${nestedPad}headers:`);
        lines.push(`${nestedPad}  Host:`);
        for (let i: number = 0; i < entry.httpOpts.hostHeaders.length; i++) {
          lines.push(`${nestedPad}    - ${JSON.stringify(entry.httpOpts.hostHeaders[i])}`);
        }
      }
    }
    if (entry.grpcOpts !== undefined) {
      lines.push(`${pad}grpc-opts:`);
      lines.push(`${nestedPad}grpc-service-name: ${JSON.stringify(entry.grpcOpts.serviceName)}`);
    }
    if (entry.xhttpOpts !== undefined) {
      lines.push(`${pad}xhttp-opts:`);
      if (entry.xhttpOpts.host !== undefined) { lines.push(`${nestedPad}host: ${JSON.stringify(entry.xhttpOpts.host)}`); }
      if (entry.xhttpOpts.path !== undefined) { lines.push(`${nestedPad}path: ${JSON.stringify(entry.xhttpOpts.path)}`); }
      if (entry.xhttpOpts.mode !== undefined) { lines.push(`${nestedPad}mode: ${JSON.stringify(entry.xhttpOpts.mode)}`); }
    }
    if (entry.realityOpts !== undefined) {
      lines.push(`${pad}reality-opts:`);
      if (entry.realityOpts.publicKey !== undefined) { lines.push(`${nestedPad}public-key: ${JSON.stringify(entry.realityOpts.publicKey)}`); }
      if (entry.realityOpts.shortId !== undefined) { lines.push(`${nestedPad}short-id: ${JSON.stringify(entry.realityOpts.shortId)}`); }
    }
    if (entry.ssOpts !== undefined) {
      lines.push(`${pad}ss-opts:`);
      lines.push(`${nestedPad}enabled: ${entry.ssOpts.enabled}`);
      lines.push(`${nestedPad}method: ${JSON.stringify(entry.ssOpts.method)}`);
      lines.push(`${nestedPad}password: ${JSON.stringify(entry.ssOpts.password)}`);
    }
    return lines.join('\n');
  }

  static buildCompleteYamlFromEntries(entries: ClashProxyEntry[]): string {
    const out: string[] = [
      'mixed-port: 7890',
      'allow-lan: false',
      'mode: rule',
      'log-level: info',
      'ipv6: false',
      'unified-delay: true',
      'tcp-concurrent: true',
      '',
      'dns:',
      '  enable: true',
      '  enhanced-mode: fake-ip',
      '  fake-ip-range: 198.18.0.1/16',
      '  nameserver:',
      '    - https://1.1.1.1/dns-query',
      '',
      'proxies:'
    ];
    for (let i: number = 0; i < entries.length; i++) {
      out.push(ClashUriParser.serializeProxyEntryYaml(entries[i], '  '));
    }
    out.push('');
    out.push('proxy-groups:');
    out.push('  - name: "Proxy"');
    out.push('    type: select');
    out.push('    proxies:');
    for (let i: number = 0; i < entries.length; i++) {
      out.push(`      - ${JSON.stringify(entries[i].name)}`);
    }
    out.push('      - DIRECT');
    out.push('  - name: "Auto"');
    out.push('    type: url-test');
    out.push('    url: "https://www.gstatic.com/generate_204"');
    out.push('    interval: 300');
    out.push('    proxies:');
    for (let i: number = 0; i < entries.length; i++) {
      out.push(`      - ${JSON.stringify(entries[i].name)}`);
    }
    out.push('');
    out.push('rules:');
    out.push('  - GEOIP,CN,DIRECT');
    out.push('  - MATCH,Proxy');
    out.push('');
    return out.join('\n');
  }

  private static extractSectionLines(lines: string[], keyName: string): number[] {
    let start: number = -1;
    let end: number = lines.length;
    for (let i: number = 0; i < lines.length; i++) {
      const scanned: string = ProxyChainConfig.stripComment(lines[i]);
      if (scanned.trim().length === 0 || scanned.trim() === '---') {
        continue;
      }
      if (scanned.trim() === '...') {
        if (start !== -1 && end === lines.length) {
          end = i;
        }
        continue;
      }
      if (new RegExp(`^${keyName}\\s*:`).test(scanned)) {
        start = i;
      } else if (start !== -1 && end === lines.length && /^\S[^\n]*:/.test(scanned) && !scanned.startsWith('-')) {
        end = i;
      }
    }
    return [start, end];
  }

  static repairBrokenProxiesIndent(profileYaml: string): string {
    const cleanYaml: string = profileYaml.replace(/^\uFEFF/, '');
    const lines: string[] = cleanYaml.split(/\r?\n/);
    const bounds: number[] = ClashUriParser.extractSectionLines(lines, 'proxies');
    const sectionStart: number = bounds[0];
    const sectionEnd: number = bounds[1];
    if (sectionStart < 0) {
      return profileYaml;
    }
    const inlineVal: string = ProxyChainConfig.stripComment(
      lines[sectionStart].substring(lines[sectionStart].indexOf(':') + 1)
    ).trim();
    if (inlineVal.length > 0) {
      return profileYaml;
    }

    let firstIndent: number = -1;
    let activeShift: number = 0;
    let changed: boolean = false;
    const repaired: string[] = lines.slice();

    for (let i: number = sectionStart + 1; i < sectionEnd; i++) {
      const line: string = lines[i];
      const stripped: string = ProxyChainConfig.stripComment(line);
      const trimmed: string = stripped.trim();
      if (trimmed.length === 0) {
        continue;
      }
      const indent: number = line.search(/\S/);
      if (indent < 0) {
        continue;
      }

      if (trimmed.startsWith('-')) {
        if (firstIndent === -1) {
          firstIndent = indent;
          activeShift = 0;
          continue;
        }
        if (indent === firstIndent) {
          activeShift = 0;
          continue;
        }
        const afterDash: string = trimmed.substring(1).trim();
        const looksLikeSiblingProxy: boolean =
          (afterDash.startsWith('{') && (afterDash.includes('name:') || afterDash.includes('type:') || afterDash.includes('server:'))) ||
          /^['"]?(name|type|server)\s*['"]?\s*:/.test(afterDash);
        if (indent > firstIndent && looksLikeSiblingProxy) {
          activeShift = firstIndent - indent;
          repaired[i] = ' '.repeat(firstIndent) + line.trimStart();
          changed = true;
          continue;
        }
      }

      if (activeShift !== 0) {
        const nextIndent: number = indent + activeShift;
        if (nextIndent > firstIndent) {
          repaired[i] = ' '.repeat(nextIndent) + line.trimStart();
          changed = true;
        } else {
          activeShift = 0;
        }
      }
    }

    return changed ? repaired.join('\n') : profileYaml;
  }

  static listProfileProxyBlocks(profileYaml: string): ClashProfileProxyItem[] {
    const lines: string[] = ClashUriParser.repairBrokenProxiesIndent(profileYaml).replace(/^\uFEFF/, '').split(/\r?\n/);
    const bounds: number[] = ClashUriParser.extractSectionLines(lines, 'proxies');
    const sectionStart: number = bounds[0];
    const sectionEnd: number = bounds[1];
    if (sectionStart < 0) {
      return [];
    }

    const blocks: string[][] = [];
    const blockIndents: number[] = [];
    const isFlowFlags: boolean[] = [];
    const inline: string = ProxyChainConfig.stripComment(lines[sectionStart].substring(lines[sectionStart].indexOf(':') + 1)).trim();
    if (inline.startsWith('[') && inline.endsWith(']')) {
      const items: string[] = ProxyChainConfig.splitFlow(inline.substring(1, inline.length - 1));
      for (let i: number = 0; i < items.length; i++) {
        blocks.push(['  - ' + items[i]]);
        blockIndents.push(2);
        isFlowFlags.push(items[i].trim().startsWith('{'));
      }
    } else if (inline.length === 0) {
      let pending: string[] = [];
      let listIndent: number = -1;
      for (let i: number = sectionStart + 1; i < sectionEnd; i++) {
        const line: string = lines[i];
        const indent: number = line.search(/\S/);
        if (/^\s*-\s/.test(line) && (listIndent === -1 || indent === listIndent)) {
          if (pending.length > 0) {
            blocks.push(pending);
            blockIndents.push(listIndent);
            isFlowFlags.push(pending[0].trim().substring(1).trim().startsWith('{'));
          }
          listIndent = indent;
          pending = [line];
        } else if (pending.length > 0) {
          pending.push(line);
        }
      }
      if (pending.length > 0) {
        blocks.push(pending);
        blockIndents.push(listIndent);
        isFlowFlags.push(pending[0].trim().substring(1).trim().startsWith('{'));
      }
    }

    const result: ClashProfileProxyItem[] = [];
    for (let i: number = 0; i < blocks.length; i++) {
      const blk: string[] = blocks[i];
      const indent: number = blockIndents[i];
      const isFlow: boolean = isFlowFlags[i];
      let name: string = '';
      let proto: string = 'Proxy';
      if (isFlow) {
        const joined: string = blk.map((l: string): string => ProxyChainConfig.stripComment(l)).join(' ').trim();
        const mapStr: string = joined.substring(1).trim();
        if (mapStr.startsWith('{') && mapStr.endsWith('}')) {
          const fields: string[] = ProxyChainConfig.splitFlow(mapStr.substring(1, mapStr.length - 1));
          for (let j: number = 0; j < fields.length; j++) {
            const f: LexiYamlField = ProxyChainConfig.field(fields[j]);
            if (f.key === 'name') { name = ProxyChainConfig.scalar(f.rawValue); }
            else if (f.key === 'type') { proto = ProxyChainConfig.scalar(f.rawValue); }
          }
        }
      } else {
        for (let j: number = 0; j < blk.length; j++) {
          const entry: string = j === 0 ? blk[0].trim().substring(1).trim() : blk[j].trim();
          if (j !== 0 && blk[j].search(/\S/) !== indent + 2) { continue; }
          const f: LexiYamlField = ProxyChainConfig.field(entry);
          if (f.key === 'name') { name = ProxyChainConfig.scalar(f.rawValue); }
          else if (f.key === 'type') { proto = ProxyChainConfig.scalar(f.rawValue); }
        }
      }
      if (name.length > 0) {
        result.push({
          name: name,
          protocol: proto.length > 0 ? proto : 'Proxy',
          rawBlockLines: blk,
          isFlow: isFlow,
          indent: indent
        });
      }
    }
    return result;
  }

  private static deduplicateAddedEntries(entries: ClashProxyEntry[], usedNames: Set<string>): ClashProxyEntry[] {
    const out: ClashProxyEntry[] = [];
    for (let i: number = 0; i < entries.length; i++) {
      const orig: ClashProxyEntry = entries[i];
      let candidateName: string = orig.name;
      if (usedNames.has(candidateName)) {
        let suffix: number = 2;
        while (usedNames.has(`${orig.name} (${suffix})`)) {
          suffix++;
        }
        candidateName = `${orig.name} (${suffix})`;
      }
      usedNames.add(candidateName);
      out.push({
        name: candidateName,
        type: orig.type,
        server: orig.server,
        port: orig.port,
        username: orig.username,
        password: orig.password,
        uuid: orig.uuid,
        cipher: orig.cipher,
        alterId: orig.alterId,
        tls: orig.tls,
        skipCertVerify: orig.skipCertVerify,
        udp: orig.udp,
        tfo: orig.tfo,
        fastOpen: orig.fastOpen,
        udpOverTcp: orig.udpOverTcp,
        ipVersion: orig.ipVersion,
        fingerprint: orig.fingerprint,
        clientFingerprint: orig.clientFingerprint,
        sni: orig.sni,
        servername: orig.servername,
        alpn: orig.alpn,
        network: orig.network,
        flow: orig.flow,
        encryption: orig.encryption,
        protocol: orig.protocol,
        protocolParam: orig.protocolParam,
        obfs: orig.obfs,
        obfsParam: orig.obfsParam,
        obfsPassword: orig.obfsPassword,
        ports: orig.ports,
        authStr: orig.authStr,
        up: orig.up,
        down: orig.down,
        recvWindowConn: orig.recvWindowConn,
        recvWindow: orig.recvWindow,
        ca: orig.ca,
        caStr: orig.caStr,
        disableMtuDiscovery: orig.disableMtuDiscovery,
        token: orig.token,
        ip: orig.ip,
        ipv6: orig.ipv6,
        heartbeatInterval: orig.heartbeatInterval,
        disableSni: orig.disableSni,
        reduceRtt: orig.reduceRtt,
        requestTimeout: orig.requestTimeout,
        udpRelayMode: orig.udpRelayMode,
        congestionController: orig.congestionController,
        maxUdpRelayPacketSize: orig.maxUdpRelayPacketSize,
        maxOpenStreams: orig.maxOpenStreams,
        privateKey: orig.privateKey,
        publicKey: orig.publicKey,
        allowedIps: orig.allowedIps,
        preSharedKey: orig.preSharedKey,
        reserved: orig.reserved,
        mtu: orig.mtu,
        dialerProxy: orig.dialerProxy,
        remoteDnsResolve: orig.remoteDnsResolve,
        dns: orig.dns,
        idleSessionCheckInterval: orig.idleSessionCheckInterval,
        idleSessionTimeout: orig.idleSessionTimeout,
        minIdleSession: orig.minIdleSession,
        plugin: orig.plugin,
        pluginOpts: orig.pluginOpts,
        wsOpts: orig.wsOpts,
        h2Opts: orig.h2Opts,
        httpOpts: orig.httpOpts,
        grpcOpts: orig.grpcOpts,
        xhttpOpts: orig.xhttpOpts,
        realityOpts: orig.realityOpts,
        ssOpts: orig.ssOpts
      });
    }
    return out;
  }

  private static updateProxyGroupsSection(
    yamlText: string,
    addedNames: string[],
    deleteSet: Set<string>,
    allRemainingNames: string[]
  ): string {
    const lines: string[] = yamlText.split(/\r?\n/);
    const bounds: number[] = ClashUriParser.extractSectionLines(lines, 'proxy-groups');
    const gStart: number = bounds[0];
    const gEnd: number = bounds[1];

    if (gStart < 0) {
      if (allRemainingNames.length === 0) {
        return yamlText;
      }
      const groupLines: string[] = [
        'proxy-groups:',
        '  - name: "Proxy"',
        '    type: select',
        '    proxies:'
      ];
      for (let i: number = 0; i < allRemainingNames.length; i++) {
        groupLines.push(`      - ${JSON.stringify(allRemainingNames[i])}`);
      }
      groupLines.push('      - DIRECT');
      const ruleBounds: number[] = ClashUriParser.extractSectionLines(lines, 'rules');
      const insertAt: number = ruleBounds[0] >= 0 ? ruleBounds[0] : lines.length;
      const merged: string[] = lines.slice(0, insertAt).concat(groupLines).concat(lines.slice(insertAt));
      return merged.join('\n');
    }

    const sectionText: string = lines.slice(gStart, gEnd).join('\n');
    const inlineVal: string = ProxyChainConfig.stripComment(lines[gStart].substring(lines[gStart].indexOf(':') + 1)).trim();
    if (inlineVal === '[]') {
      if (allRemainingNames.length === 0) {
        return yamlText;
      }
      const newGroupLines: string[] = [
        'proxy-groups:',
        '  - name: "Proxy"',
        '    type: select',
        '    proxies:'
      ];
      for (let i: number = 0; i < allRemainingNames.length; i++) {
        newGroupLines.push(`      - ${JSON.stringify(allRemainingNames[i])}`);
      }
      newGroupLines.push('      - DIRECT');
      return lines.slice(0, gStart).concat(newGroupLines).concat(lines.slice(gEnd)).join('\n');
    }

    // Parse and rebuild proxy-groups blocks cleanly to align with clash-verge-rev seq.rs:
    // remove deleted nodes from all groups and prepend addedNames into the first select/selector group.
    const rawLines: string[] = sectionText.split(/\r?\n/);
    const expanded: string[] = [];
    for (let i: number = 0; i < rawLines.length; i++) {
      const clean: string = ProxyChainConfig.stripComment(rawLines[i]);
      if (/^proxy-groups\s*:\s*\[/.test(clean) && clean.trim().endsWith(']')) {
        const colon: number = clean.indexOf(':');
        expanded.push(clean.substring(0, colon + 1));
        const inner: string = clean.substring(colon + 1).trim();
        const items: string[] = ProxyChainConfig.splitFlow(inner.substring(1, inner.length - 1));
        for (let j: number = 0; j < items.length; j++) {
          expanded.push('  - ' + items[j]);
        }
      } else {
        expanded.push(rawLines[i]);
      }
    }

    const outSection: string[] = ['proxy-groups:'];
    let i: number = 1;
    let injectedFirstSelector: boolean = false;
    while (i < expanded.length) {
      const line: string = expanded[i];
      const trimmed: string = line.trim();
      if (trimmed.length === 0) {
        outSection.push(line);
        i++;
        continue;
      }
      if (/^\s*-\s/.test(line)) {
        const blk: string[] = [line];
        const blkIndent: number = line.search(/\S/);
        i++;
        while (i < expanded.length && !(/^\s*-\s/.test(expanded[i]) && expanded[i].search(/\S/) <= blkIndent)) {
          blk.push(expanded[i]);
          i++;
        }
        const rebuilt: string[] = ClashUriParser.updateSingleGroupBlock(
          blk, blkIndent, addedNames, deleteSet, !injectedFirstSelector
        );
        if (rebuilt.length > 0 && rebuilt[0] === '__INJECTED__') {
          injectedFirstSelector = true;
          for (let r: number = 1; r < rebuilt.length; r++) {
            outSection.push(rebuilt[r]);
          }
        } else {
          for (let r: number = 0; r < rebuilt.length; r++) {
            outSection.push(rebuilt[r]);
          }
        }
      } else {
        outSection.push(line);
        i++;
      }
    }
    return lines.slice(0, gStart).concat(outSection).concat(lines.slice(gEnd)).join('\n');
  }

  private static updateSingleGroupBlock(
    blk: string[],
    blkIndent: number,
    addedNames: string[],
    deleteSet: Set<string>,
    tryInjectSelector: boolean
  ): string[] {
    const firstTrimmed: string = blk[0].trim().substring(1).trim();
    if (firstTrimmed.startsWith('{')) {
      const joined: string = blk.map((l: string): string => ProxyChainConfig.stripComment(l)).join(' ').trim();
      const mapStr: string = joined.substring(1).trim();
      if (mapStr.startsWith('{') && mapStr.endsWith('}')) {
        const fields: string[] = ProxyChainConfig.splitFlow(mapStr.substring(1, mapStr.length - 1));
        let gType: string = '';
        for (let i: number = 0; i < fields.length; i++) {
          const f: LexiYamlField = ProxyChainConfig.field(fields[i]);
          if (f.key === 'type') {
            gType = ProxyChainConfig.scalar(f.rawValue).toLowerCase();
          }
        }
        const isSel: boolean = gType === 'select' || gType === 'selector';
        const doInject: boolean = tryInjectSelector && isSel && addedNames.length > 0;
        const rebuiltFields: string[] = [];
        for (let i: number = 0; i < fields.length; i++) {
          const f: LexiYamlField = ProxyChainConfig.field(fields[i]);
          if (f.key === 'proxies' && f.rawValue.trim().startsWith('[') && f.rawValue.trim().endsWith(']')) {
            const rawArr: string = f.rawValue.trim();
            const members: string[] = ProxyChainConfig.splitFlow(rawArr.substring(1, rawArr.length - 1))
              .map((m: string): string => ProxyChainConfig.scalar(m))
              .filter((m: string): boolean => m.length > 0 && !deleteSet.has(m));
            const merged: string[] = [];
            const seen: Set<string> = new Set<string>();
            if (doInject) {
              for (let a: number = 0; a < addedNames.length; a++) {
                if (!seen.has(addedNames[a])) { seen.add(addedNames[a]); merged.push(addedNames[a]); }
              }
            }
            for (let m: number = 0; m < members.length; m++) {
              if (!seen.has(members[m])) { seen.add(members[m]); merged.push(members[m]); }
            }
            rebuiltFields.push(`proxies: [${merged.map((s: string): string => JSON.stringify(s)).join(', ')}]`);
          } else {
            rebuiltFields.push(fields[i]);
          }
        }
        const padStr: string = ' '.repeat(Math.max(0, blkIndent));
        const resLine: string = `${padStr}- {${rebuiltFields.join(', ')}}`;
        return doInject ? ['__INJECTED__', resLine] : [resLine];
      }
    }

    let groupType: string = '';
    for (let i: number = 0; i < blk.length; i++) {
      const entry: string = i === 0 ? blk[0].trim().substring(1).trim() : blk[i].trim();
      const f: LexiYamlField = ProxyChainConfig.field(entry);
      if (f.key === 'type') {
        groupType = ProxyChainConfig.scalar(f.rawValue).toLowerCase();
      }
    }
    const isSelector: boolean = groupType === 'select' || groupType === 'selector';
    const shouldInject: boolean = tryInjectSelector && isSelector && addedNames.length > 0;

    const out: string[] = [];
    if (shouldInject) {
      out.push('__INJECTED__');
    }

    let k: number = 0;
    while (k < blk.length) {
      const cur: string = blk[k];
      const curTrimmed: string = cur.trim();
      const curIndent: number = cur.search(/\S/);
      const fieldText: string = k === 0 ? curTrimmed.substring(1).trim() : curTrimmed;
      const f: LexiYamlField = ProxyChainConfig.field(fieldText);
      if ((k === 0 || curIndent === blkIndent + 2) && f.key === 'proxies') {
        const inline: string = ProxyChainConfig.stripComment(f.rawValue).trim();
        const existingMembers: string[] = [];
        let memberIndent: string = ' '.repeat(blkIndent + 4);
        if (inline.startsWith('[') && inline.endsWith(']')) {
          const items: string[] = ProxyChainConfig.splitFlow(inline.substring(1, inline.length - 1));
          for (let m: number = 0; m < items.length; m++) {
            const val: string = ProxyChainConfig.scalar(items[m]);
            if (val.length > 0 && !deleteSet.has(val)) {
              existingMembers.push(val);
            }
          }
          out.push(cur.substring(0, cur.indexOf('proxies:') + 8));
          k++;
        } else {
          out.push(cur);
          k++;
          while (k < blk.length) {
            const mLine: string = blk[k];
            const mTrim: string = ProxyChainConfig.stripComment(mLine).trim();
            if (mTrim.length === 0) {
              k++;
              continue;
            }
            const mIndent: number = mLine.search(/\S/);
            if (mTrim.startsWith('-') && mIndent >= blkIndent + 2) {
              memberIndent = mLine.substring(0, mIndent);
              const val: string = ProxyChainConfig.scalar(mTrim.substring(1).trim());
              if (val.length > 0 && !deleteSet.has(val)) {
                existingMembers.push(val);
              }
              k++;
            } else {
              break;
            }
          }
        }

        const mergedMembers: string[] = [];
        const seen: Set<string> = new Set<string>();
        if (shouldInject) {
          for (let a: number = 0; a < addedNames.length; a++) {
            if (!seen.has(addedNames[a])) {
              seen.add(addedNames[a]);
              mergedMembers.push(addedNames[a]);
            }
          }
        }
        for (let m: number = 0; m < existingMembers.length; m++) {
          if (!seen.has(existingMembers[m])) {
            seen.add(existingMembers[m]);
            mergedMembers.push(existingMembers[m]);
          }
        }
        for (let m: number = 0; m < mergedMembers.length; m++) {
          out.push(`${memberIndent}- ${JSON.stringify(mergedMembers[m])}`);
        }
        continue;
      }
      out.push(cur);
      k++;
    }
    return out;
  }

  static applyProxiesSequenceEdit(
    profileYaml: string,
    prepend: ClashProxyEntry[],
    append: ClashProxyEntry[],
    deleteNames: string[]
  ): ClashSeqEditResult {
    try {
      const normalizedYaml: string = ClashUriParser.repairBrokenProxiesIndent(profileYaml).replace(/^\uFEFF/, '');
      const existingItems: ClashProfileProxyItem[] = ClashUriParser.listProfileProxyBlocks(normalizedYaml);
      const targetIndentNum: number = existingItems.length > 0 ? Math.max(0, existingItems[0].indent) : 2;
      const targetIndentStr: string = ' '.repeat(targetIndentNum);
      const deleteSet: Set<string> = new Set<string>(deleteNames);

      const keptBlocks: string[] = [];
      const usedNames: Set<string> = new Set<string>();
      const allRemainingNames: string[] = [];
      let removedCount: number = 0;

      for (let i: number = 0; i < existingItems.length; i++) {
        const item: ClashProfileProxyItem = existingItems[i];
        if (deleteSet.has(item.name)) {
          removedCount++;
          continue;
        }
        usedNames.add(item.name);
        allRemainingNames.push(item.name);
        keptBlocks.push(item.rawBlockLines.join('\n'));
      }

      const finalPrepend: ClashProxyEntry[] = ClashUriParser.deduplicateAddedEntries(prepend, usedNames);
      const finalAppend: ClashProxyEntry[] = ClashUriParser.deduplicateAddedEntries(append, usedNames);
      const addedNames: string[] = [];
      const finalNamesOrder: string[] = [];

      const outProxyBlocks: string[] = ['proxies:'];
      for (let i: number = 0; i < finalPrepend.length; i++) {
        addedNames.push(finalPrepend[i].name);
        finalNamesOrder.push(finalPrepend[i].name);
        outProxyBlocks.push(ClashUriParser.serializeProxyEntryYaml(finalPrepend[i], targetIndentStr));
      }
      for (let i: number = 0; i < keptBlocks.length; i++) {
        outProxyBlocks.push(keptBlocks[i]);
        finalNamesOrder.push(allRemainingNames[i]);
      }
      for (let i: number = 0; i < finalAppend.length; i++) {
        addedNames.push(finalAppend[i].name);
        finalNamesOrder.push(finalAppend[i].name);
        outProxyBlocks.push(ClashUriParser.serializeProxyEntryYaml(finalAppend[i], targetIndentStr));
      }

      if (outProxyBlocks.length === 1) {
        outProxyBlocks[0] = 'proxies: []';
      }

      const lines: string[] = normalizedYaml.split(/\r?\n/);
      const bounds: number[] = ClashUriParser.extractSectionLines(lines, 'proxies');
      let updatedYaml: string;
      if (bounds[0] >= 0) {
        updatedYaml = lines.slice(0, bounds[0]).concat(outProxyBlocks).concat(lines.slice(bounds[1])).join('\n');
      } else {
        const groupBounds: number[] = ClashUriParser.extractSectionLines(lines, 'proxy-groups');
        const insertAt: number = groupBounds[0] >= 0 ? groupBounds[0] : lines.length;
        updatedYaml = lines.slice(0, insertAt).concat(outProxyBlocks).concat(lines.slice(insertAt)).join('\n');
      }

      updatedYaml = ClashUriParser.updateProxyGroupsSection(updatedYaml, addedNames, deleteSet, finalNamesOrder);
      return {
        yamlContent: updatedYaml,
        errorMessage: '',
        addedCount: addedNames.length,
        removedCount: removedCount
      };
    } catch (err) {
      return {
        yamlContent: '',
        errorMessage: (err as Error).message,
        addedCount: 0,
        removedCount: 0
      };
    }
  }
}

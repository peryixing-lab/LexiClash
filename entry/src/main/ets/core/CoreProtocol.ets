// CoreProtocol.ets — Mirrors FlClash core/protocol.go wire protocol & domain models

export class CoreMethodNames {
  static readonly CORE_INIT: string = 'core.init';
  static readonly CORE_INITIALIZED: string = 'core.initialized';
  static readonly CORE_GC: string = 'core.gc';
  static readonly CORE_MEMORY: string = 'core.memory';
  static readonly CORE_CRASH: string = 'core.crash';

  static readonly CONFIG_SETUP: string = 'config.setup';
  static readonly CONFIG_UPDATE: string = 'config.update';
  static readonly CONFIG_VALIDATE: string = 'config.validate';
  static readonly CONFIG_READ: string = 'config.read';

  static readonly PROFILE_BASE: string = 'profile.base';
  static readonly PROFILE_OUTBOUNDS: string = 'profile.outbounds';
  static readonly PROFILE_BUILD: string = 'profile.build';

  static readonly PROXY_LIST: string = 'proxy.list';
  static readonly PROXY_SELECT: string = 'proxy.select';
  static readonly PROXY_TEST_DELAY: string = 'proxy.testDelay';

  static readonly PROVIDER_LIST: string = 'provider.list';
  static readonly PROVIDER_UPDATE: string = 'provider.update';
  static readonly GEO_UPDATE: string = 'geo.update';

  static readonly TRAFFIC_CURRENT: string = 'traffic.current';
  static readonly TRAFFIC_TOTAL: string = 'traffic.total';
  static readonly TRAFFIC_RESET: string = 'traffic.reset';

  static readonly CONNECTION_LIST: string = 'connection.list';
  static readonly CONNECTION_COUNT: string = 'connection.count';
  static readonly CONNECTION_CLOSE: string = 'connection.close';
  static readonly CONNECTION_CLOSE_ALL: string = 'connection.closeAll';
  static readonly CONNECTION_RESET: string = 'connection.reset';

  static readonly DNS_CLEAR_CACHE: string = 'dns.clearCache';
  static readonly LOG_START: string = 'log.start';
  static readonly LOG_STOP: string = 'log.stop';
  static readonly LISTENER_START: string = 'listener.start';
  static readonly LISTENER_STOP: string = 'listener.stop';
  static readonly ROUTE_WATCH: string = 'route.watch';
  static readonly ROUTE_CHECK: string = 'route.check';

  static readonly PROBE_OUTBOUND_IP: string = 'probe.outboundIp';
  static readonly PROBE_SERVICES: string = 'probe.services';
}

export type OutboundModeType = 'rule' | 'global' | 'direct';
export type CoreStatusType = 'connected' | 'connecting' | 'disconnected';
export type ProxyGroupKind = 'Selector' | 'URLTest' | 'Fallback' | 'LoadBalance';
export type ProxiesViewStyle = 'tab' | 'list';
export type ProxiesSortKind = 'none' | 'delay' | 'name';
export type ProxiesLayoutDensity = 'tight' | 'standard' | 'loose';
export type ProxyCardSizeKind = 'expand' | 'shrink' | 'min';
export type ProfileSourceKind = 'url' | 'file' | 'custom';
export type ThemeModeKind = 'auto' | 'light' | 'dark';
export type ColorStyleKind = 'vivid' | 'tinted' | 'soft' | 'monochrome';
export type NavBarStyleKind = 'floating' | 'docked';
export type DashboardFeedKind = 'connections' | 'requests' | 'dns';
export type LexiMonitorTab = 'connections' | 'requests' | 'dns' | 'logs' | 'resources';
export type LogLevelKind = 'info' | 'warning' | 'error' | 'debug';

export interface CoreMethodEnvelope {
  id: string;
  method: string;
  argumentsJson: string;
}

export interface CoreResponseEnvelope {
  id: string;
  resultJson: string;
  errorMsg: string;
}

export interface TrafficSample {
  up: number;
  down: number;
  timestamp: number;
}

export interface CoreMemorySnapshot {
  appBytes: number;
  coreRssBytes: number;
  heapInuseBytes: number;
  heapIdleBytes: number;
  stackInuseBytes: number;
  runtimeOtherBytes: number;
}

export interface OutboundIpModel {
  ip: string;
  countryCode: string;
  countryName: string;
  ipType: string; // 'Residential' | 'DataCenter' | 'Business'
  qualityLevel: 'good' | 'normal' | 'risky';
  qualityScore: number;
  organization: string;
  asn: string;
  timezone: string;
}

export interface ServiceProbeItem {
  id: string;
  name: string;
  iconName: string; // resource media name e.g. 'google', 'github', 'openai'
  url: string;
  status: 'available' | 'restricted' | 'unavailable' | 'checking';
  delayMs: number;
  regionCode: string;
  enabled: boolean;
}

export interface ProxyNodeItem {
  id: string;
  name: string;
  protocol: string; // 'Trojan' | 'VLess' | 'VMess' | 'Hysteria2' | 'Shadowsocks' | 'TUIC' | 'Direct'
  regionCode: string;
  server: string;
  port: number;
  udp: boolean;
  delayMs: number; // -1 timeout, 0 untested, >0 ms
  isTesting: boolean;
  providerName: string;
}

export interface ProxyGroupItem {
  id: string;
  name: string;
  groupType: ProxyGroupKind;
  iconText: string;
  selectedName: string;
  fixedName: string;
  testUrl: string;
  isTestingGroup: boolean;
  nodeNames: string[];
  hidden: boolean;
}

export interface ProfileSubscriptionModel {
  id: string;
  label: string;
  sourceType: ProfileSourceKind;
  url: string;
  usedUploadBytes: number;
  usedDownloadBytes: number;
  totalBytes: number;
  expireTimestamp: number; // unix seconds
  lastUpdatedText: string;
  autoUpdate: boolean;
  autoUpdateIntervalMinutes: number;
  isUpdating: boolean;
  groupsCount: number;
  proxiesCount: number;
  rulesCount: number;
  yamlContent: string;
}

export interface TrackerRecordItem {
  id: string;
  sourceProcess: string;
  sourceIconLetter: string;
  targetHost: string;
  destinationIp: string;
  network: 'TCP' | 'UDP';
  ruleName: string;
  rulePayload: string;
  exitNodeName: string;
  exitRegionCode: string;
  downloadBytes: number;
  uploadBytes: number;
  downloadSpeed: number;
  uploadSpeed: number;
  startTimeText: string;
  durationSeconds: number;
  asnInfo: string;
  proxyChain: string[];
  isActive: boolean;
}

export interface DnsQueryRecordItem {
  id: string;
  domain: string;
  qtype: 'A' | 'AAAA' | 'HTTPS' | 'CNAME';
  answerText: string;
  upstreamServer: string;
  durationMs: number;
  cacheHit: boolean;
  initiator: 'app' | 'rule' | 'proxy' | 'direct';
  timeText: string;
}

export interface CoreLogRecordItem {
  id: string;
  timeText: string;
  level: LogLevelKind;
  tag: string;
  sourceText: string;
  payloadText: string;
}

export interface ExternalResourceItem {
  id: string;
  name: string;
  category: 'GeoData' | 'RuleProvider' | 'ProxyProvider';
  vehicleType: 'HTTP' | 'File' | 'Inline';
  behaviorText: string;
  entriesCount: number;
  sizeText: string;
  updatedAtText: string;
  url: string;
  isUpdating: boolean;
}

export interface AppAccessItem {
  bundleName: string;
  appName: string;
  iconLetter: string;
  iconBgColor: string;
  isSystemApp: boolean;
  isSelected: boolean;
}

export interface OverrideRuleItem {
  id: string;
  ruleType: string; // 'DOMAIN-SUFFIX' | 'DOMAIN-KEYWORD' | 'IP-CIDR' | 'PROCESS-NAME' | 'GEOIP' | 'MATCH'
  payload: string;
  targetGroup: string;
  noResolve: boolean;
  enabled: boolean;
}

export interface DashboardWidgetConfigItem {
  id: string;
  titleKey: string;
  descKey: string;
  enabled: boolean;
  removable: boolean;
  desktopOnly: boolean;
}

export interface LexiProxyChainDraft {
  profileId: string;
  targetGroup: string;
  nodeNames: string[];
}

export interface LexiSavedProxySelection {
  profileId: string;
  groupName: string;
  nodeName: string;
}

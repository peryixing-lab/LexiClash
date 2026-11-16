// ThemeManager.ets — FlClash prism_ui Surface Levels, Seeded Color Scheme & I18n Engine

import { ColorStyleKind, ThemeModeKind } from '../core/CoreProtocol';

export interface SeedPresetItem {
  id: string;
  nameZh: string;
  nameEn: string;
  lightHex: string;
  darkHex: string;
  softHex: string;
  tintPageLight: string;
  tintCardLight: string;
  tintPageDark: string;
  tintCardDark: string;
}

export interface FlClashColorPalette {
  isDark: boolean;
  page: string;
  card: string;
  block: string; // tone
  inset: string; // tone2
  floating: string;
  chrome: string;
  divider: string;
  onSurface: string;
  onSurfaceVariant: string;
  primary: string;
  onPrimary: string;
  primarySoft: string; // 14% alpha blend for badges/decorations
  series2: string; // 45% primary over card for upload chart / core memory
  ok: string;
  okContainer: string;
  onOkContainer: string;
  warn: string;
  warnContainer: string;
  onWarnContainer: string;
  error: string;
  errorContainer: string;
  onErrorContainer: string;
}

export class ThemeManager {
  static readonly SEED_PRESETS: SeedPresetItem[] = [
    {
      id: 'blue',
      nameZh: '经典蓝',
      nameEn: 'Ocean Blue',
      lightHex: '#007AFF',
      darkHex: '#2E90FF',
      softHex: '#4A78B8',
      tintPageLight: '#EDF2F9',
      tintCardLight: '#F8FAFD',
      tintPageDark: '#0D1118',
      tintCardDark: '#1E2430'
    },
    {
      id: 'amber',
      nameZh: '琥珀橙',
      nameEn: 'Sunset Amber',
      lightHex: '#D97724',
      darkHex: '#DF8E3D',
      softHex: '#B57B4C',
      tintPageLight: '#F7F1EB',
      tintCardLight: '#FDFBF8',
      tintPageDark: '#14110D',
      tintCardDark: '#28231D'
    },
    {
      id: 'emerald',
      nameZh: '翡翠绿',
      nameEn: 'Emerald Green',
      lightHex: '#1F9D55',
      darkHex: '#34C759',
      softHex: '#4D946B',
      tintPageLight: '#ECF6F0',
      tintCardLight: '#F8FCF9',
      tintPageDark: '#0C1410',
      tintCardDark: '#1C2921'
    },
    {
      id: 'rose',
      nameZh: '珊瑚粉',
      nameEn: 'Coral Rose',
      lightHex: '#E11D48',
      darkHex: '#FB7185',
      softHex: '#B8566D',
      tintPageLight: '#F9EEF1',
      tintCardLight: '#FDF8FA',
      tintPageDark: '#160E11',
      tintCardDark: '#2B1E22'
    },
    {
      id: 'indigo',
      nameZh: '极光紫',
      nameEn: 'Indigo Violet',
      lightHex: '#5856D6',
      darkHex: '#7D7AFF',
      softHex: '#6E6DB8',
      tintPageLight: '#F0EFF9',
      tintCardLight: '#F9F9FD',
      tintPageDark: '#100F18',
      tintCardDark: '#222030'
    },
    {
      id: 'cyan',
      nameZh: '冰川青',
      nameEn: 'Glacier Cyan',
      lightHex: '#0284C7',
      darkHex: '#38BDF8',
      softHex: '#4B8CAD',
      tintPageLight: '#ECF5F9',
      tintCardLight: '#F7FBFD',
      tintPageDark: '#0C1317',
      tintCardDark: '#1C272E'
    }
  ];

  static resolvePalette(
    themeMode: ThemeModeKind,
    seedId: string,
    colorStyle: ColorStyleKind,
    pureBlack: boolean
  ): FlClashColorPalette {
    // Default to dark on mobile / auto if dark selected, or light if light
    const isDark: boolean = themeMode === 'dark';
    let preset: SeedPresetItem = ThemeManager.SEED_PRESETS[0];
    for (let i = 0; i < ThemeManager.SEED_PRESETS.length; i++) {
      if (ThemeManager.SEED_PRESETS[i].id === seedId) {
        preset = ThemeManager.SEED_PRESETS[i];
        break;
      }
    }

    let primaryColor: string = isDark ? preset.darkHex : preset.lightHex;
    let onPrimaryColor: string = '#FFFFFF';
    if (colorStyle === 'soft') {
      primaryColor = preset.softHex;
    } else if (colorStyle === 'monochrome') {
      primaryColor = isDark ? '#F2F2F7' : '#1C1C1E';
      onPrimaryColor = isDark ? '#1C1C1E' : '#FFFFFF';
    }

    let pageBg: string = isDark ? (pureBlack ? '#000000' : '#0F0F12') : '#F0F0F5';
    let cardBg: string = isDark ? (pureBlack ? '#16161A' : '#222227') : '#FAFAFC';
    let blockBg: string = isDark ? (pureBlack ? '#242429' : '#2F2F36') : '#EFEFF4';
    let insetBg: string = isDark ? (pureBlack ? '#323238' : '#3C3C44') : '#E4E4EB';
    let floatingBg: string = isDark ? '#2D2D34' : '#FFFFFF';
    let chromeBg: string = isDark ? '#18181C' : '#E6E6ED';

    if (colorStyle === 'tinted') {
      pageBg = isDark ? (pureBlack ? '#000000' : preset.tintPageDark) : preset.tintPageLight;
      cardBg = isDark ? preset.tintCardDark : preset.tintCardLight;
    }

    return {
      isDark: isDark,
      page: pageBg,
      card: cardBg,
      block: blockBg,
      inset: insetBg,
      floating: floatingBg,
      chrome: chromeBg,
      divider: isDark ? '#24FFFFFF' : '#1F000000',
      onSurface: isDark ? '#F5F5F7' : '#1C1C1E',
      onSurfaceVariant: isDark ? '#9898A0' : '#6C6C74',
      primary: primaryColor,
      onPrimary: onPrimaryColor,
      primarySoft: isDark ? ('#28' + primaryColor.substring(1)) : ('#1E' + primaryColor.substring(1)),
      series2: isDark ? ('#73' + primaryColor.substring(1)) : ('#66' + primaryColor.substring(1)),
      ok: isDark ? '#4ADE80' : '#16A34A',
      okContainer: isDark ? '#173B26' : '#DCFCE7',
      onOkContainer: isDark ? '#6EE7B7' : '#15803D',
      warn: isDark ? '#FBBF24' : '#D97706',
      warnContainer: isDark ? '#3D2B11' : '#FEF3C7',
      onWarnContainer: isDark ? '#FCD34D' : '#B45309',
      error: isDark ? '#F87171' : '#DC2626',
      errorContainer: isDark ? '#3F1A1A' : '#FEE2E2',
      onErrorContainer: isDark ? '#FCA5A5' : '#B91C1C'
    };
  }

  static delayColor(delayMs: number, palette: FlClashColorPalette): string {
    if (delayMs < 0) {
      return palette.error;
    }
    if (delayMs === 0) {
      return palette.onSurfaceVariant;
    }
    if (delayMs < 260) {
      return palette.ok;
    }
    if (delayMs < 600) {
      return palette.primary;
    }
    return palette.warn;
  }

  static formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let val: number = bytes;
    let idx: number = 0;
    while (val >= 1024 && idx < units.length - 1) {
      val = val / 1024;
      idx++;
    }
    if (idx === 0) {
      return `${Math.round(val)} B`;
    }
    return `${val.toFixed(1)} ${units[idx]}`;
  }

  static formatSpeedValueAndUnit(bytesPerSec: number): string[] {
    if (bytesPerSec <= 0) {
      return ['0.0', 'KB/s'];
    }
    const kb: number = bytesPerSec / 1024;
    if (kb < 1000) {
      return [kb.toFixed(1), 'KB/s'];
    }
    const mb: number = kb / 1024;
    return [mb.toFixed(1), 'MB/s'];
  }

  static formatDurationHMS(totalSeconds: number): string {
    const hrs: number = Math.floor(totalSeconds / 3600);
    const mins: number = Math.floor((totalSeconds % 3600) / 60);
    const secs: number = Math.floor(totalSeconds % 60);
    const hStr: string = hrs < 10 ? `0${hrs}` : `${hrs}`;
    const mStr: string = mins < 10 ? `0${mins}` : `${mins}`;
    const sStr: string = secs < 10 ? `0${secs}` : `${secs}`;
    return `${hStr}:${mStr}:${sStr}`;
  }

  static countryFlagEmoji(countryCode: string, countryName: string = ''): string {
    const code: string = countryCode.trim().toUpperCase();
    const nameLower: string = countryName.trim().toLowerCase();
    if (
      code === 'TW' ||
      code === 'TWN' ||
      nameLower.includes('taiwan') ||
      countryName.includes('台湾') ||
      countryName.includes('台灣')
    ) {
      return '\uD83C\uDDE8\uD83C\uDDF3';
    }
    if (code.length === 2) {
      const c1: number = code.charCodeAt(0);
      const c2: number = code.charCodeAt(1);
      if (c1 >= 65 && c1 <= 90 && c2 >= 65 && c2 <= 90) {
        return '\uD83C' + String.fromCharCode(0xDDE6 + (c1 - 65)) +
          '\uD83C' + String.fromCharCode(0xDDE6 + (c2 - 65));
      }
    }
    return '';
  }

  static countryDisplayName(countryCode: string, countryName: string = '', lang: string = 'zh_CN'): string {
    const code: string = countryCode.trim().toUpperCase();
    const rawName: string = countryName.trim();
    const nameLower: string = rawName.toLowerCase();
    const isEn: boolean = lang === 'en_US';
    if (
      code === 'TW' ||
      code === 'TWN' ||
      nameLower.includes('taiwan') ||
      rawName.includes('台湾') ||
      rawName.includes('台灣')
    ) {
      return isEn ? 'Taiwan, China' : '中国台湾';
    }
    const zhMap: Record<string, string> = {
      'CN': '中国',
      'HK': '中国香港',
      'MO': '中国澳门',
      'SG': '新加坡',
      'JP': '日本',
      'KR': '韩国',
      'US': '美国',
      'GB': '英国',
      'UK': '英国',
      'DE': '德国',
      'FR': '法国',
      'NL': '荷兰',
      'CA': '加拿大',
      'AU': '澳大利亚',
      'RU': '俄罗斯',
      'IN': '印度',
      'MY': '马来西亚',
      'TH': '泰国',
      'VN': '越南',
      'PH': '菲律宾',
      'ID': '印度尼西亚',
      'TR': '土耳其',
      'IT': '意大利',
      'ES': '西班牙',
      'BR': '巴西',
      'CH': '瑞士',
      'SE': '瑞典',
      'AE': '阿联酋'
    };
    const enMap: Record<string, string> = {
      'CN': 'China',
      'HK': 'Hong Kong',
      'MO': 'Macao',
      'SG': 'Singapore',
      'JP': 'Japan',
      'KR': 'South Korea',
      'US': 'United States',
      'GB': 'United Kingdom',
      'UK': 'United Kingdom',
      'DE': 'Germany',
      'FR': 'France',
      'NL': 'Netherlands',
      'CA': 'Canada',
      'AU': 'Australia',
      'RU': 'Russia',
      'IN': 'India',
      'MY': 'Malaysia',
      'TH': 'Thailand',
      'VN': 'Vietnam',
      'PH': 'Philippines',
      'ID': 'Indonesia',
      'TR': 'Turkey',
      'IT': 'Italy',
      'ES': 'Spain',
      'BR': 'Brazil',
      'CH': 'Switzerland',
      'SE': 'Sweden',
      'AE': 'UAE'
    };
    const mapped: string | undefined = isEn ? enMap[code] : zhMap[code];
    if (mapped !== undefined && mapped.length > 0) {
      return mapped;
    }
    return rawName.length > 0 ? rawName : code;
  }

  static formatIpTypeLabel(ipType: string, lang: string): string {
    if (ipType === 'Residential') return I18n.t('residential', lang);
    if (ipType === 'DataCenter') return I18n.t('dataCenter', lang);
    if (ipType === 'Mobile') return I18n.t('mobileNetwork', lang);
    if (ipType === 'Business') return I18n.t('businessNetwork', lang);
    return I18n.t('ipTypeUnknown', lang);
  }

  static formatIpQualityLabel(qualityLevel: string, lang: string): string {
    if (qualityLevel === 'good') return I18n.t('qualityGood', lang);
    if (qualityLevel === 'risky') return I18n.t('qualityRisky', lang);
    return I18n.t('qualityNormal', lang);
  }

  static ipQualityTextColor(qualityLevel: string, palette: FlClashColorPalette): string {
    if (qualityLevel === 'good') return palette.onOkContainer;
    if (qualityLevel === 'risky') return palette.onWarnContainer;
    return palette.onSurfaceVariant;
  }

  static ipQualityBgColor(qualityLevel: string, palette: FlClashColorPalette): string {
    if (qualityLevel === 'good') return palette.okContainer;
    if (qualityLevel === 'risky') return palette.warnContainer;
    return palette.block;
  }
}

export class I18n {
  static t(key: string, lang: string): string {
    const isEn: boolean = lang === 'en_US';
    if (key === 'dashboard') return isEn ? 'Dashboard' : '仪表盘';
    if (key === 'editDashboard') return isEn ? 'Edit Dashboard' : '编辑仪表盘';
    if (key === 'proxies') return isEn ? 'Proxies' : '代理';
    if (key === 'profiles') return isEn ? 'Profiles' : '配置';
    if (key === 'profile') return isEn ? 'Profile' : '配置';
    if (key === 'liveConnections') return isEn ? 'Live connections' : '实时连接';
    if (key === 'recentRequests') return isEn ? 'Recent requests' : '最近请求';
    if (key === 'dnsQueries') return isEn ? 'DNS queries' : 'DNS 查询';
    if (key === 'logs') return isEn ? 'Logs' : '日志';
    if (key === 'resources') return isEn ? 'Resources' : '外部资源';
    if (key === 'tools') return isEn ? 'Tools' : '工具';
    if (key === 'status') return isEn ? 'Status' : '状态';
    if (key === 'running') return isEn ? 'Running' : '运行中';
    if (key === 'stopped') return isEn ? 'Stopped' : '未运行';
    if (key === 'runTime') return isEn ? 'Run time' : '运行时长';
    if (key === 'organization') return isEn ? 'Organization' : '所属机构';
    if (key === 'residential') return isEn ? 'Residential' : '住宅宽带';
    if (key === 'dataCenter') return isEn ? 'DataCenter' : '数据中心';
    if (key === 'mobileNetwork') return isEn ? 'Mobile' : '移动网络';
    if (key === 'businessNetwork') return isEn ? 'Business' : '企业专线';
    if (key === 'ipTypeUnknown') return isEn ? 'Unknown Type' : '未知类型';
    if (key === 'qualityGood') return isEn ? 'Quality Good' : '质量优';
    if (key === 'qualityNormal') return isEn ? 'Standard' : '常规线路';
    if (key === 'qualityRisky') return isEn ? 'Risky' : '高风险';
    if (key === 'networkSpeed') return isEn ? 'Network speed' : '网络速度';
    if (key === 'upload') return isEn ? 'Upload' : '上传';
    if (key === 'download') return isEn ? 'Download' : '下载';
    if (key === 'peak') return isEn ? 'Peak' : '峰值';
    if (key === 'total') return isEn ? 'Total' : '总计';
    if (key === 'outboundMode') return isEn ? 'Outbound mode' : '出站模式';
    if (key === 'rule') return isEn ? 'Rule' : '规则';
    if (key === 'global') return isEn ? 'Global' : '全局';
    if (key === 'direct') return isEn ? 'Direct' : '直连';
    if (key === 'systemProxy') return isEn ? 'System proxy' : '系统代理';
    if (key === 'tun') return isEn ? 'TUN' : '虚拟网卡';
    if (key === 'intranetIp') return isEn ? 'Intranet IP' : '内网 IP';
    if (key === 'allowLan') return isEn ? 'Allow LAN' : '局域网代理';
    if (key === 'enabled') return isEn ? 'Enabled' : '已开启';
    if (key === 'disabled') return isEn ? 'Disabled' : '已关闭';
    if (key === 'daysLeft') return isEn ? 'days left' : '天后到期';
    if (key === 'used') return isEn ? 'used' : '已使用';
    if (key === 'serviceStatus') return isEn ? 'Service status' : '服务状态';
    if (key === 'memoryInfo') return isEn ? 'Memory info' : '内存信息';
    if (key === 'app') return isEn ? 'App' : '应用';
    if (key === 'core') return isEn ? 'Core' : '内核';
    if (key === 'proxyGroup') return isEn ? 'Proxy group' : '策略组';
    if (key === 'settings') return isEn ? 'Settings' : '设置';
    if (key === 'other') return isEn ? 'Other' : '其他';
    if (key === 'language') return isEn ? 'Language' : '语言';
    if (key === 'theme') return isEn ? 'Theme' : '主题与外观';
    if (key === 'accessControl') return isEn ? 'Access Control' : '分应用代理';
    if (key === 'backupRestore') return isEn ? 'Backup & Restore' : '备份与恢复';
    if (key === 'advancedConfig') return isEn ? 'Advanced Config' : '进阶与网络配置';
    if (key === 'general') return isEn ? 'General' : '常规设置';
    if (key === 'disclaimer') return isEn ? 'Disclaimer' : '免责声明';
    if (key === 'developerMode') return isEn ? 'Developer & NAPI Core' : '开发者与内核桥接';
    if (key === 'about') return isEn ? 'About LexiClash' : '关于 LexiClash';
    return key;
  }
}

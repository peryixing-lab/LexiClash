import type { vpnExtension } from '@kit.NetworkKit';
import type { AppAccessItem } from './CoreProtocol';

export type LexiAppAccessMode = 'whitelist' | 'blacklist';

export interface LexiAppAccessPolicy {
  enabled: boolean;
  mode: LexiAppAccessMode;
  bundleNames: string[];
}

export class AppAccessControl {
  static readonly MAX_APPS: number = 256;

  static unrestricted(): LexiAppAccessPolicy {
    return { enabled: false, mode: 'blacklist', bundleNames: [] };
  }

  static isBundleName(bundleName: string): boolean {
    return bundleName.length >= 7 && bundleName.length <= 128 &&
      /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/.test(bundleName);
  }

  static validationError(policy: LexiAppAccessPolicy): string {
    if (typeof policy.enabled !== 'boolean' ||
      (policy.mode !== 'whitelist' && policy.mode !== 'blacklist') || !Array.isArray(policy.bundleNames)) {
      return '分应用代理配置无效，请重新设置';
    }
    if (!policy.enabled) { return ''; }
    if (policy.bundleNames.length > AppAccessControl.MAX_APPS) { return '最多可选择 256 个应用'; }
    for (let i: number = 0; i < policy.bundleNames.length; i++) {
      if (typeof policy.bundleNames[i] !== 'string' || !AppAccessControl.isBundleName(policy.bundleNames[i])) {
        return '应用包名格式不正确，请检查分应用代理列表';
      }
    }
    // An empty system allowlist means unrestricted capture, not "capture nothing".
    if (policy.mode === 'whitelist' && policy.bundleNames.length === 0) {
      return '白名单模式至少需要选中一个应用';
    }
    return '';
  }

  static fingerprint(policy: LexiAppAccessPolicy): string {
    if (!policy.enabled) { return 'disabled'; }
    return `${policy.mode}:${Array.from(new Set<string>(policy.bundleNames)).sort().join(',')}`;
  }

  static configureVpn(config: vpnExtension.VpnConfig, policy: LexiAppAccessPolicy): void {
    const error: string = AppAccessControl.validationError(policy);
    if (error.length > 0) { throw new Error(error); }
    if (!policy.enabled) { return; }
    const bundles: string[] = Array.from(new Set<string>(policy.bundleNames));
    if (policy.mode === 'whitelist') {
      config.trustedApplications = bundles;
    } else if (bundles.length > 0) {
      config.blockedApplications = bundles;
    }
  }

  static restoreEntries(saved: AppAccessItem[] | undefined): AppAccessItem[] {
    const entries: AppAccessItem[] = [];
    const seen: Set<string> = new Set<string>();
    if (!Array.isArray(saved)) { return entries; }
    for (let i: number = 0; i < saved.length && entries.length < AppAccessControl.MAX_APPS; i++) {
      const app: AppAccessItem = saved[i];
      if (!app || typeof app.bundleName !== 'string' || !AppAccessControl.isBundleName(app.bundleName) ||
        seen.has(app.bundleName)) { continue; }
      seen.add(app.bundleName);
      const appName: string = typeof app.appName === 'string' && app.appName.trim().length > 0
        ? app.appName.trim().slice(0, 64) : app.bundleName;
      entries.push({ bundleName: app.bundleName, appName: appName, isSelected: app.isSelected === true,
        iconLetter: appName.charAt(0), iconBgColor: '', isSystemApp: false });
    }
    return entries;
  }
}

export type LexiTunStack = 'system' | 'gvisor' | 'mixed';

export interface LexiTunSettings {
  stack: LexiTunStack;
  mtu: number;
}

export class TunConfig {
  static defaults(): LexiTunSettings {
    return { stack: 'system', mtu: 1400 };
  }

  static validationError(settings: LexiTunSettings): string {
    if (settings.stack !== 'system' && settings.stack !== 'gvisor' && settings.stack !== 'mixed') {
      return 'TUN 协议栈无效，请选择 System、gVisor 或 Mixed';
    }
    if (!Number.isInteger(settings.mtu) || settings.mtu < 1280 || settings.mtu > 9000) {
      return 'TUN MTU 必须是 1280–9000 之间的整数';
    }
    return '';
  }

  static fingerprint(settings: LexiTunSettings): string {
    return `${settings.stack}:${settings.mtu}`;
  }
}

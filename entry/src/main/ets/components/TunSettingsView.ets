import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';
import { LexiTunStack } from '../core/TunConfig';
import { AppStateStore } from '../store/AppStateStore';

@Component
export struct TunSettingsView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop @Watch('syncSettings') revisionTick: number = 0;
  @State active: boolean = false;
  @State busy: boolean = false;
  @State connecting: boolean = false;
  @State selectedStack: LexiTunStack = 'system';
  @State mtuInput: string = '1400';
  @State mtuError: string = '';
  @State pendingChanges: boolean = false;
  @State activeSummary: string = '';
  @State english: boolean = false;
  @State feedback: string = '';
  private store: AppStateStore = AppStateStore.getInstance();
  private stacks: LexiTunStack[] = ['system', 'gvisor', 'mixed'];

  aboutToAppear(): void {
    this.mtuInput = `${this.store.tunMtu}`;
    this.syncSettings();
  }

  syncSettings(): void {
    this.active = this.store.vpnEnabled;
    this.busy = this.store.isVpnTransitioning;
    this.connecting = this.store.coreStatus === 'connecting';
    this.selectedStack = this.store.tunStack;
    this.pendingChanges = this.store.hasPendingTunChanges() || this.store.hasPendingAppAccessChanges();
    this.english = this.store.localeLang === 'en_US';
    const applied = this.store.getActiveTunSettings();
    this.activeSummary = `${applied.stack} · MTU ${applied.mtu}`;
  }

  private text(zh: string, en: string): string {
    return this.english ? en : zh;
  }

  private statusText(): string {
    if (this.busy) {
      return this.connecting ? this.text('正在启动 TUN…', 'Starting TUN…') : this.text('正在关闭 TUN…', 'Stopping TUN…');
    }
    return this.active ? this.text('系统 VPN 已连接 · TUN 已启用', 'System VPN connected · TUN active')
      : this.text('系统 VPN 未连接', 'System VPN disconnected');
  }

  private changeMtu(input: string): void {
    this.mtuInput = input;
    if (!/^\d{4}$/.test(input.trim())) {
      this.mtuError = this.text('请输入 1280–9000 之间的整数', 'Enter an integer between 1280 and 9000');
      return;
    }
    this.mtuError = this.store.setTunSettings(this.store.tunStack, Number(input.trim()));
    this.feedback = '';
    this.syncSettings();
  }

  private async applySettings(): Promise<void> {
    this.feedback = '';
    const operation: Promise<boolean> = this.store.applyTunSettingsAsync();
    this.syncSettings();
    const ok: boolean = await operation;
    this.feedback = ok ? (this.active ? this.text('TUN 设置已应用', 'TUN settings applied')
      : this.text('设置已保存，下次连接 VPN 时生效', 'Saved. Applies the next VPN connection.')) : this.store.lastOperationError;
    this.syncSettings();
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text(this.text('TUN 设置', 'TUN settings'))
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
          Text(this.statusText()).fontSize(13).fontColor(this.active ? this.palette.ok : this.palette.onSurfaceVariant)
          if (this.active) {
            Text(this.activeSummary).fontSize(12).fontColor(this.palette.onSurfaceVariant)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').padding(18).backgroundColor(this.palette.card).borderRadius(22)

      Column({ space: 8 }) {
        Text(this.text('通过鸿蒙系统 VPN 创建虚拟网卡，接管 TCP、UDP 和 DNS 流量，无需为各应用手动设置 HTTP 代理。',
          'Creates a virtual network interface through the system VPN to handle TCP, UDP and DNS traffic. Apps do not need manual HTTP proxy settings.'))
          .fontSize(13).fontColor(this.palette.onSurfaceVariant)
        Text(this.text('鸿蒙系统 VPN 依赖 TUN 虚拟网卡，连接时始终启用。请在仪表盘连接或断开 VPN；分应用黑白名单决定哪些应用进入 VPN。',
          'HarmonyOS system VPN requires a TUN interface, which is always enabled when connected. Connect or disconnect from the dashboard. App routing decides which apps enter the VPN.'))
          .fontSize(12).fontColor(this.palette.onSurfaceVariant)
      }.alignItems(HorizontalAlign.Start).width('100%').padding(18)
      .backgroundColor(this.palette.card).borderRadius(22)

      Column({ space: 12 }) {
        Text(this.text('TUN 协议栈', 'TUN stack'))
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
        Row({ space: 8 }) {
          ForEach(this.stacks, (stack: LexiTunStack) => {
            Button(stack === 'gvisor' ? 'gVisor' : (stack === 'system' ? 'System' : 'Mixed'))
              .height(42).fontSize(13).layoutWeight(1).enabled(!this.busy)
              .fontColor(this.selectedStack === stack ? this.palette.onPrimary : this.palette.onSurface)
              .backgroundColor(this.selectedStack === stack ? this.palette.primary : this.palette.block)
              .onClick((): void => {
                this.feedback = this.store.setTunSettings(stack, this.store.tunMtu);
                this.syncSettings();
              })
          }, (stack: LexiTunStack): string => stack)
        }.width('100%')
        Text(this.text('默认使用 System。修改协议栈后，需要重新创建 TUN 连接。',
          'System is the default. Changing the stack requires recreating the TUN connection.'))
          .fontSize(12).fontColor(this.palette.onSurfaceVariant)
        Row({ space: 12 }) {
          Text('MTU').fontSize(15).fontColor(this.palette.onSurface).layoutWeight(1)
          TextInput({ text: this.mtuInput, placeholder: '1400' })
            .id('tun-mtu-input').width(116).height(42).type(InputType.Number).maxLength(4)
            .fontColor(this.palette.onSurface).backgroundColor(this.palette.block).enabled(!this.busy)
            .onChange((input: string): void => { this.changeMtu(input); })
        }.width('100%')
        Text(this.text('范围 1280–9000，默认 1400。系统虚拟网卡与内核使用相同 MTU。',
          'Range: 1280–9000; default: 1400. The system interface and native stack use the same MTU.'))
          .fontSize(12).fontColor(this.palette.onSurfaceVariant)
        if (this.mtuError.length > 0) {
          Text(this.mtuError).fontSize(12).fontColor(this.palette.error)
        }
        Button(this.text('恢复默认设置', 'Restore defaults'))
          .height(40).fontSize(13).fontColor(this.palette.primary).backgroundColor(this.palette.primarySoft)
          .enabled(!this.busy)
          .onClick((): void => {
            this.feedback = this.store.setTunSettings('system', 1400);
            this.mtuInput = '1400'; this.mtuError = '';
            this.syncSettings();
          })
      }.alignItems(HorizontalAlign.Start).width('100%').padding(18)
      .backgroundColor(this.palette.card).borderRadius(22)

      Text(this.active ? (this.pendingChanges
        ? this.text('存在待应用的设置。应用时会短暂断开并重连，保留当前节点和代理链。',
          'Changes are pending. Applying briefly reconnects the VPN and preserves the selected proxies and chain.')
        : this.text('当前 TUN 正在使用这些设置', 'The active TUN uses these settings.'))
        : this.text('设置自动保存，下次连接 VPN 时生效', 'Settings are saved automatically for the next TUN connection.'))
        .fontSize(12).fontColor(this.palette.onSurfaceVariant).width('100%')
      Button(this.active ? this.text('应用并重连 TUN', 'Apply and reconnect TUN') : this.text('保存设置', 'Save settings'))
        .id('tun-apply-button').height(46).width('100%')
        .fontColor(this.palette.onPrimary).backgroundColor(this.palette.primary)
        .enabled(!this.busy && this.mtuError.length === 0 && (!this.active || this.pendingChanges))
        .onClick((): void => { this.applySettings(); })
      if (this.feedback.length > 0) {
        Text(this.feedback).fontSize(13).fontColor(this.palette.onSurface).width('100%')
      }
    }.width('100%')
  }
}

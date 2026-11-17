import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';
import { LexiTunStack } from '../core/TunConfig';
import { AppStateStore } from '../store/AppStateStore';

@Component
export struct TunSettingsView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop @Watch('syncSettings') revisionTick: number = 0;
  @State active: boolean = false;
  @State tunEnabled: boolean = true;
  @State localConnected: boolean = false;
  @State proxyAddress: string = '127.0.0.1:7890';
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
    this.tunEnabled = this.store.tunEnabled;
    this.localConnected = this.store.isRunning && !this.store.vpnEnabled;
    this.proxyAddress = `127.0.0.1:${this.store.mixedPort}`;
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
    return this.active ? this.text('TUN 已连接', 'TUN is connected')
      : (this.localConnected ? this.text('本地代理已连接', 'Local proxy is connected')
        : this.text('代理未连接，模式在下次连接时生效', 'Disconnected. The mode applies on the next connection.'));
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

  private async switchTun(nextEnabled: boolean): Promise<void> {
    this.feedback = '';
    const operation: Promise<boolean> = this.store.setTunModeEnabledAsync(nextEnabled);
    this.syncSettings();
    const ok: boolean = await operation;
    if (!ok) { this.feedback = this.store.lastOperationError; }
    this.syncSettings();
  }

  private async applySettings(): Promise<void> {
    this.feedback = '';
    const operation: Promise<boolean> = this.store.applyTunSettingsAsync();
    this.syncSettings();
    const ok: boolean = await operation;
    this.feedback = ok ? (this.active ? this.text('TUN 设置已应用', 'TUN settings applied')
      : this.text('设置已保存，下次开启 TUN 时生效', 'Saved. Applies the next time TUN starts.')) : this.store.lastOperationError;
    this.syncSettings();
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text(this.text('TUN 模式', 'TUN mode'))
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
          Text(this.statusText()).fontSize(13).fontColor(this.active ? this.palette.ok : this.palette.onSurfaceVariant)
          if (this.active) {
            Text(this.activeSummary).fontSize(12).fontColor(this.palette.onSurfaceVariant)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: $$this.tunEnabled })
          .id('tun-mode-toggle').selectedColor(this.palette.primary)
          .accessibilityText(this.text('启用 TUN 模式', 'Enable TUN mode'))
          .enabled(!this.busy && !this.store.isChainConnecting && (this.tunEnabled || this.mtuError.length === 0))
          .onChange((nextEnabled: boolean): void => { this.switchTun(nextEnabled); })
      }.width('100%').padding(18).backgroundColor(this.palette.card).borderRadius(22)

      Column({ space: 8 }) {
        Text(this.text('通过鸿蒙系统 VPN 创建虚拟网卡，接管 TCP、UDP 和 DNS 流量，无需为各应用手动设置 HTTP 代理。',
          'Creates a virtual network interface through the system VPN to handle TCP, UDP and DNS traffic. Apps do not need manual HTTP proxy settings.'))
          .fontSize(13).fontColor(this.palette.onSurfaceVariant)
        Text(this.text('开启后通过系统 VPN 接管流量；关闭后仍可连接，使用本地 HTTP/SOCKS 代理。运行中切换会重连并保留节点和代理链。分应用黑白名单仅在 TUN 模式生效。',
          'When enabled, the system VPN captures traffic. When disabled, local HTTP/SOCKS proxy connections remain available. Switching reconnects while preserving proxies and the chain. App routing applies only in TUN mode.'))
          .fontSize(12).fontColor(this.palette.onSurfaceVariant)
        Text(this.text(`本地代理地址：${this.proxyAddress}。关闭 TUN 时，需要在支持代理的应用或网络设置中手动填写该地址。`,
          `Local proxy: ${this.proxyAddress}. With TUN off, configure this address in an app or network setting that supports proxies.`))
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
        : this.text('设置自动保存，下次开启 TUN 时生效', 'Settings are saved automatically for the next TUN connection.'))
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

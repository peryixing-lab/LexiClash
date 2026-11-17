import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';
import { AppAccessControl, LexiAppAccessMode } from '../core/AppAccessControl';
import { AppAccessItem } from '../core/CoreProtocol';
import { AppStateStore } from '../store/AppStateStore';

@Component
export struct AppAccessSettingsView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop @Watch('syncSettings') revisionTick: number = 0;
  @State accessEnabled: boolean = false;
  @State accessMode: LexiAppAccessMode = 'blacklist';
  @State appItems: AppAccessItem[] = [];
  @State bundleInput: string = '';
  @State nameInput: string = '';
  @State searchInput: string = '';
  @State busy: boolean = false;
  @State running: boolean = false;
  @State pendingChanges: boolean = false;
  @State validationMessage: string = '';
  @State feedback: string = '';
  @State formError: string = '';
  @State english: boolean = false;
  private store: AppStateStore = AppStateStore.getInstance();

  aboutToAppear(): void {
    this.syncSettings();
  }

  syncSettings(): void {
    this.accessEnabled = this.store.accessControlEnabled;
    this.accessMode = this.store.accessControlMode;
    this.appItems = AppAccessControl.restoreEntries(this.store.appAccessList);
    this.busy = this.store.isVpnTransitioning;
    this.running = this.store.isRunning && this.store.vpnEnabled;
    this.pendingChanges = this.store.hasPendingAppAccessChanges();
    this.validationMessage = AppAccessControl.validationError(this.store.getAppAccessPolicy());
    this.english = this.store.localeLang === 'en_US';
  }

  private text(zh: string, en: string): string {
    return this.english ? en : zh;
  }

  private changeMode(mode: LexiAppAccessMode): void {
    this.store.setAppAccessMode(mode);
    this.feedback = '';
    this.syncSettings();
  }

  private addApp(): void {
    this.formError = this.store.addAppAccessEntry(this.bundleInput, this.nameInput);
    if (this.formError.length === 0) { this.bundleInput = ''; this.nameInput = ''; this.feedback = ''; }
    this.syncSettings();
  }

  private visibleApps(): AppAccessItem[] {
    const keyword: string = this.searchInput.trim().toLowerCase();
    return this.appItems.filter((app: AppAccessItem): boolean =>
      app.appName.toLowerCase().includes(keyword) || app.bundleName.toLowerCase().includes(keyword));
  }

  private selectedCount(): number {
    return this.appItems.filter((app: AppAccessItem): boolean => app.isSelected).length;
  }

  private async applySettings(): Promise<void> {
    const wasRunning: boolean = this.running;
    this.feedback = '';
    const operation: Promise<boolean> = this.store.applyAppAccessChangesAsync();
    this.syncSettings();
    const ok: boolean = await operation;
    this.feedback = ok
      ? (wasRunning ? this.text('分应用设置已应用', 'App routing applied')
        : this.text('设置已保存，下次连接时生效', 'Saved. Applies on the next connection.'))
      : this.store.lastOperationError;
    this.syncSettings();
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.text('启用分应用代理', 'Enable app routing'))
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
          Text(this.text('关闭后，所有应用按 VPN 路由接管', 'When off, VPN routes apply to all apps.'))
            .fontSize(12).fontColor(this.palette.onSurfaceVariant)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.accessEnabled })
          .selectedColor(this.palette.primary)
          .enabled(!this.busy)
          .onChange((nextEnabled: boolean): void => {
            this.store.setAppAccessEnabled(nextEnabled);
            this.feedback = '';
            this.syncSettings();
          })
      }.width('100%').padding(16).backgroundColor(this.palette.card).borderRadius(22)

      Row({ space: 8 }) {
        Button(this.text('白名单模式', 'Allowlist'))
          .fontSize(13).height(42).layoutWeight(1)
          .fontColor(this.accessMode === 'whitelist' ? this.palette.onPrimary : this.palette.onSurface)
          .backgroundColor(this.accessMode === 'whitelist' ? this.palette.primary : this.palette.card)
          .enabled(!this.busy)
          .onClick((): void => { this.changeMode('whitelist'); })
        Button(this.text('黑名单模式', 'Bypass list'))
          .fontSize(13).height(42).layoutWeight(1)
          .fontColor(this.accessMode === 'blacklist' ? this.palette.onPrimary : this.palette.onSurface)
          .backgroundColor(this.accessMode === 'blacklist' ? this.palette.primary : this.palette.card)
          .enabled(!this.busy)
          .onClick((): void => { this.changeMode('blacklist'); })
      }.width('100%')

      Column({ space: 8 }) {
        Text(this.text('白名单：只有勾选的应用进入 VPN，其他应用直连。',
          'Allowlist: only checked apps enter the VPN; other apps connect directly.'))
          .fontSize(12).fontColor(this.palette.onSurfaceVariant)
        Text(this.text('黑名单：勾选的应用直连，其余应用进入 VPN。',
          'Bypass list: checked apps connect directly; other apps enter the VPN.'))
          .fontSize(12).fontColor(this.palette.onSurfaceVariant)
        Text(this.text('进入 VPN 后仍按规则、全局或直连模式处理。黑名单留空表示不排除任何应用；白名单至少勾选一个应用。',
          'VPN traffic follows the current rule, global or direct mode. An empty bypass list excludes no apps. An allowlist needs at least one checked app.'))
          .fontSize(12).fontColor(this.palette.onSurfaceVariant)
      }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
      .backgroundColor(this.palette.card).borderRadius(22)

      Column({ space: 10 }) {
        Text(this.text('按应用包名添加', 'Add an app by bundle name'))
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
        Text(this.text('鸿蒙手机限制普通应用读取完整安装列表。请填写已安装应用的准确包名；应用名称仅用于显示。',
          'HarmonyOS phones restrict access to the full installed-app list. Enter the exact bundle name of an installed app. The label is for display only.'))
          .fontSize(12).fontColor(this.palette.onSurfaceVariant)
        TextInput({ placeholder: this.text('应用包名，如 com.example.app', 'Bundle name, e.g. com.example.app'),
          text: this.bundleInput })
          .maxLength(128).fontColor(this.palette.onSurface).enabled(!this.busy)
          .onChange((input: string): void => { this.bundleInput = input; })
        TextInput({ placeholder: this.text('应用名称（可选）', 'App label (optional)'), text: this.nameInput })
          .maxLength(64).fontColor(this.palette.onSurface).enabled(!this.busy)
          .onChange((input: string): void => { this.nameInput = input; })
        Button(this.text('添加并勾选', 'Add and check'))
          .width('100%').height(42).backgroundColor(this.palette.primary).fontColor(this.palette.onPrimary)
          .enabled(!this.busy && this.bundleInput.trim().length > 0)
          .onClick((): void => { this.addApp(); })
        if (this.formError.length > 0) {
          Text(this.formError).fontSize(12).fontColor(this.palette.onSurface)
        }
      }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
      .backgroundColor(this.palette.card).borderRadius(22)

      Text(this.text(`已勾选 ${this.selectedCount()} 个应用（最多 256 个）`,
        `${this.selectedCount()} apps checked (up to 256)`))
        .fontSize(12).fontColor(this.palette.onSurfaceVariant).width('100%')
      Search({ value: this.searchInput, placeholder: this.text('搜索名称或包名', 'Search labels or bundle names') })
        .fontColor(this.palette.onSurface)
        .onChange((input: string): void => { this.searchInput = input; })
      if (this.appItems.length === 0) {
        Text(this.text('尚未添加应用', 'No apps added yet'))
          .fontSize(13).fontColor(this.palette.onSurfaceVariant).padding(16)
      } else if (this.visibleApps().length === 0) {
        Text(this.text('没有匹配的应用', 'No matching apps'))
          .fontSize(13).fontColor(this.palette.onSurfaceVariant).padding(16)
      }
      ForEach(this.visibleApps(), (app: AppAccessItem) => {
        Column({ space: 8 }) {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(app.appName).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
              Text(app.bundleName).fontSize(11).fontColor(this.palette.onSurfaceVariant)
                .copyOption(CopyOptions.LocalDevice)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Toggle({ type: ToggleType.Checkbox, isOn: app.isSelected })
              .selectedColor(this.palette.primary).enabled(!this.busy)
              .accessibilityText(app.appName)
              .onChange((nextSelected: boolean): void => {
                this.store.setAppAccessSelected(app.bundleName, nextSelected);
                this.feedback = '';
                this.syncSettings();
              })
          }.width('100%')
          Button(this.text('移除', 'Remove'))
            .fontSize(12).height(36).fontColor(this.palette.onSurfaceVariant)
            .backgroundColor(this.palette.card).enabled(!this.busy)
            .onClick((): void => {
              this.store.removeAppAccessEntry(app.bundleName);
              this.feedback = '';
              this.syncSettings();
            })
        }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
        .backgroundColor(this.palette.card).borderRadius(22)
      }, (app: AppAccessItem): string => `${app.bundleName}_${app.isSelected}`)

      if (this.validationMessage.length > 0) {
        Text(this.validationMessage).fontSize(13).fontColor(this.palette.onSurface).width('100%')
      }
      Text(this.running
        ? (this.pendingChanges ? this.text('有未应用的修改，点击下方按钮将短暂断开并重连 VPN。',
          'Changes are pending. Applying briefly disconnects and reconnects the VPN.')
          : this.text('当前连接已使用这些分应用设置', 'The current connection uses these app-routing settings.'))
        : this.text('设置自动保存，下次连接时生效', 'Settings are saved automatically and apply on the next connection.'))
        .fontSize(12).fontColor(this.palette.onSurfaceVariant).width('100%')
      Button(this.busy ? this.text('正在连接…', 'Connecting…')
        : (this.running ? this.text('应用并重连', 'Apply and reconnect') : this.text('保存设置', 'Save settings')))
        .width('100%').height(46).fontColor(this.palette.onPrimary).backgroundColor(this.palette.primary)
        .enabled(!this.busy && this.validationMessage.length === 0 && (!this.running || this.pendingChanges))
        .onClick((): void => { this.applySettings(); })
      if (this.feedback.length > 0) {
        Text(this.feedback).fontSize(13).fontColor(this.palette.onSurface).width('100%')
      }
    }.width('100%')
  }
}

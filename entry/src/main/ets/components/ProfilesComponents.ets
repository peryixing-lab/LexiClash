import { ImmersiveTitleStyle } from '../common/ImmersiveTitleStyle';
// ProfilesComponents.ets — Mobile FlClash Profiles View with ImmersivePage & NullStatus on Install

import { ImmersiveTitlePage } from './ImmersiveTitlePage';
import { BackNavigationCoordinator, ImmersiveBackButton, ImmersivePageTransition } from './ImmersiveBackButton';
import { ResponsiveLayout } from '../common/ResponsiveLayout';
import { FlClashColorPalette, I18n, ThemeManager } from '../common/ThemeManager';
import {
  OverrideRuleItem,
  ProfileSourceKind,
  ProfileSubscriptionModel
} from '../core/CoreProtocol';
import { ParsedYamlSummary, YamlProfileParser } from '../core/YamlProfileParser';
import { ClashProfileProxyItem, ClashProxyEntry, ClashUriParser } from '../core/ClashUriParser';
import { AppStateStore } from '../store/AppStateStore';
import { WavyProgressView } from './DashboardComponents';
import { NodeImportPanel } from './NodeImportPanel';

@Component
export struct ProfilesMainView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  @StorageProp('lexiTopInset') titleTopInset: number = 0;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;

  @State @Watch('onSecondaryStateChange') activeModal: 'none' | 'add' | 'yamlEditor' | 'overrides' | 'proxiesEditor' = 'none';
  @State renderedModal: 'none' | 'add' | 'yamlEditor' | 'overrides' | 'proxiesEditor' = 'none';
  @State editingProfileId: string = '';
  @State yamlDraftText: string = '';
  @State yamlValidationMsg: string = '';
  @State yamlIsValid: boolean = true;

  @State newProfileName: string = '';
  @State newProfileUrl: string = '';
  @State newProfileFileYaml: string = '';
  @State newProfileSourceKind: ProfileSourceKind = 'url';
  @State addProfileTab: 'url' | 'file' | 'node' | 'custom' = 'url';
  @State isSubmittingProfile: boolean = false;
  @State submitErrorText: string = '';

  @State editorPrependNodes: ClashProxyEntry[] = [];
  @State editorAppendNodes: ClashProxyEntry[] = [];
  @State editorOriginalNodes: ClashProfileProxyItem[] = [];
  @State editorDeleteNames: string[] = [];
  @State editorSearchText: string = '';
  @State editorStatusMsg: string = '';

  @State newRuleType: string = 'DOMAIN-SUFFIX';
  @State newRulePayload: string = '';
  @State newRuleTarget: string = 'Proxy';
  @State localTick: number = 0;

  private store: AppStateStore = AppStateStore.getInstance();
  private storeListener: () => void = (): void => {
    this.localTick += 1;
  };

  private syncSecondaryDockState(): void {
    AppStorage.setOrCreate<boolean>('lexiProfilesSecondary', this.activeModal !== 'none');
  }

  onSecondaryStateChange(): void {
    this.syncSecondaryDockState();
  }

  aboutToAppear(): void {
    this.store.subscribe(this.storeListener);
    this.syncSecondaryDockState();
    BackNavigationCoordinator.register('profiles', (): boolean => {
      if (this.activeModal !== 'none') {
        this.activeModal = 'none';
        return true;
      }
      return false;
    });
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.storeListener);
    BackNavigationCoordinator.unregister('profiles');
    AppStorage.setOrCreate<boolean>('lexiProfilesSecondary', false);
  }

  private showOperationError(message: string): void {
    if (message.length === 0) { return; }
    try { this.getUIContext().getPromptAction().showToast({ message: message, duration: 3000 }); }
    catch (error) { /* The page may already have closed. */ }
  }

  private updateProfile(profileId: string): void {
    this.store.syncProfileById(profileId).then((message: string): void => { this.showOperationError(message); });
  }

  private hasProfilesReactive(): boolean {
    const _tick: number = this.localTick + this.revisionTick;
    return _tick >= 0 && this.store.profiles.length > 0;
  }

  private getProfilesReactive(): ProfileSubscriptionModel[] {
    const _tick: number = this.localTick + this.revisionTick;
    return _tick >= 0 ? this.store.profiles : [];
  }

  private isCurrentProfileReactive(id: string): boolean {
    const _tick: number = this.localTick + this.revisionTick;
    return _tick >= 0 && this.store.currentProfileId === id;
  }

  private openModal(modal: 'add' | 'yamlEditor' | 'overrides' | 'proxiesEditor'): void {
    this.renderedModal = modal;
    this.activeModal = modal;
  }

  private openYamlEditorFor(prof: ProfileSubscriptionModel): void {
    this.editingProfileId = prof.id;
    this.yamlDraftText = prof.yamlContent;
    const check: ParsedYamlSummary = YamlProfileParser.parseYaml(this.yamlDraftText);
    this.yamlIsValid = check.valid;
    this.yamlValidationMsg = check.valid
      ? `${check.proxiesCount} 代理 · ${check.groupsCount} 策略组 · ${check.rulesCount} 规则`
      : check.errorMessage;
    this.openModal('yamlEditor');
  }

  private openProxiesEditorFor(prof: ProfileSubscriptionModel): void {
    this.editingProfileId = prof.id;
    this.editorPrependNodes = [];
    this.editorAppendNodes = [];
    this.editorDeleteNames = [];
    this.editorSearchText = '';
    this.editorStatusMsg = '';
    this.editorOriginalNodes = ClashUriParser.listProfileProxyBlocks(prof.yamlContent);
    this.openModal('proxiesEditor');
  }

  private addNodesToProxiesEditor(entries: ClashProxyEntry[], insertPosition: 'prepend' | 'append'): void {
    const existingNames: Set<string> = new Set<string>();
    for (let i: number = 0; i < this.editorPrependNodes.length; i++) { existingNames.add(this.editorPrependNodes[i].name); }
    for (let i: number = 0; i < this.editorAppendNodes.length; i++) { existingNames.add(this.editorAppendNodes[i].name); }
    for (let i: number = 0; i < this.editorOriginalNodes.length; i++) { existingNames.add(this.editorOriginalNodes[i].name); }

    const deduped: ClashProxyEntry[] = [];
    for (let i: number = 0; i < entries.length; i++) {
      const e: ClashProxyEntry = entries[i];
      if (!existingNames.has(e.name)) {
        existingNames.add(e.name);
        deduped.push(e);
      }
    }
    if (deduped.length === 0) {
      this.editorStatusMsg = '节点名称与当前列表重复';
      return;
    }
    if (insertPosition === 'prepend') {
      this.editorPrependNodes = deduped.concat(this.editorPrependNodes);
      this.editorStatusMsg = `已前置添加 ${deduped.length} 个节点（点击右上角保存生效）`;
    } else {
      this.editorAppendNodes = this.editorAppendNodes.concat(deduped);
      this.editorStatusMsg = `已后置添加 ${deduped.length} 个节点（点击右上角保存生效）`;
    }
  }

  private moveEditorSequenceNode(isPrepend: boolean, idx: number, delta: number): void {
    const src: ClashProxyEntry[] = isPrepend ? this.editorPrependNodes.slice() : this.editorAppendNodes.slice();
    const nextIdx: number = idx + delta;
    if (idx < 0 || idx >= src.length || nextIdx < 0 || nextIdx >= src.length) {
      return;
    }
    const moved: ClashProxyEntry = src.splice(idx, 1)[0];
    src.splice(nextIdx, 0, moved);
    if (isPrepend) {
      this.editorPrependNodes = src;
    } else {
      this.editorAppendNodes = src;
    }
  }

  private removeEditorAddedNode(isPrepend: boolean, nodeName: string): void {
    if (isPrepend) {
      this.editorPrependNodes = this.editorPrependNodes.filter((item: ClashProxyEntry): boolean => item.name !== nodeName);
    } else {
      this.editorAppendNodes = this.editorAppendNodes.filter((item: ClashProxyEntry): boolean => item.name !== nodeName);
    }
  }

  private toggleDeleteOriginalNode(name: string): void {
    if (this.editorDeleteNames.includes(name)) {
      this.editorDeleteNames = this.editorDeleteNames.filter((n: string): boolean => n !== name);
    } else {
      this.editorDeleteNames = this.editorDeleteNames.concat([name]);
    }
  }

  private saveProxiesEditor(): void {
    const err: string = this.store.applyProfileProxiesEdit(
      this.editingProfileId,
      this.editorPrependNodes,
      this.editorAppendNodes,
      this.editorDeleteNames
    );
    if (err.length > 0) {
      this.editorStatusMsg = err;
      return;
    }
    this.activeModal = 'none';
    try {
      this.getUIContext().getPromptAction().showToast({ message: '节点列表已保存', duration: 1600 });
    } catch (_toastErr) {
      // ignore
    }
  }

  private filteredPrependNodes(): ClashProxyEntry[] {
    const kw: string = this.editorSearchText.trim().toLowerCase();
    return this.editorPrependNodes.filter((item: ClashProxyEntry): boolean =>
      kw.length === 0 || item.name.toLowerCase().includes(kw) || item.type.toLowerCase().includes(kw)
    );
  }

  private filteredOriginalNodes(): ClashProfileProxyItem[] {
    const kw: string = this.editorSearchText.trim().toLowerCase();
    return this.editorOriginalNodes.filter((item: ClashProfileProxyItem): boolean =>
      kw.length === 0 || item.name.toLowerCase().includes(kw) || item.protocol.toLowerCase().includes(kw)
    );
  }

  private filteredAppendNodes(): ClashProxyEntry[] {
    const kw: string = this.editorSearchText.trim().toLowerCase();
    return this.editorAppendNodes.filter((item: ClashProxyEntry): boolean =>
      kw.length === 0 || item.name.toLowerCase().includes(kw) || item.type.toLowerCase().includes(kw)
    );
  }

  private async submitSingleNodeProfile(entries: ClashProxyEntry[]): Promise<void> {
    if (this.isSubmittingProfile || entries.length === 0) {
      return;
    }
    this.isSubmittingProfile = true;
    this.submitErrorText = '';
    const generatedYaml: string = ClashUriParser.buildCompleteYamlFromEntries(entries);
    const autoLabel: string = this.newProfileName.trim().length > 0
      ? this.newProfileName.trim()
      : (entries.length === 1 ? entries[0].name : `节点配置 ${this.store.profiles.length + 1}`);
    const err: string = await this.store.addNewProfile(autoLabel, '', 'file', generatedYaml);
    this.isSubmittingProfile = false;
    if (err.length > 0) {
      this.submitErrorText = err;
      return;
    }
    this.activeModal = 'none';
  }

  private getUsageRatio(prof: ProfileSubscriptionModel): number {
    if (prof.totalBytes <= 0) {
      return 0;
    }
    return Math.min(1.0, Math.max(0.0, (prof.usedUploadBytes + prof.usedDownloadBytes) / prof.totalBytes));
  }

  private getExpireDaysText(prof: ProfileSubscriptionModel): string {
    if (prof.expireTimestamp <= 0) {
      return prof.sourceType === 'custom' ? '自定义' : prof.sourceType === 'url' ? '远程' : '本地';
    }
    const days: number = Math.max(0, Math.round((prof.expireTimestamp - Date.now() / 1000) / 86400));
    return `${days} ${I18n.t('daysLeft', this.store.localeLang)}`;
  }

  private addPresetRule(ruleType: string, payload: string, targetGroup: string): void {
    this.store.overrideRules.unshift({
      id: 'or_' + Date.now() + '_' + Math.floor(Math.random() * 100),
      ruleType: ruleType,
      payload: payload,
      targetGroup: targetGroup,
      noResolve: ruleType === 'IP-CIDR' || ruleType === 'GEOIP',
      enabled: true
    });
    this.store.notify();
    try {
      this.getUIContext().getPromptAction().showToast({
        message: `已添加规则: ${ruleType},${payload},${targetGroup}`,
        duration: 1400
      });
    } catch (e) {
      // ignore
    }
  }

  private async submitAddProfile(): Promise<void> {
    if (this.isSubmittingProfile) {
      return;
    }
    this.submitErrorText = '';
    if (this.newProfileSourceKind === 'url' && this.newProfileUrl.trim().length === 0) {
      this.submitErrorText = '请输入配置 URL';
      return;
    }
    if (this.newProfileSourceKind === 'file' && this.newProfileFileYaml.trim().length === 0) {
      this.submitErrorText = '请输入或粘贴配置内容';
      return;
    }

    this.isSubmittingProfile = true;
    const err: string = await this.store.addNewProfile(
      this.newProfileName,
      this.newProfileUrl,
      this.newProfileSourceKind,
      this.newProfileFileYaml
    );
    this.isSubmittingProfile = false;

    if (err.length > 0) {
      this.submitErrorText = err;
      return;
    }

    this.activeModal = 'none';
  }

  private getActiveHeaderTitle(): string {
    const modalKey: string = this.activeModal === 'none' ? this.renderedModal : this.activeModal;
    if (modalKey === 'add') {
      return this.store.localeLang === 'en_US' ? 'Add Profile' : '添加配置';
    }
    if (modalKey === 'proxiesEditor') {
      return this.store.localeLang === 'en_US' ? 'Edit Nodes' : '编辑节点';
    }
    if (modalKey === 'yamlEditor') {
      return this.store.localeLang === 'en_US' ? 'Edit YAML' : '编辑 YAML';
    }
    if (modalKey === 'overrides') {
      return this.store.localeLang === 'en_US' ? 'Overrides' : '覆写规则';
    }
    return I18n.t('profiles', this.store.localeLang);
  }

  @Builder
  mainHeader() {
    Row({ space: 10 }) {
      Text(I18n.t('profiles', this.store.localeLang))
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .layoutWeight(1)

      if (this.hasProfilesReactive()) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(17)
            .fontColor([this.palette.onSurface])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, false))
        .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, false))
        .onClick((): void => {
          for (let i = 0; i < this.store.profiles.length; i++) {
            if (this.store.profiles[i].sourceType === 'url') {
              this.updateProfile(this.store.profiles[i].id);
            }
          }
        })

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(17)
            .fontColor([this.palette.primary])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, true))
        .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, true))
        .onClick((): void => {
          this.newProfileName = '';
          this.newProfileUrl = '';
          this.newProfileFileYaml = '';
          this.submitErrorText = '';
          this.newProfileSourceKind = 'url';
          this.addProfileTab = 'url';
          this.openModal('add');
        })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  modalHeader() {
    Row({ space: 10 }) {
      ImmersiveBackButton({
        palette: this.palette,
        immersiveEnabled: this.store.liquidGlass,
        onBack: (): void => {
          this.activeModal = 'none';
        }
      })

      Text(this.getActiveHeaderTitle())
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  profileCardItem(prof: ProfileSubscriptionModel) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(prof.sourceType === 'url'
            ? $r('sys.symbol.link')
            : prof.sourceType === 'custom'
              ? $r('sys.symbol.doc_plaintext')
              : $r('sys.symbol.folder'))
            .fontSize(18)
            .fontColor([this.isCurrentProfileReactive(prof.id) ? this.palette.primary : this.palette.onSurfaceVariant])
        }
        .width(40)
        .height(40)
        .borderRadius(14)
        .backgroundColor(this.isCurrentProfileReactive(prof.id) ? this.palette.primarySoft : this.palette.block)

        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(prof.label)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(prof.sourceType === 'url' ? '远程' : prof.sourceType === 'custom' ? '自定义' : '本地')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurfaceVariant)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.palette.block)
              .borderRadius(6)
          }
          .alignItems(VerticalAlign.Center)

          Text(`${prof.lastUpdatedText} · ${this.getExpireDaysText(prof)}`)
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.isCurrentProfileReactive(prof.id)) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(13)
              .fontColor([this.palette.onPrimary])
          }
          .width(24)
          .height(24)
          .borderRadius(12)
          .backgroundColor(this.palette.primary)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (prof.totalBytes > 0) {
        Column({ space: 6 }) {
          Row() {
            Text(`${Math.round(this.getUsageRatio(prof) * 100)}% ${I18n.t('used', this.store.localeLang)}`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
            Blank()
            Text(`${ThemeManager.formatBytes(prof.usedUploadBytes + prof.usedDownloadBytes)} / ${ThemeManager.formatBytes(prof.totalBytes)}`)
              .fontSize(12)
              .fontColor(this.palette.onSurfaceVariant)
          }
          .width('100%')

          WavyProgressView({
            progressRatio: this.getUsageRatio(prof),
            activeColor: this.palette.primary,
            trackColor: this.palette.inset,
            revisionTick: this.revisionTick
          })
        }
        .width('100%')
        .padding({ top: 4, bottom: 2 })
      } else {
        Row({ space: 16 }) {
          Column({ space: 2 }) {
            Text(`${prof.groupsCount}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
            Text(I18n.t('proxyGroup', this.store.localeLang))
              .fontSize(11)
              .fontColor(this.palette.onSurfaceVariant)
          }
          .alignItems(HorizontalAlign.Start)

          Column({ space: 2 }) {
            Text(`${prof.proxiesCount}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
            Text(I18n.t('proxies', this.store.localeLang))
              .fontSize(11)
              .fontColor(this.palette.onSurfaceVariant)
          }
          .alignItems(HorizontalAlign.Start)

          Column({ space: 2 }) {
            Text(`${prof.rulesCount}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
            Text(I18n.t('rule', this.store.localeLang))
              .fontSize(11)
              .fontColor(this.palette.onSurfaceVariant)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.palette.block)
        .borderRadius(14)
      }

      Row({ space: 6 }) {
        if (prof.sourceType === 'url') {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(12)
              .fontColor([this.palette.onSurface])
            Text(prof.isUpdating ? '...' : (this.store.localeLang === 'en_US' ? 'Sync' : '更新'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette.onSurface)
          }
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(this.palette.block)
          .borderRadius(12)
          .onClick((): void => {
            this.updateProfile(prof.id);
          })
        }

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.globe_badge_heart'))
            .fontSize(12)
            .fontColor([this.palette.primary])
          Text(this.store.localeLang === 'en_US' ? 'Nodes' : '编辑节点')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.primary)
        }
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .backgroundColor(this.palette.primarySoft)
        .borderRadius(12)
        .onClick((): void => {
          this.openProxiesEditorFor(prof);
        })

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(12)
            .fontColor([this.palette.onSurface])
          Text('YAML')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.onSurface)
        }
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .backgroundColor(this.palette.block)
        .borderRadius(12)
        .onClick((): void => {
          this.openYamlEditorFor(prof);
        })

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
            .fontSize(12)
            .fontColor([this.palette.onSurface])
          Text(this.store.localeLang === 'en_US' ? 'Override' : '覆写')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.onSurface)
        }
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .backgroundColor(this.palette.block)
        .borderRadius(12)
        .onClick((): void => {
          this.editingProfileId = prof.id;
          this.openModal('overrides');
        })

        Blank()

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(14)
            .fontColor([this.palette.error])
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(this.palette.errorContainer)
        .onClick((): void => {
          this.store.deleteProfile(prof.id);
          this.showOperationError(this.store.lastOperationError);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.palette.card)
    .borderRadius(28)
    .onClick((): void => {
      this.store.selectProfile(prof.id);
      this.showOperationError(this.store.lastOperationError);
    })
  }

  @Builder
  modalBody() {
    Column({ space: 12 }) {
      if (this.renderedModal === 'add') {
        Scroll() {
          Column({ space: 14 }) {
            Text(this.store.localeLang === 'en_US' ? 'Add Profile' : '添加配置')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)

            Scroll() {
              Row({ space: 6 }) {
                ForEach(
                  ['url', 'file', 'node', 'custom'],
                  (kind: string) => {
                    Text(kind === 'url'
                      ? (this.store.localeLang === 'en_US' ? 'Via URL' : 'URL 订阅')
                      : kind === 'file'
                        ? (this.store.localeLang === 'en_US' ? 'Paste Config' : '粘贴配置')
                        : kind === 'node'
                          ? '单节点/SOCKS5'
                          : (this.store.localeLang === 'en_US' ? 'From Scratch' : '从零开始'))
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.addProfileTab === kind ? this.palette.onPrimary : this.palette.onSurface)
                      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                      .backgroundColor(this.addProfileTab === kind ? this.palette.primary : this.palette.block)
                      .borderRadius(12)
                      .onClick((): void => {
                        this.addProfileTab = kind as 'url' | 'file' | 'node' | 'custom';
                        this.newProfileSourceKind = kind === 'node' ? 'file' : (kind as ProfileSourceKind);
                        this.submitErrorText = '';
                      })
                  },
                  (kind: string): string => `${kind}_${this.addProfileTab === kind}`
                )
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')

            Column({ space: 6 }) {
              Text(this.store.localeLang === 'en_US' ? 'Name (Optional)' : '名称（可选）')
                .fontSize(13)
                .fontColor(this.palette.onSurfaceVariant)
              TextInput({
                placeholder: this.store.localeLang === 'en_US' ? 'Enter profile name' : '请输入配置名称',
                text: this.newProfileName
              })
                .height(44)
                .fontSize(14)
                .fontColor(this.palette.onSurface)
                .placeholderColor(this.palette.onSurfaceVariant)
                .backgroundColor(this.palette.block)
                .borderRadius(14)
                .onChange((v: string): void => {
                  this.newProfileName = v;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            if (this.addProfileTab === 'url') {
              Column({ space: 6 }) {
                Text('URL')
                  .fontSize(13)
                  .fontColor(this.palette.onSurfaceVariant)
                TextInput({
                  placeholder: 'https://...',
                  text: this.newProfileUrl
                })
                  .height(44)
                  .fontSize(14)
                  .fontColor(this.palette.onSurface)
                  .placeholderColor(this.palette.onSurfaceVariant)
                  .backgroundColor(this.palette.block)
                  .borderRadius(14)
                  .onChange((v: string): void => {
                    this.newProfileUrl = v;
                  })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            } else if (this.addProfileTab === 'file') {
              Column({ space: 6 }) {
                Text(this.store.localeLang === 'en_US' ? 'YAML / Base64 / Node URIs' : 'YAML 配置、Base64 或节点分享链接')
                  .fontSize(13)
                  .fontColor(this.palette.onSurfaceVariant)
                TextArea({
                  placeholder: '粘贴 Clash YAML、Base64 或多条 socks5:// / ss:// / trojan:// / vmess:// / vless:// / hy2:// 链接',
                  text: this.newProfileFileYaml
                })
                  .height(160)
                  .fontSize(12)
                  .fontFamily('monospace')
                  .fontColor(this.palette.onSurface)
                  .placeholderColor(this.palette.onSurfaceVariant)
                  .backgroundColor(this.palette.block)
                  .borderRadius(14)
                  .onChange((v: string): void => {
                    this.newProfileFileYaml = v;
                  })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            } else if (this.addProfileTab === 'node') {
              NodeImportPanel({
                palette: this.palette,
                singleButtonMode: true,
                primaryActionLabel: '导入并创建配置',
                onImportEntries: (entries: ClashProxyEntry[], _insertPosition: 'prepend' | 'append'): void => {
                  this.submitSingleNodeProfile(entries);
                }
              })
            }

            if (this.submitErrorText.length > 0) {
              Text(this.submitErrorText)
                .fontSize(12)
                .fontColor(this.palette.error)
                .width('100%')
            }

            if (this.addProfileTab !== 'node') {
              Row({ space: 10 }) {
                Button() {
                  Text(this.store.localeLang === 'en_US' ? 'Cancel' : '取消')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)
                }
                .layoutWeight(1)
                .height(44)
                .backgroundColor(this.palette.block)
                .borderRadius(18)
                .onClick((): void => {
                  this.activeModal = 'none';
                })

                Button() {
                  Text(this.isSubmittingProfile
                    ? (this.store.localeLang === 'en_US' ? 'Loading…' : '加载中…')
                    : (this.store.localeLang === 'en_US' ? 'Submit' : '提交'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onPrimary)
                }
                .layoutWeight(2)
                .height(44)
                .backgroundColor(this.palette.primary)
                .borderRadius(18)
                .onClick((): void => {
                  this.submitAddProfile();
                })
              }
              .width('100%')
              .margin({ top: 6 })
            }
          }
          .width('100%')
          .padding(20)
          .backgroundColor(this.palette.card)
          .borderRadius(28)
        }
        .contentStartOffset(64 + this.titleTopInset)
        .contentEndOffset(this.bottomInset)
        .padding({ left: 18, right: 18, bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset) })
        .layoutWeight(1)
        .align(Alignment.Top)
      } else if (this.renderedModal === 'proxiesEditor') {
        Scroll() {
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text('编辑节点')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
                .layoutWeight(1)

              Button('取消')
                .height(34)
                .fontSize(12)
                .fontColor(this.palette.onSurface)
                .backgroundColor(this.palette.block)
                .borderRadius(16)
                .onClick((): void => {
                  this.activeModal = 'none';
                })

              Button('保存')
                .height(34)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onPrimary)
                .backgroundColor(this.palette.primary)
                .borderRadius(16)
                .onClick((): void => {
                  this.saveProxiesEditor();
                })
            }
            .width('100%')

            Column({ space: 10 }) {
              NodeImportPanel({
                palette: this.palette,
                singleButtonMode: false,
                onImportEntries: (entries: ClashProxyEntry[], insertPosition: 'prepend' | 'append'): void => {
                  this.addNodesToProxiesEditor(entries, insertPosition);
                }
              })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.palette.card)
            .borderRadius(22)

            if (this.editorStatusMsg.length > 0) {
              Text(this.editorStatusMsg)
                .fontSize(12)
                .fontColor(this.palette.primary)
                .width('100%')
            }

            TextInput({ placeholder: '搜索节点名称 / 协议', text: this.editorSearchText })
              .height(38)
              .width('100%')
              .fontSize(12)
              .fontColor(this.palette.onSurface)
              .placeholderColor(this.palette.onSurfaceVariant)
              .backgroundColor(this.palette.card)
              .borderRadius(16)
              .onChange((val: string): void => {
                this.editorSearchText = val;
              })

            if (this.filteredPrependNodes().length > 0) {
              Column({ space: 6 }) {
                Text(`前置节点 (${this.filteredPrependNodes().length})`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette.ok)
                ForEach(
                  this.filteredPrependNodes(),
                  (pNode: ClashProxyEntry, pIdx: number) => {
                    Row({ space: 8 }) {
                      Text('前置')
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onOkContainer)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor(this.palette.okContainer)
                        .borderRadius(6)
                      Column({ space: 2 }) {
                        Text(pNode.name)
                          .fontSize(13)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.palette.onSurface)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${pNode.type} · ${pNode.server}:${pNode.port}`)
                          .fontSize(11)
                          .fontColor(this.palette.onSurfaceVariant)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.chevron_up'))
                          .fontSize(14)
                          .fontColor([this.palette.onSurface])
                      }
                        .height(28).width(28).padding(0)
                        .backgroundColor(this.palette.block)
                        .accessibilityText('上移 ' + pNode.name)
                        .onClick((): void => { this.moveEditorSequenceNode(true, this.editorPrependNodes.indexOf(pNode), -1); })
                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.chevron_down'))
                          .fontSize(14)
                          .fontColor([this.palette.onSurface])
                      }
                        .height(28).width(28).padding(0)
                        .backgroundColor(this.palette.block)
                        .accessibilityText('下移 ' + pNode.name)
                        .onClick((): void => { this.moveEditorSequenceNode(true, this.editorPrependNodes.indexOf(pNode), 1); })
                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.xmark'))
                          .fontSize(12)
                          .fontColor([this.palette.error])
                      }
                        .height(28).width(28).padding(0)
                        .backgroundColor(this.palette.errorContainer)
                        .accessibilityText('移除 ' + pNode.name)
                        .onClick((): void => { this.removeEditorAddedNode(true, pNode.name); })
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor(this.palette.okContainer)
                    .borderRadius(16)
                  },
                  (pNode: ClashProxyEntry): string => `pre_${pNode.name}_${this.editorPrependNodes.indexOf(pNode)}`
                )
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            Column({ space: 6 }) {
              Text(`原配置节点 (${this.filteredOriginalNodes().length})`)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurfaceVariant)
              ForEach(
                this.filteredOriginalNodes(),
                (oNode: ClashProfileProxyItem) => {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text(oNode.name)
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.editorDeleteNames.includes(oNode.name) ? this.palette.error : this.palette.onSurface)
                        .decoration({
                          type: this.editorDeleteNames.includes(oNode.name) ? TextDecorationType.LineThrough : TextDecorationType.None
                        })
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(oNode.protocol)
                        .fontSize(11)
                        .fontColor(this.palette.onSurfaceVariant)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Button(this.editorDeleteNames.includes(oNode.name) ? '撤销' : '删除')
                      .height(30)
                      .fontSize(11)
                      .fontColor(this.editorDeleteNames.includes(oNode.name) ? this.palette.onSurface : this.palette.error)
                      .backgroundColor(this.editorDeleteNames.includes(oNode.name) ? this.palette.block : this.palette.errorContainer)
                      .borderRadius(10)
                      .onClick((): void => {
                        this.toggleDeleteOriginalNode(oNode.name);
                      })
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(this.editorDeleteNames.includes(oNode.name) ? this.palette.errorContainer : this.palette.card)
                  .borderRadius(16)
                },
                (oNode: ClashProfileProxyItem): string => `orig_${oNode.name}_${this.editorDeleteNames.includes(oNode.name)}`
              )
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            if (this.filteredAppendNodes().length > 0) {
              Column({ space: 6 }) {
                Text(`后置节点 (${this.filteredAppendNodes().length})`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette.ok)
                ForEach(
                  this.filteredAppendNodes(),
                  (aNode: ClashProxyEntry, aIdx: number) => {
                    Row({ space: 8 }) {
                      Text('后置')
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onOkContainer)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor(this.palette.okContainer)
                        .borderRadius(6)
                      Column({ space: 2 }) {
                        Text(aNode.name)
                          .fontSize(13)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.palette.onSurface)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${aNode.type} · ${aNode.server}:${aNode.port}`)
                          .fontSize(11)
                          .fontColor(this.palette.onSurfaceVariant)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.chevron_up'))
                          .fontSize(14)
                          .fontColor([this.palette.onSurface])
                      }
                        .height(28).width(28).padding(0)
                        .backgroundColor(this.palette.block)
                        .accessibilityText('上移 ' + aNode.name)
                        .onClick((): void => { this.moveEditorSequenceNode(false, this.editorAppendNodes.indexOf(aNode), -1); })
                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.chevron_down'))
                          .fontSize(14)
                          .fontColor([this.palette.onSurface])
                      }
                        .height(28).width(28).padding(0)
                        .backgroundColor(this.palette.block)
                        .accessibilityText('下移 ' + aNode.name)
                        .onClick((): void => { this.moveEditorSequenceNode(false, this.editorAppendNodes.indexOf(aNode), 1); })
                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.xmark'))
                          .fontSize(12)
                          .fontColor([this.palette.error])
                      }
                        .height(28).width(28).padding(0)
                        .backgroundColor(this.palette.errorContainer)
                        .accessibilityText('移除 ' + aNode.name)
                        .onClick((): void => { this.removeEditorAddedNode(false, aNode.name); })
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor(this.palette.okContainer)
                    .borderRadius(16)
                  },
                  (aNode: ClashProxyEntry): string => `app_${aNode.name}_${this.editorAppendNodes.indexOf(aNode)}`
                )
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset) })
        }
        .contentStartOffset(64 + this.titleTopInset)
        .contentEndOffset(this.bottomInset)
        .layoutWeight(1)
        .align(Alignment.Top)
      } else if (this.renderedModal === 'yamlEditor') {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Circle({ width: 8, height: 8 })
              .fill(this.yamlIsValid ? this.palette.ok : this.palette.error)
            Text(this.yamlValidationMsg)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.yamlIsValid ? this.palette.onSurfaceVariant : this.palette.error)
              .layoutWeight(1)

            Button() {
              Text(this.store.localeLang === 'en_US' ? 'Save' : '保存')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onPrimary)
            }
            .height(32)
            .padding({ left: 14, right: 14 })
            .backgroundColor(this.palette.primary)
            .borderRadius(16)
            .onClick((): void => {
              const res: ParsedYamlSummary = this.store.saveProfileYaml(this.editingProfileId, this.yamlDraftText);
              this.yamlIsValid = res.valid;
              if (res.valid) {
                this.activeModal = 'none';
              } else {
                this.yamlValidationMsg = res.errorMessage;
              }
            })
          }
          .width('100%')
          .padding({ left: 18, right: 18 })
          .alignItems(VerticalAlign.Center)

          TextArea({ text: this.yamlDraftText })
            .layoutWeight(1)
            .width('92%')
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor(this.palette.onSurface)
            .backgroundColor(this.palette.card)
            .borderRadius(22)
            .padding(14)
            .onChange((val: string): void => {
              this.yamlDraftText = val;
              const check: ParsedYamlSummary = YamlProfileParser.parseYaml(val);
              this.yamlIsValid = check.valid;
              this.yamlValidationMsg = check.valid
                ? `${check.proxiesCount} 代理 · ${check.groupsCount} 策略组 · ${check.rulesCount} 规则`
                : check.errorMessage;
            })
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset) })
      } else if (this.renderedModal === 'overrides') {
        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 10 }) {
              Text(this.store.localeLang === 'en_US' ? 'Quick Actions' : '快捷操作')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)

              Flex({ wrap: FlexWrap.Wrap }) {
                Text('屏蔽 QUIC')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.primary)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(this.palette.primarySoft)
                  .borderRadius(12)
                  .margin({ right: 8, bottom: 8 })
                  .onClick((): void => {
                    this.addPresetRule('AND', '((NETWORK,UDP),(DST-PORT,443))', 'REJECT');
                  })

                Text('屏蔽 STUN')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.primary)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(this.palette.primarySoft)
                  .borderRadius(12)
                  .margin({ right: 8, bottom: 8 })
                  .onClick((): void => {
                    this.addPresetRule('DST-PORT', '3478', 'REJECT');
                  })

                Text('Apple 与 Microsoft 直连')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.primary)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(this.palette.primarySoft)
                  .borderRadius(12)
                  .margin({ right: 8, bottom: 8 })
                  .onClick((): void => {
                    this.addPresetRule('GEOSITE', 'apple,microsoft', 'DIRECT');
                  })

                Text('局域网直连')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.primary)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(this.palette.primarySoft)
                  .borderRadius(12)
                  .margin({ right: 8, bottom: 8 })
                  .onClick((): void => {
                    this.addPresetRule('GEOIP', 'PRIVATE', 'DIRECT');
                  })
              }
              .width('100%')
            }
            .width('100%')
            .padding(18)
            .backgroundColor(this.palette.card)
            .borderRadius(26)
            .alignItems(HorizontalAlign.Start)

            Column({ space: 10 }) {
              Text(this.store.localeLang === 'en_US' ? 'Add Rule' : '添加规则')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)

              Row({ space: 6 }) {
                ForEach(
                  ['DOMAIN-SUFFIX', 'DOMAIN-KEYWORD', 'IP-CIDR', 'GEOIP'],
                  (rt: string) => {
                    Text(rt)
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.newRuleType === rt ? this.palette.onPrimary : this.palette.onSurface)
                      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                      .backgroundColor(this.newRuleType === rt ? this.palette.primary : this.palette.block)
                      .borderRadius(10)
                      .onClick((): void => {
                        this.newRuleType = rt;
                      })
                  },
                  (rt: string): string => rt
                )
              }
              .width('100%')

              Row({ space: 8 }) {
                TextInput({
                  placeholder: this.store.localeLang === 'en_US' ? 'Enter rule content' : '输入规则内容',
                  text: this.newRulePayload
                })
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(13)
                  .fontColor(this.palette.onSurface)
                  .placeholderColor(this.palette.onSurfaceVariant)
                  .backgroundColor(this.palette.block)
                  .borderRadius(12)
                  .onChange((val: string): void => {
                    this.newRulePayload = val;
                  })

                Button() {
                  Text(this.store.localeLang === 'en_US' ? 'Add' : '添加')
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onPrimary)
                }
                .height(40)
                .padding({ left: 16, right: 16 })
                .backgroundColor(this.palette.primary)
                .borderRadius(12)
                .onClick((): void => {
                  if (this.newRulePayload.trim().length > 0) {
                    this.addPresetRule(this.newRuleType, this.newRulePayload.trim(), this.newRuleTarget);
                    this.newRulePayload = '';
                  }
                })
              }
              .width('100%')
            }
            .width('100%')
            .padding(18)
            .backgroundColor(this.palette.card)
            .borderRadius(26)
            .alignItems(HorizontalAlign.Start)

            if (this.store.overrideRules.length === 0) {
              Text('暂无附加规则')
                .fontSize(13)
                .fontColor(this.palette.onSurfaceVariant)
                .padding({ top: 16 })
            } else {
              Column({ space: 8 }) {
                ForEach(
                  this.store.overrideRules,
                  (rItem: OverrideRuleItem) => {
                    Row({ space: 10 }) {
                      Column({ space: 3 }) {
                        Row({ space: 6 }) {
                          Text(rItem.ruleType)
                            .fontSize(11)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(this.palette.primary)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .backgroundColor(this.palette.primarySoft)
                            .borderRadius(6)

                          Text(rItem.payload)
                            .fontSize(14)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(this.palette.onSurface)
                        }
                        Text(`→ ${rItem.targetGroup}`)
                          .fontSize(12)
                          .fontColor(this.palette.onSurfaceVariant)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Toggle({ type: ToggleType.Switch, isOn: rItem.enabled })
                        .selectedColor(this.palette.primary)
                        .onChange((v: boolean): void => {
                          rItem.enabled = v;
                          this.store.notify();
                        })
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    .backgroundColor(this.palette.card)
                    .borderRadius(20)
                    .alignItems(VerticalAlign.Center)
                  },
                  (rItem: OverrideRuleItem): string => `${rItem.id}_${rItem.enabled}`
                )
              }
              .width('100%')
            }
          }
          .padding({ left: 18, right: 18, bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset) })
        }
        .contentStartOffset(64 + this.titleTopInset)
        .contentEndOffset(this.bottomInset)
        .layoutWeight(1)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  mainBody() {
    Column({ space: 12 }) {
      if (!this.hasProfilesReactive()) {
        Column({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(34)
              .fontColor([this.palette.onSurfaceVariant])
          }
          .width(76)
          .height(76)
          .borderRadius(28)
          .backgroundColor(this.palette.card)

          Text(this.store.localeLang === 'en_US' ? 'No Profiles' : '暂无配置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurface)

          Text(this.store.localeLang === 'en_US'
            ? 'Add a profile to get started'
            : '添加一个配置文件后即可开始使用')
            .fontSize(13)
            .fontColor(this.palette.onSurfaceVariant)

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(15)
                .fontColor([this.palette.onPrimary])
              Text(this.store.localeLang === 'en_US' ? 'Add Profile' : '添加配置')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onPrimary)
            }
          }
          .height(42)
          .padding({ left: 20, right: 20 })
          .backgroundColor(this.palette.primary)
          .borderRadius(21)
          .margin({ top: 6 })
          .onClick((): void => {
            this.newProfileName = '';
            this.newProfileUrl = '';
            this.newProfileFileYaml = '';
            this.submitErrorText = '';
            this.newProfileSourceKind = 'url';
            this.addProfileTab = 'url';
            this.openModal('add');
          })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 80 })
      } else {
        Scroll() {
          Column() {
            if (this.windowWidthVp >= 720) {
              Grid() {
                ForEach(
                  this.getProfilesReactive(),
                  (prof: ProfileSubscriptionModel) => {
                    GridItem() {
                      this.profileCardItem(prof)
                    }
                  },
                  (prof: ProfileSubscriptionModel): string => `${prof.id}_${this.isCurrentProfileReactive(prof.id)}_${prof.lastUpdatedText}_${prof.isUpdating}_${prof.proxiesCount}_${prof.groupsCount}`
                )
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(12)
              .rowsGap(12)
              .width('100%')
            } else {
              Column({ space: 12 }) {
                ForEach(
                  this.getProfilesReactive(),
                  (prof: ProfileSubscriptionModel) => {
                    this.profileCardItem(prof)
                  },
                  (prof: ProfileSubscriptionModel): string => `${prof.id}_${this.isCurrentProfileReactive(prof.id)}_${prof.lastUpdatedText}_${prof.isUpdating}_${prof.proxiesCount}_${prof.groupsCount}`
                )
              }
              .width('100%')
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.windowWidthVp) })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            bottom: ResponsiveLayout.bottomContentPadding(this.windowWidthVp, this.bottomInset)
          })
        }
        .contentStartOffset(64 + this.titleTopInset)
        .contentEndOffset(this.bottomInset)
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column() {
        ImmersiveTitlePage({
          palette: this.palette,
          immersiveEnabled: this.store.liquidGlass,
          scrollUnderTitle: true,
          revisionTick: this.revisionTick,
          header: (): void => { this.mainHeader(); },
          bodyContent: (): void => { this.mainBody(); }
        })
      }
      .width('100%')
      .height('100%')

      if (this.activeModal !== 'none') {
        Column() {
          ImmersiveTitlePage({
            palette: this.palette,
            immersiveEnabled: this.store.liquidGlass,
            scrollUnderTitle: this.renderedModal !== 'yamlEditor',
            revisionTick: this.revisionTick,
            header: (): void => { this.modalHeader(); },
            bodyContent: (): void => { this.modalBody(); }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.page)
        .zIndex(1)
        .transition(ImmersivePageTransition.secondaryPage())
      }
    }
    .width('100%')
    .height('100%')
  }
}

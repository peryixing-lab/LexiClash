import { pasteboard } from '@kit.BasicServicesKit';
import { ResponsiveLayout } from '../common/ResponsiveLayout';
import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';
import { OutboundModeType, ProfileSubscriptionModel, ProxyGroupItem, ProxyNodeItem } from '../core/CoreProtocol';
import { ClashProxyEntry } from '../core/ClashUriParser';
import { LexiChainBuildResult } from '../core/ProxyChainConfig';
import { AppStateStore } from '../store/AppStateStore';
import { BackNavigationCoordinator } from './ImmersiveBackButton';
import { NodeImportPanel } from './NodeImportPanel';

@Component
export struct ProxyChainPanel {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop @Watch('refreshDraft') revisionTick: number = 0;
  onExitChainMode: () => void = (): void => {};
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;

  @State chainNames: string[] = [];
  @State chainMessage: string = '';
  @State chainMessageIsWarning: boolean = false;
  @State candidateSearch: string = '';
  @State showPreview: boolean = false;
  @State showImportInChain: boolean = false;
  @State previewYaml: string = '';
  @State nodeScopeMode: 'auto' | 'group' | 'all' = 'auto';
  private store: AppStateStore = AppStateStore.getInstance();
  private lastProfileId: string = '';

  aboutToAppear(): void {
    this.refreshDraft();
    BackNavigationCoordinator.register('chainModal', (): boolean => {
      if (this.showImportInChain) {
        this.showImportInChain = false;
        return true;
      }
      if (this.showPreview) {
        this.showPreview = false;
        return true;
      }
      return false;
    });
  }

  aboutToDisappear(): void {
    BackNavigationCoordinator.unregister('chainModal');
  }

  refreshDraft(): void {
    if (this.lastProfileId !== this.store.currentProfileId) {
      this.lastProfileId = this.store.currentProfileId;
      this.chainMessage = '';
      this.chainMessageIsWarning = false;
      this.showPreview = false;
      this.showImportInChain = false;
      this.nodeScopeMode = 'auto';
    }
    this.chainNames = this.store.getProxyChainDraft().nodeNames.slice();
  }

  private currentMode(): OutboundModeType {
    return this.revisionTick >= 0 ? this.store.outboundMode : 'rule';
  }

  private currentProfile(): ProfileSubscriptionModel | null {
    return this.revisionTick >= 0 ? this.store.getCurrentProfile() : null;
  }

  private allProfiles(): ProfileSubscriptionModel[] {
    return this.revisionTick >= 0 ? this.store.profiles : [];
  }

  private targetGroupName(): string {
    return this.revisionTick >= 0 ? this.store.getProxyChainDraft().targetGroup : '';
  }

  private isConnected(): boolean {
    return this.revisionTick >= 0 && this.store.chainConnected;
  }

  private isConnecting(): boolean {
    return this.revisionTick >= 0 && this.store.isChainConnecting;
  }

  private isDraftApplied(): boolean {
    return this.revisionTick >= 0 && this.store.isProxyChainDraftApplied();
  }

  private validationError(): string {
    return this.revisionTick >= 0 ? this.store.getProxyChainValidationError() : '';
  }

  private coreMissing(): boolean {
    return this.revisionTick >= 0 && this.store.getRuntimeUnavailableReason().length > 0;
  }

  private groups(): ProxyGroupItem[] {
    return this.revisionTick >= 0
      ? this.store.proxyGroups.filter((group: ProxyGroupItem): boolean => group.groupType === 'Selector' && !group.hidden)
      : [];
  }

  private selectedGroupItem(): ProxyGroupItem | null {
    const target: string = this.targetGroupName();
    const list: ProxyGroupItem[] = this.groups();
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].name === target) {
        return list[i];
      }
    }
    return null;
  }

  private allImportedNodes(): ProxyNodeItem[] {
    return this.revisionTick >= 0 ? this.store.getImportedProfileNodes() : [];
  }

  private activeSelectedNode(): ProxyNodeItem | null {
    return this.revisionTick >= 0 ? this.store.getActiveSelectedProxyNode() : null;
  }

  private ruleGroupCandidates(): ProxyNodeItem[] {
    return this.revisionTick >= 0 ? this.store.getChainCandidates() : [];
  }

  private isShowingAllImportedNodes(): boolean {
    if (this.currentMode() === 'global') {
      return false;
    }
    if (this.nodeScopeMode === 'all') {
      return true;
    }
    if (this.nodeScopeMode === 'group') {
      return false;
    }
    return this.ruleGroupCandidates().length === 0 && this.allImportedNodes().length > 0;
  }

  private candidates(): ProxyNodeItem[] {
    const base: ProxyNodeItem[] = this.isShowingAllImportedNodes()
      ? this.allImportedNodes()
      : this.ruleGroupCandidates();
    const keyword: string = this.candidateSearch.trim().toLowerCase();
    if (keyword.length === 0) {
      return base;
    }
    return base.filter((node: ProxyNodeItem): boolean =>
      node.name.toLowerCase().includes(keyword) ||
      node.protocol.toLowerCase().includes(keyword) ||
      node.server.toLowerCase().includes(keyword)
    );
  }

  private nodeProtocolOf(nodeName: string): string {
    const found: ProxyNodeItem | null = this.revisionTick >= 0 ? this.store.getNodeByName(nodeName) : null;
    return found !== null ? found.protocol : 'Proxy';
  }

  private nodeDelayOf(nodeName: string): number {
    const found: ProxyNodeItem | null = this.revisionTick >= 0 ? this.store.getNodeByName(nodeName) : null;
    return found !== null ? found.delayMs : 0;
  }

  private nodeEndpointLabel(node: ProxyNodeItem): string {
    if (node.server.length > 0 && node.server !== 'local' && node.server !== 'mihomo' && node.port > 0) {
      return `${node.server}:${node.port}`;
    }
    return node.port > 0 ? `端口 ${node.port}` : '';
  }

  private chainRoleBadge(nodeName: string): string {
    const idx: number = this.chainNames.indexOf(nodeName);
    if (idx < 0) {
      return '';
    }
    if (idx === 0) {
      return '入口';
    }
    if (this.chainNames.length > 1 && idx === this.chainNames.length - 1) {
      return '出口';
    }
    return `第${idx + 1}跳`;
  }

  private isNodeActiveSelected(nodeName: string): boolean {
    const active: ProxyNodeItem | null = this.activeSelectedNode();
    return active !== null && active.name === nodeName;
  }

  private delayChipText(delayMs: number): string {
    if (delayMs < 0) {
      return '超时';
    }
    return `${delayMs} ms`;
  }

  private isFirstNode(nodeName: string): boolean {
    return this.chainNames.indexOf(nodeName) === 0;
  }

  private isLastNode(nodeName: string): boolean {
    const idx: number = this.chainNames.indexOf(nodeName);
    return this.chainNames.length > 1 && idx === this.chainNames.length - 1;
  }

  private moveNode(nodeName: string, delta: number): void {
    const index: number = this.chainNames.indexOf(nodeName);
    this.store.moveProxyChainNode(index, index + delta);
    this.chainMessage = '';
    this.chainMessageIsWarning = false;
    this.refreshDraft();
  }

  private addCandidateToChain(node: ProxyNodeItem): void {
    if (this.chainNames.includes(node.name)) {
      this.chainMessage = '该节点已在链式代理表中';
      this.chainMessageIsWarning = true;
      return;
    }
    const inRuleGroup: boolean = this.ruleGroupCandidates().some(
      (candidate: ProxyNodeItem): boolean => candidate.name === node.name
    );
    if (this.currentMode() === 'rule' && !inRuleGroup) {
      this.store.setOutboundMode('global');
      const err: string = this.store.addProxyChainNode(node.name);
      this.chainMessage = err.length > 0 ? err : `已切换为全局模式并添加节点：${node.name}`;
      this.chainMessageIsWarning = err.length > 0;
    } else {
      this.chainMessage = this.store.addProxyChainNode(node.name);
      this.chainMessageIsWarning = this.chainMessage.length > 0;
    }
    this.refreshDraft();
    this.showPreview = false;
  }

  private updatePreview(): void {
    const result: LexiChainBuildResult = this.store.buildProxyChainPreview();
    this.chainMessage = result.errorMessage;
    this.chainMessageIsWarning = result.errorMessage.length > 0;
    if (result.errorMessage.length === 0) {
      this.previewYaml = result.yamlContent;
      this.showPreview = !this.showPreview;
      this.showImportInChain = false;
    }
  }

  private async copyPreview(): Promise<void> {
    try {
      const result: LexiChainBuildResult = this.store.buildProxyChainPreview();
      if (result.errorMessage.length > 0) {
        this.chainMessage = result.errorMessage;
        this.chainMessageIsWarning = true;
        return;
      }
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, result.yamlContent)
      );
      this.chainMessage = '运行配置已复制';
      this.chainMessageIsWarning = false;
    } catch (error) {
      this.chainMessage = '复制失败：' + (error as Error).message;
      this.chainMessageIsWarning = true;
    }
  }

  private async handleConnectOrDisconnect(): Promise<void> {
    if (this.store.isChainConnecting) {
      return;
    }
    this.chainMessage = '';
    this.chainMessageIsWarning = false;
    const isDisconnecting: boolean = this.store.isProxyChainDraftApplied();
    const err: string = isDisconnecting
      ? await this.store.disconnectProxyChainAsync()
      : await this.store.connectProxyChainAsync();
    if (err.length > 0) {
      this.chainMessage = err;
      this.chainMessageIsWarning = true;
    } else {
      this.chainMessage = this.store.chainConnected
        ? `代理链已连接（${this.chainNames.join(' → ')}）`
        : '代理链已断开';
      this.chainMessageIsWarning = false;
    }
    this.refreshDraft();
  }

  private handleImportInChain(entries: ClashProxyEntry[], insertPosition: 'prepend' | 'append'): void {
    const profId: string = this.store.currentProfileId;
    if (profId.length === 0) {
      this.chainMessage = '请先添加配置文件';
      this.chainMessageIsWarning = true;
      return;
    }
    const err: string = this.store.importNodesToProfile(profId, insertPosition, entries);
    if (err.length > 0) {
      this.chainMessage = err;
      this.chainMessageIsWarning = true;
      return;
    }
    for (let i: number = 0; i < entries.length; i++) {
      const name: string = entries[i].name;
      if (!this.store.getProxyChainDraft().nodeNames.includes(name)) {
        if (insertPosition === 'prepend') {
          this.store.addProxyChainNode(name);
          const curLen: number = this.store.getProxyChainDraft().nodeNames.length;
          if (curLen > 1) {
            this.store.moveProxyChainNode(curLen - 1, 0);
          }
        } else {
          this.store.addProxyChainNode(name);
        }
      }
    }
    this.showImportInChain = false;
    this.chainMessage = `已导入并加入代理链：${entries.map((e: ClashProxyEntry): string => e.name).join('、')}`;
    this.chainMessageIsWarning = false;
    this.refreshDraft();
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        // Header bar matching clash-verge-rev ProxyChain (mode + clear)
        Row({ space: 6 }) {
          ForEach(['rule', 'global'], (mode: string) => {
            Button(mode === 'rule' ? '规则模式' : '全局模式')
              .fontSize(12)
              .fontColor(this.currentMode() === mode ? this.palette.onPrimary : this.palette.onSurface)
              .backgroundColor(this.currentMode() === mode ? this.palette.primary : this.palette.block)
              .height(34)
              .onClick((): void => {
                this.store.setOutboundMode(mode === 'rule' ? 'rule' : 'global');
                this.chainMessage = this.store.lastOperationError;
                this.chainMessageIsWarning = this.store.lastOperationError.length > 0;
                this.showPreview = false;
              })
          }, (mode: string): string => `${mode}_${this.currentMode()}`)

          Blank()

          if (this.chainNames.length > 0) {
            Button('删除链式配置')
              .fontSize(11)
              .height(34)
              .fontColor(this.palette.error)
              .backgroundColor(this.palette.errorContainer)
              .onClick((): void => {
                this.chainMessage = this.store.clearProxyChain();
                this.chainMessageIsWarning = this.chainMessage.length > 0;
                this.refreshDraft();
                this.showPreview = false;
              })
          }
        }
        .width('100%')

        // Currently selected imported profile & active node summary card
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Text('当前导入配置')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.primary)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.palette.primarySoft)
              .borderRadius(8)

            Text(this.currentProfile() !== null ? this.currentProfile()!.label : '未选择配置')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.currentProfile() !== null) {
              Text(this.currentProfile()!.sourceType === 'url' ? '订阅' : '本地')
                .fontSize(10)
                .fontColor(this.palette.onSurfaceVariant)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(this.palette.block)
                .borderRadius(6)
            }

            Text(`${this.allImportedNodes().length} 个节点`)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette.onSurfaceVariant)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.allProfiles().length > 1) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.allProfiles(), (prof: ProfileSubscriptionModel) => {
                  Text(prof.label)
                    .fontSize(11)
                    .fontWeight(this.currentProfile()?.id === prof.id ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.currentProfile()?.id === prof.id ? this.palette.onPrimary : this.palette.onSurface)
                    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                    .backgroundColor(this.currentProfile()?.id === prof.id ? this.palette.primary : this.palette.block)
                    .borderRadius(10)
                    .onClick((): void => {
                      this.store.selectProfile(prof.id);
                      this.chainMessage = this.store.lastOperationError;
                      this.chainMessageIsWarning = this.store.lastOperationError.length > 0;
                      this.nodeScopeMode = 'auto';
                      this.refreshDraft();
                      this.showPreview = false;
                    })
                }, (prof: ProfileSubscriptionModel): string => `${prof.id}_${this.currentProfile()?.id ?? ''}_${prof.proxiesCount}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .align(Alignment.Start)
            .width('100%')
          }

          Row({ space: 8 }) {
            Text('当前选中节点')
              .fontSize(11)
              .fontColor(this.palette.onSurfaceVariant)

            if (this.activeSelectedNode() !== null) {
              Column({ space: 2 }) {
                Text(this.activeSelectedNode()!.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette.onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Row({ space: 5 }) {
                  Text(this.activeSelectedNode()!.protocol)
                    .fontSize(10)
                    .fontColor(this.palette.onSurfaceVariant)
                  if (this.nodeEndpointLabel(this.activeSelectedNode()!).length > 0) {
                    Text(this.nodeEndpointLabel(this.activeSelectedNode()!))
                      .fontSize(10)
                      .fontColor(this.palette.onSurfaceVariant)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  if (this.activeSelectedNode()!.delayMs !== 0) {
                    Text(this.delayChipText(this.activeSelectedNode()!.delayMs))
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(ThemeManager.delayColor(this.activeSelectedNode()!.delayMs, this.palette))
                  }
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(this.chainNames.includes(this.activeSelectedNode()!.name) ? '已在链中' : '+ 加入链')
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.chainNames.includes(this.activeSelectedNode()!.name)
                  ? this.palette.onSurfaceVariant
                  : this.palette.primary)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(this.chainNames.includes(this.activeSelectedNode()!.name)
                  ? this.palette.block
                  : this.palette.primarySoft)
                .borderRadius(8)
                .onClick((): void => {
                  const active: ProxyNodeItem | null = this.activeSelectedNode();
                  if (active !== null) {
                    this.addCandidateToChain(active);
                  }
                })
            } else {
              Text('暂无可选择的代理节点，请先导入节点')
                .fontSize(11)
                .fontColor(this.palette.onSurfaceVariant)
                .layoutWeight(1)
            }
          }
          .width('100%')
          .padding({ left: 9, right: 9, top: 7, bottom: 7 })
          .backgroundColor(this.palette.block)
          .borderRadius(10)
          .alignItems(VerticalAlign.Center)
        }
        .padding(11)
        .width('100%')
        .backgroundColor(this.palette.card)
        .borderRadius(16)
        .border({ width: 1, color: this.palette.divider })

        // clash-verge-rev rule-group selector header (`代理规则 · Group (Type)`)
        if (this.currentMode() === 'rule') {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('代理规则')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurfaceVariant)
              if (this.selectedGroupItem() !== null) {
                Text(`${this.selectedGroupItem()!.name} (${this.selectedGroupItem()!.groupType})`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette.primary)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(this.palette.primarySoft)
                  .borderRadius(10)
              }
            }
            .width('100%')

            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.groups(), (group: ProxyGroupItem) => {
                  Button(group.name)
                    .fontSize(12)
                    .height(32)
                    .fontColor(this.targetGroupName() === group.name ? this.palette.onPrimary : this.palette.onSurface)
                    .backgroundColor(this.targetGroupName() === group.name ? this.palette.primary : this.palette.block)
                    .onClick((): void => {
                      this.chainMessage = this.store.setProxyChainGroup(group.name);
                      this.chainMessageIsWarning = this.chainMessage.length > 0;
                      this.nodeScopeMode = 'auto';
                      this.refreshDraft();
                      this.showPreview = false;
                    })
                }, (group: ProxyGroupItem): string => `${group.id}_${this.targetGroupName()}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .align(Alignment.Start)
            .width('100%')
          }
          .width('100%')
        }

        // clash-verge-rev chain warning / connecting / 1-node hint alert
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(14)
            .fontColor([this.chainNames.length === 1 ? this.palette.warn : this.palette.onSurfaceVariant])
          Text(this.chainNames.length === 1
            ? '链式代理至少需要 2 个节点，请再添加一个节点。'
            : (this.isConnecting()
              ? '正在应用链式代理配置并连接节点…'
              : ((this.isConnected() && !this.isConnecting())
                ? `代理链已连接 · 本机 → ${this.chainNames.join(' → ')} → 目标`
                : '链式代理会显著降低网速。按流量转发顺序依次点击下方节点添加到代理链中。')))
            .fontSize(11)
            .fontColor(this.chainNames.length === 1
              ? this.palette.onWarnContainer
              : ((this.isConnected() && !this.isConnecting()) ? this.palette.onOkContainer : this.palette.onSurfaceVariant))
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor(this.chainNames.length === 1
          ? this.palette.warnContainer
          : ((this.isConnected() && !this.isConnecting()) ? this.palette.okContainer : this.palette.block))
        .borderRadius(12)

        if (this.coreMissing()) {
          Text('尚未安装代理内核，可先编辑、保存和复制链式配置。')
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
            .width('100%')
        }

        // Chain sequence list with entry/exit role badges, protocol & latency chips, and downward hop arrows
        if (this.chainNames.length > 0) {
          List({ space: 0 }) {
            ForEach(this.chainNames, (nodeName: string) => {
              ListItem() {
                Column({ space: 0 }) {
                  Row({ space: 6 }) {
                    Text('≡')
                      .fontSize(16)
                      .fontColor(this.palette.onSurfaceVariant)

                    if (this.isFirstNode(nodeName)) {
                      Text('入口')
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onOkContainer)
                        .textAlign(TextAlign.Center)
                        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                        .backgroundColor(this.palette.okContainer)
                        .borderRadius(8)
                    } else if (this.isLastNode(nodeName)) {
                      Text('出口')
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onWarnContainer)
                        .textAlign(TextAlign.Center)
                        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                        .backgroundColor(this.palette.warnContainer)
                        .borderRadius(8)
                    } else {
                      Text(`${this.chainNames.indexOf(nodeName) + 1}`)
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onPrimary)
                        .textAlign(TextAlign.Center)
                        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                        .backgroundColor(this.palette.primary)
                        .borderRadius(8)
                    }

                    Column({ space: 2 }) {
                      Text(nodeName)
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onSurface)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 6 }) {
                        Text(this.nodeProtocolOf(nodeName))
                          .fontSize(10)
                          .fontColor(this.palette.onSurfaceVariant)
                          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                          .backgroundColor(this.palette.block)
                          .borderRadius(5)
                        if (this.nodeDelayOf(nodeName) !== 0) {
                          Text(this.delayChipText(this.nodeDelayOf(nodeName)))
                            .fontSize(10)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(ThemeManager.delayColor(this.nodeDelayOf(nodeName), this.palette))
                        }
                      }
                      .alignItems(VerticalAlign.Center)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Button({ type: ButtonType.Circle }) {
                      SymbolGlyph($r('sys.symbol.chevron_up'))
                        .fontSize(15)
                        .fontColor([this.chainNames.indexOf(nodeName) > 0
                          ? this.palette.onSurface
                          : this.palette.onSurfaceVariant])
                    }
                    .height(28)
                    .width(28)
                    .padding(0)
                    .backgroundColor(this.palette.block)
                    .accessibilityText('上移 ' + nodeName)
                    .enabled(this.chainNames.indexOf(nodeName) > 0)
                    .onClick((): void => {
                      this.moveNode(nodeName, -1);
                      this.showPreview = false;
                    })

                    Button({ type: ButtonType.Circle }) {
                      SymbolGlyph($r('sys.symbol.chevron_down'))
                        .fontSize(15)
                        .fontColor([this.chainNames.indexOf(nodeName) < this.chainNames.length - 1
                          ? this.palette.onSurface
                          : this.palette.onSurfaceVariant])
                    }
                    .height(28)
                    .width(28)
                    .padding(0)
                    .backgroundColor(this.palette.block)
                    .accessibilityText('下移 ' + nodeName)
                    .enabled(this.chainNames.indexOf(nodeName) < this.chainNames.length - 1)
                    .onClick((): void => {
                      this.moveNode(nodeName, 1);
                      this.showPreview = false;
                    })

                    Button({ type: ButtonType.Circle }) {
                      SymbolGlyph($r('sys.symbol.xmark'))
                        .fontSize(13)
                        .fontColor([this.palette.error])
                    }
                    .height(28)
                    .width(28)
                    .padding(0)
                    .backgroundColor(this.palette.errorContainer)
                    .accessibilityText('移除 ' + nodeName)
                    .onClick((): void => {
                      this.store.removeProxyChainNode(nodeName);
                      this.refreshDraft();
                      this.showPreview = false;
                    })
                  }
                  .alignItems(VerticalAlign.Center)
                  .padding(10)
                  .width('100%')
                  .backgroundColor(this.palette.card)
                  .borderRadius(14)
                  .border({
                    width: this.isFirstNode(nodeName) || this.isLastNode(nodeName) ? 1.5 : 1,
                    color: this.isFirstNode(nodeName)
                      ? this.palette.ok
                      : (this.isLastNode(nodeName) ? this.palette.warn : this.palette.divider)
                  })

                  if (this.chainNames.indexOf(nodeName) < this.chainNames.length - 1) {
                    Row() {
                      SymbolGlyph($r('sys.symbol.arrow_down'))
                        .fontSize(14)
                        .fontColor([this.palette.primary])
                    }
                    .width('100%')
                    .height(20)
                    .justifyContent(FlexAlign.Center)
                  }
                }
                .width('100%')
              }
            }, (nodeName: string): string => `${nodeName}_${this.chainNames.indexOf(nodeName)}_${this.chainNames.length}_${this.nodeDelayOf(nodeName)}`)
              .onMove((from: number, to: number): void => {
                this.store.moveProxyChainNode(from, to);
                this.refreshDraft();
                this.showPreview = false;
              })
          }
          .nestedScroll({
            scrollForward: NestedScrollMode.PARENT_FIRST,
            scrollBackward: NestedScrollMode.SELF_FIRST
          })
          .height(Math.min(220, this.chainNames.length * 76))
          .width('100%')
        } else {
          Column({ space: 8 }) {
            Text('点击下方导入的配置节点依次添加，至少需要 2 个节点（例如：机场节点 → SOCKS5 落地）')
              .fontSize(12)
              .fontColor(this.palette.onSurfaceVariant)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(this.palette.card)
          .borderRadius(16)
        }

        // Action row: Connect / Disconnect / Apply + Preview + Copy + Import SOCKS5/URI
        Row({ space: 6 }) {
          Button(this.isConnecting()
            ? '连接中...'
            : (this.isDraftApplied() ? '断开连接' : (this.isConnected() ? '应用修改' : '连接')))
            .id('chain-connect')
            .fontSize(12)
            .height(38)
            .layoutWeight(1.4)
            .fontColor(this.palette.onPrimary)
            .backgroundColor(this.isDraftApplied() ? this.palette.error : this.palette.primary)
            .enabled(!this.isConnecting() && (this.isDraftApplied() || this.validationError().length === 0))
            .onClick((): void => {
              this.handleConnectOrDisconnect();
            })

          Button(this.showImportInChain ? '收起导入' : '+ 导入节点')
            .fontSize(11)
            .height(38)
            .backgroundColor(this.showImportInChain ? this.palette.primarySoft : this.palette.block)
            .fontColor(this.showImportInChain ? this.palette.primary : this.palette.onSurface)
            .onClick((): void => {
              this.showImportInChain = !this.showImportInChain;
              if (this.showImportInChain) {
                this.showPreview = false;
              }
            })

          Button('预览')
            .fontSize(11)
            .height(38)
            .backgroundColor(this.palette.block)
            .fontColor(this.palette.onSurface)
            .onClick((): void => {
              this.updatePreview();
            })

          Button('复制')
            .fontSize(11)
            .height(38)
            .backgroundColor(this.palette.block)
            .fontColor(this.palette.onSurface)
            .onClick((): void => {
              this.copyPreview();
            })
        }
        .width('100%')

        if (this.chainMessage.length > 0) {
          Text(this.chainMessage)
            .fontSize(11)
            .fontColor(this.chainMessageIsWarning ? this.palette.error : this.palette.primary)
            .width('100%')
        } else if (this.validationError().length > 0) {
          Text(this.validationError())
            .fontSize(11)
            .fontColor(this.palette.onSurfaceVariant)
            .width('100%')
        }

        if (this.showImportInChain) {
          Column() {
            NodeImportPanel({
              palette: this.palette,
              singleButtonMode: false,
              onImportEntries: (entries: ClashProxyEntry[], insertPosition: 'prepend' | 'append'): void => {
                this.handleImportInChain(entries, insertPosition);
              }
            })
          }
          .padding(14)
          .backgroundColor(this.palette.card)
          .borderRadius(18)
          .width('100%')
        } else if (this.showPreview) {
          Column() {
            Text(this.previewYaml)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor(this.palette.onSurface)
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
          .width('100%')
          .backgroundColor(this.palette.card)
          .padding(12)
          .borderRadius(16)
        } else {
          // Clearly labeled section showing nodes from the currently selected imported profile
          Row({ space: 6 }) {
            Text(`当前配置节点 (${this.candidates().length})`)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
              .layoutWeight(1)

            if (this.currentMode() === 'rule' && this.allImportedNodes().length > 0) {
              Text(`策略组 (${this.ruleGroupCandidates().length})`)
                .fontSize(11)
                .fontWeight(!this.isShowingAllImportedNodes() ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(!this.isShowingAllImportedNodes() ? this.palette.onPrimary : this.palette.onSurfaceVariant)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(!this.isShowingAllImportedNodes() ? this.palette.primary : this.palette.block)
                .borderRadius(8)
                .onClick((): void => {
                  this.nodeScopeMode = 'group';
                })

              Text(`全部导入 (${this.allImportedNodes().length})`)
                .fontSize(11)
                .fontWeight(this.isShowingAllImportedNodes() ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.isShowingAllImportedNodes() ? this.palette.onPrimary : this.palette.onSurfaceVariant)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(this.isShowingAllImportedNodes() ? this.palette.primary : this.palette.block)
                .borderRadius(8)
                .onClick((): void => {
                  this.nodeScopeMode = 'all';
                })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.currentMode() === 'rule' && this.isShowingAllImportedNodes() && this.ruleGroupCandidates().length === 0) {
            Text('当前策略组仅包含子分组，以下已显示当前配置全部导入节点；点击添加将自动切至全局模式。')
              .fontSize(11)
              .fontColor(this.palette.onSurfaceVariant)
              .width('100%')
          }

          TextInput({ text: this.candidateSearch, placeholder: '搜索当前配置节点 (名称 / 协议 / 地址)' })
            .height(38)
            .fontSize(12)
            .fontColor(this.palette.onSurface)
            .placeholderColor(this.palette.onSurfaceVariant)
            .backgroundColor(this.palette.card)
            .onChange((keyword: string): void => {
              this.candidateSearch = keyword;
            })

          if (this.candidates().length === 0) {
            Column({ space: 6 }) {
              Text(this.allImportedNodes().length === 0
                ? '当前配置中暂无导入节点，可点击上方“+ 导入节点”快速添加'
                : '当前筛选条件下没有匹配的节点')
                .fontSize(12)
                .fontColor(this.palette.onSurfaceVariant)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.palette.card)
            .borderRadius(16)
          } else {
            Column({ space: 6 }) {
              ForEach(this.candidates(), (node: ProxyNodeItem) => {
                Row({ space: 8 }) {
                  Column({ space: 4 }) {
                    Text(node.name)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.palette.onSurface)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')

                    Row({ space: 6 }) {
                      Text(node.protocol)
                        .fontSize(10)
                        .fontColor(this.palette.onSurfaceVariant)
                        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                        .backgroundColor(this.palette.block)
                        .borderRadius(5)
                      if (this.nodeEndpointLabel(node).length > 0) {
                        Text(this.nodeEndpointLabel(node))
                          .fontSize(10)
                          .fontColor(this.palette.onSurfaceVariant)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      if (node.delayMs !== 0) {
                        Text(this.delayChipText(node.delayMs))
                          .fontSize(10)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(ThemeManager.delayColor(node.delayMs, this.palette))
                      }
                    }
                    .alignItems(VerticalAlign.Center)
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Row({ space: 6 }) {
                    if (this.isNodeActiveSelected(node.name)) {
                      Text('当前选中')
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.primary)
                        .textAlign(TextAlign.Center)
                        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                        .backgroundColor(this.palette.primarySoft)
                        .borderRadius(8)
                    }

                    if (this.chainRoleBadge(node.name).length > 0) {
                      Text(this.chainRoleBadge(node.name))
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.chainRoleBadge(node.name) === '入口'
                          ? this.palette.onOkContainer
                          : (this.chainRoleBadge(node.name) === '出口'
                            ? this.palette.onWarnContainer
                            : this.palette.onPrimary))
                        .textAlign(TextAlign.Center)
                        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                        .backgroundColor(this.chainRoleBadge(node.name) === '入口'
                          ? this.palette.okContainer
                          : (this.chainRoleBadge(node.name) === '出口'
                            ? this.palette.warnContainer
                            : this.palette.primary))
                        .borderRadius(8)
                    }

                    Text(this.chainNames.includes(node.name) ? '已在链中' : '+ 添加')
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.chainNames.includes(node.name) ? this.palette.onSurfaceVariant : this.palette.primary)
                  }
                  .alignItems(VerticalAlign.Center)
                }
                .alignItems(VerticalAlign.Center)
                .padding(12)
                .width('100%')
                .backgroundColor(this.palette.card)
                .borderRadius(16)
                .border({
                  width: this.isNodeActiveSelected(node.name) ? 1.2 : 1,
                  color: this.isNodeActiveSelected(node.name) ? this.palette.primary : this.palette.divider
                })
                .onClick((): void => {
                  this.addCandidateToChain(node);
                })
              }, (node: ProxyNodeItem): string => `${node.id}_${this.chainNames.includes(node.name)}_${this.chainRoleBadge(node.name)}_${this.isNodeActiveSelected(node.name)}_${node.delayMs}`)
            }
            .width('100%')
          }
        }
      }
      .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.windowWidthVp) })
      .padding({
        left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
        right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
        bottom: ResponsiveLayout.bottomContentPadding(this.windowWidthVp, this.bottomInset)
      })
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }
}

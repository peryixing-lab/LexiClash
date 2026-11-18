import { ImmersiveTitleStyle } from '../common/ImmersiveTitleStyle';
// ProxiesComponents.ets — Mobile FlClash Proxies View with Dedicated Reactive Node Cards & Node Selection

import { ImmersiveNavDestination, ImmersiveTitlePage } from './ImmersiveTitlePage';
import { BackNavigationCoordinator, ImmersiveBackButton, ImmersivePageTransition } from './ImmersiveBackButton';
import { ResponsiveLayout } from '../common/ResponsiveLayout';
import { FlClashColorPalette, I18n, ThemeManager } from '../common/ThemeManager';
import {
  ProxiesSortKind,
  ProxiesViewStyle,
  ProxyGroupItem,
  ProxyNodeItem
} from '../core/CoreProtocol';
import { YamlProfileParser } from '../core/YamlProfileParser';
import { ClashProxyEntry } from '../core/ClashUriParser';
import { AppStateStore } from '../store/AppStateStore';
import { NodeImportPanel } from './NodeImportPanel';
import { ProxyChainPanel } from './ProxyChainPanel';

@Component
export struct ProxyNodeCardItem {
  @Prop nodeName: string = '';
  @Prop nodeProtocol: string = 'Proxy';
  @Prop nodeRegion: string = 'GL';
  @Prop nodeDelayMs: number = 0;
  @Prop nodeIsTesting: boolean = false;
  @Prop isSelected: boolean = false;
  @Prop isCompactCard: boolean = false;
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  onSelectNode: (nodeName: string) => void = (_nodeName: string): void => {};
  onTestNodeDelay: (nodeName: string) => void = (_nodeName: string): void => {};

  private getRegionFlag(code: string): string {
    if (code === 'US') return '🇺🇸';
    if (code === 'HK') return '🇭🇰';
    if (code === 'SG') return '🇸🇬';
    if (code === 'JP') return '🇯🇵';
    if (code === 'TW') return '🇹🇼';
    if (code === 'DE') return '🇩🇪';
    if (code === 'UK') return '🇬🇧';
    if (code === 'KR') return '🇰🇷';
    if (code === 'CN') return '🇨🇳';
    return '🌐';
  }

  private hasFlagEmoji(name: string): boolean {
    return name.includes('🇺🇸') || name.includes('🇭🇰') || name.includes('🇸🇬') ||
      name.includes('🇯🇵') || name.includes('🇹🇼') || name.includes('🇩🇪') ||
      name.includes('🇬🇧') || name.includes('🇰🇷') || name.includes('🇨🇳');
  }

  private getDelayText(): string {
    if (this.nodeIsTesting) {
      return '...';
    }
    if (this.nodeDelayMs < 0) {
      return 'Timeout';
    }
    if (this.nodeDelayMs === 0) {
      return '测速';
    }
    return `${this.nodeDelayMs} ms`;
  }

  build() {
    Column({ space: this.isCompactCard ? 6 : 10 }) {
      Row({ space: 8 }) {
        if (!this.hasFlagEmoji(this.nodeName)) {
          Text(this.getRegionFlag(this.nodeRegion))
            .fontSize(15)
        }

        Text(this.nodeName)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isSelected ? this.palette.primary : this.palette.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.isSelected) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(12)
              .fontColor([this.palette.onPrimary])
          }
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor(this.palette.primary)
        } else {
          Column()
            .width(22)
            .height(22)
            .borderRadius(11)
            .border({ width: 1.5, color: this.palette.inset })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        Text(this.nodeProtocol)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.onSurfaceVariant)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor(this.palette.block)
          .borderRadius(8)

        Blank()

        Row({ space: 4 }) {
          if (this.nodeDelayMs > 0 || this.nodeDelayMs < 0) {
            Circle({ width: 6, height: 6 })
              .fill(ThemeManager.delayColor(this.nodeDelayMs, this.palette))
          }
          Text(this.getDelayText())
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeManager.delayColor(this.nodeDelayMs, this.palette))
        }
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .backgroundColor(this.palette.block)
        .borderRadius(10)
        .onClick((): void => {
          this.onTestNodeDelay(this.nodeName);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.palette.card)
    .borderRadius(22)
    .border({
      width: this.isSelected ? 1.5 : 0,
      color: this.isSelected ? this.palette.primary : Color.Transparent
    })
    .onClick((): void => {
      this.onSelectNode(this.nodeName);
    })
  }
}

@Component
export struct ProxyGroupChipItem {
  @Prop groupId: string = '';
  @Prop groupName: string = '';
  @Prop groupType: string = '';
  @Prop isSelected: boolean = false;
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  onSelectGroup: (groupId: string) => void = (_groupId: string): void => {};

  build() {
    Row({ space: 6 }) {
      Text(this.groupName)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isSelected ? this.palette.onPrimary : this.palette.onSurface)
      Text(this.groupType)
        .fontSize(10)
        .fontColor(this.isSelected ? this.palette.onPrimary : this.palette.onSurfaceVariant)
        .opacity(0.85)
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(this.isSelected ? this.palette.primary : this.palette.card)
    .borderRadius(18)
    .onClick((): void => {
      this.onSelectGroup(this.groupId);
    })
  }
}

@Component
export struct ProxyGroupListCard {
  @Prop groupId: string = '';
  @Prop groupName: string = '';
  @Prop groupType: string = '';
  @Prop iconText: string = 'P';
  @Prop selectedNodeName: string = '';
  @Prop isExpanded: boolean = false;
  @Prop searchKeyword: string = '';
  @Prop proxiesSortKind: ProxiesSortKind = 'none';
  @Prop hideTimeoutProxies: boolean = false;
  @Prop isCompactCard: boolean = false;
  @Prop revisionTick: number = 0;
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  onToggleExpand: (groupId: string) => void = (_groupId: string): void => {};
  onSelectNode: (groupId: string, nodeName: string) => void = (_groupId: string, _nodeName: string): void => {};
  onTestNodeDelay: (nodeName: string) => void = (_nodeName: string): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

  private getFilteredNodes(): ProxyNodeItem[] {
    const _tick: number = this.revisionTick;
    const grp: ProxyGroupItem | null = _tick >= 0 ? this.store.getGroupById(this.groupId) : null;
    if (grp === null) {
      return [];
    }
    const result: ProxyNodeItem[] = [];
    const kw: string = this.searchKeyword.trim().toLowerCase();
    for (let i = 0; i < grp.nodeNames.length; i++) {
      const memberName: string = grp.nodeNames[i];
      let node: ProxyNodeItem | null = this.store.getNodeByName(memberName);
      if (node === null) {
        node = {
          id: `node_${grp.id}_${i}_${memberName}`,
          name: memberName,
          protocol: memberName === 'DIRECT' || memberName === 'REJECT' ? memberName : 'Group',
          regionCode: YamlProfileParser.inferRegionFromName(memberName),
          server: '',
          port: 0,
          udp: true,
          delayMs: 0,
          isTesting: false,
          providerName: 'Profile'
        };
      }
      if (this.hideTimeoutProxies && node.delayMs < 0) {
        continue;
      }
      if (kw.length > 0 && !node.name.toLowerCase().includes(kw) && !node.protocol.toLowerCase().includes(kw)) {
        continue;
      }
      result.push(node);
    }
    if (this.proxiesSortKind === 'delay') {
      result.sort((a: ProxyNodeItem, b: ProxyNodeItem): number => {
        const da: number = a.delayMs <= 0 ? 999999 : a.delayMs;
        const db: number = b.delayMs <= 0 ? 999999 : b.delayMs;
        return da - db;
      });
    } else if (this.proxiesSortKind === 'name') {
      result.sort((a: ProxyNodeItem, b: ProxyNodeItem): number => a.name.localeCompare(b.name));
    }
    return result;
  }

  private getActiveSelectedName(): string {
    const _tick: number = this.revisionTick;
    const grp: ProxyGroupItem | null = _tick >= 0 ? this.store.getGroupById(this.groupId) : null;
    return grp !== null ? grp.selectedName : this.selectedNodeName;
  }

  private getNodeDelay(node: ProxyNodeItem): number {
    const _tick: number = this.revisionTick;
    const fresh: ProxyNodeItem | null = _tick >= 0 ? this.store.getNodeByName(node.name) : null;
    return fresh !== null ? fresh.delayMs : node.delayMs;
  }

  private getNodeIsTesting(node: ProxyNodeItem): boolean {
    const _tick: number = this.revisionTick;
    const fresh: ProxyNodeItem | null = _tick >= 0 ? this.store.getNodeByName(node.name) : null;
    return fresh !== null ? fresh.isTesting : node.isTesting;
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Center }) {
          Text(this.iconText)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.primary)
        }
        .width(36)
        .height(36)
        .borderRadius(12)
        .backgroundColor(this.palette.primarySoft)

        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.groupName)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
            Text(this.groupType)
              .fontSize(11)
              .fontColor(this.palette.onSurfaceVariant)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.palette.block)
              .borderRadius(8)
          }
          Text(this.getActiveSelectedName())
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.primary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph(this.isExpanded
          ? $r('sys.symbol.chevron_up')
          : $r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([this.palette.onSurfaceVariant])
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.palette.card)
      .borderRadius(24)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.onToggleExpand(this.groupId);
      })

      if (this.isExpanded) {
        if (this.getFilteredNodes().length === 0) {
          Text(this.store.localeLang === 'en_US' ? 'No matching nodes' : '没有匹配的节点')
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 14, bottom: 14 })
        } else {
          Grid() {
            ForEach(
              this.getFilteredNodes(),
              (node: ProxyNodeItem) => {
                GridItem() {
                  ProxyNodeCardItem({
                    nodeName: node.name,
                    nodeProtocol: node.protocol,
                    nodeRegion: node.regionCode,
                    nodeDelayMs: this.getNodeDelay(node),
                    nodeIsTesting: this.getNodeIsTesting(node),
                    isSelected: this.getActiveSelectedName() === node.name,
                    isCompactCard: this.isCompactCard,
                    palette: this.palette,
                    onSelectNode: (targetName: string): void => {
                      this.onSelectNode(this.groupId, targetName);
                    },
                    onTestNodeDelay: (targetName: string): void => {
                      this.onTestNodeDelay(targetName);
                    }
                  })
                }
              },
              (node: ProxyNodeItem): string => `${this.groupId}_${node.id}`
            )
          }
          .columnsTemplate(ResponsiveLayout.proxyColumnsTemplate(this.windowWidthVp))
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')
        }
      }
    }
    .width('100%')
  }
}

@Component
export struct ProxiesMainView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop @Watch('onExternalRevision') revisionTick: number = 0;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  onGoAddProfile: () => void = (): void => {};

  @State localTick: number = 0;
  @State selectedGroupIdState: string = '';
  @State selectedNodeNameState: string = '';
  @State searchKeyword: string = '';
  @State showSearchBar: boolean = false;
  @State showStylePanel: boolean = false;
  @State showAddNodePanel: boolean = false;
  @State expandedGroupIds: string[] = [];
  @State @Watch('onChainPanelStateChange') showChainPanel: boolean = false;

  private proxiesNavStack: NavPathStack = new NavPathStack();
  private lastStoreGroupId: string = '';
  private store: AppStateStore = AppStateStore.getInstance();
  private storeListener: () => void = (): void => {
    this.syncStateFromStore();
  };

  aboutToAppear(): void {
    this.store.subscribe(this.storeListener);
    this.syncStateFromStore();
    BackNavigationCoordinator.register('proxies', (): boolean => {
      if (this.showChainPanel) {
        if (BackNavigationCoordinator.dispatch('chainModal')) {
          return true;
        }
        this.exitChainMode();
        return true;
      }
      if (this.showAddNodePanel) {
        this.showAddNodePanel = false;
        return true;
      }
      if (this.showStylePanel) {
        this.showStylePanel = false;
        return true;
      }
      if (this.showSearchBar) {
        this.showSearchBar = false;
        this.searchKeyword = '';
        return true;
      }
      return false;
    });
  }

  aboutToDisappear(): void {
    this.store.unsubscribe(this.storeListener);
    BackNavigationCoordinator.unregister('proxies');
  }

  onExternalRevision(): void {
    this.syncStateFromStore();
  }

  onChainPanelStateChange(): void {
    if (this.showChainPanel) {
      ImmersivePageTransition.push(this.proxiesNavStack, 'chain');
    } else {
      ImmersivePageTransition.clear(this.proxiesNavStack);
    }
  }

  private syncStateFromStore(): void {
    const validIds: string[] = this.store.proxyGroups.map((g: ProxyGroupItem): string => g.id);
    const prunedExpanded: string[] = this.expandedGroupIds.filter((id: string): boolean => validIds.includes(id));

    const storeChangedGroup: boolean = this.store.currentGroupId !== this.lastStoreGroupId;
    this.lastStoreGroupId = this.store.currentGroupId;

    let targetId: string = storeChangedGroup ? this.store.currentGroupId : this.selectedGroupIdState;
    if (targetId.length === 0 || !validIds.includes(targetId)) {
      targetId = this.store.currentGroupId;
    }
    let grp: ProxyGroupItem | null = targetId.length > 0 ? this.store.getGroupById(targetId) : null;
    if (grp === null && this.store.proxyGroups.length > 0) {
      grp = this.store.proxyGroups[0];
    }

    if (grp !== null) {
      this.selectedGroupIdState = grp.id;
      this.selectedNodeNameState = grp.selectedName;
      if (this.store.currentGroupId !== grp.id) {
        this.store.currentGroupId = grp.id;
        this.lastStoreGroupId = grp.id;
      }
      if (prunedExpanded.length === 0) {
        this.expandedGroupIds = [grp.id];
      } else if (storeChangedGroup && !prunedExpanded.includes(grp.id)) {
        const nextExpanded: string[] = prunedExpanded.slice();
        nextExpanded.push(grp.id);
        this.expandedGroupIds = nextExpanded;
      } else {
        this.expandedGroupIds = prunedExpanded;
      }
    } else {
      this.selectedGroupIdState = '';
      this.selectedNodeNameState = '';
      this.expandedGroupIds = [];
    }
    this.localTick += 1;
  }

  private hasActiveGroups(): boolean {
    const _tick: number = this.localTick + this.revisionTick + this.selectedGroupIdState.length + this.selectedNodeNameState.length;
    return _tick >= 0 && this.store.proxyGroups.length > 0 && this.getCurrentGroup() !== null;
  }

  private getCurrentGroup(): ProxyGroupItem | null {
    const _tick: number = this.localTick + this.revisionTick + this.selectedNodeNameState.length;
    if (_tick < 0) {
      return null;
    }
    const targetId: string = this.selectedGroupIdState.length > 0 ? this.selectedGroupIdState : this.store.currentGroupId;
    const found: ProxyGroupItem | null = targetId.length > 0 ? this.store.getGroupById(targetId) : null;
    if (found !== null) {
      return found;
    }
    return this.store.proxyGroups.length > 0 ? this.store.proxyGroups[0] : null;
  }

  private getProxyGroupsReactive(): ProxyGroupItem[] {
    const _tick: number = this.localTick + this.revisionTick + this.selectedGroupIdState.length + this.selectedNodeNameState.length;
    return _tick >= 0 ? this.store.proxyGroups : [];
  }

  private isTabViewStyle(): boolean {
    const _tick: number = this.localTick + this.revisionTick;
    return _tick >= 0 && this.store.proxiesViewStyle === 'tab';
  }

  private isNodeSelectedInGroup(grp: ProxyGroupItem, nodeName: string): boolean {
    const _tick: number = this.localTick + this.revisionTick + this.selectedGroupIdState.length + this.selectedNodeNameState.length;
    const freshGrp: ProxyGroupItem | null = this.store.getGroupById(grp.id);
    const activeSelected: string = freshGrp !== null ? freshGrp.selectedName : grp.selectedName;
    return _tick >= 0 && activeSelected === nodeName;
  }

  private getGroupSelectedName(grp: ProxyGroupItem): string {
    const _tick: number = this.localTick + this.revisionTick + this.selectedNodeNameState.length;
    const freshGrp: ProxyGroupItem | null = this.store.getGroupById(grp.id);
    return _tick >= 0 && freshGrp !== null ? freshGrp.selectedName : grp.selectedName;
  }

  private getNodeDelay(node: ProxyNodeItem): number {
    const _tick: number = this.localTick + this.revisionTick;
    const fresh: ProxyNodeItem | null = this.store.getNodeByName(node.name);
    return _tick >= 0 && fresh !== null ? fresh.delayMs : node.delayMs;
  }

  private getNodeIsTesting(node: ProxyNodeItem): boolean {
    const _tick: number = this.localTick + this.revisionTick;
    const fresh: ProxyNodeItem | null = this.store.getNodeByName(node.name);
    return _tick >= 0 && fresh !== null ? fresh.isTesting : node.isTesting;
  }

  private handleSelectNode(group: ProxyGroupItem, nodeName: string): void {
    this.store.selectProxyInGroup(group.id, nodeName);
    if (this.store.lastOperationError.length > 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: this.store.lastOperationError, duration: 2500 });
      } catch (e) {
        // ignore
      }
      return;
    }
    this.selectedGroupIdState = group.id;
    this.selectedNodeNameState = nodeName;
    this.localTick += 1;
    try {
      this.getUIContext().getPromptAction().showToast({
        message: `${group.name} → ${nodeName}`,
        duration: 1200
      });
    } catch (e) {
      // ignore
    }
  }

  private handleImportQuickNodes(entries: ClashProxyEntry[], insertPosition: 'prepend' | 'append'): void {
    const profileId: string = this.store.currentProfileId;
    if (profileId.length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '请先添加配置', duration: 2000 });
      } catch (_toastErr) {
        // ignore
      }
      return;
    }
    const err: string = this.store.importNodesToProfile(profileId, insertPosition, entries);
    if (err.length > 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: err, duration: 2800 });
      } catch (_toastErr) {
        // ignore
      }
      return;
    }
    this.showAddNodePanel = false;
    this.syncStateFromStore();
    try {
      const posLabel: string = insertPosition === 'prepend' ? '前置' : '后置';
      this.getUIContext().getPromptAction().showToast({
        message: `已添加 ${entries.length} 个${posLabel}节点`,
        duration: 1800
      });
    } catch (_toastErr) {
      // ignore
    }
  }

  private openChainModeWithConfirm(): void {
    if (this.store.chainWarningAcknowledged) {
      this.showChainPanel = true;
      return;
    }
    try {
      this.getUIContext().showAlertDialog({
        title: '链式代理',
        message: '链式代理会显著降低网速。如果您没有明确的业务需求，或不了解此项配置，请保持关闭。',
        primaryButton: {
          value: '保持关闭',
          action: (): void => {}
        },
        secondaryButton: {
          value: '我明白，开启',
          action: (): void => {
            this.store.setChainWarningAcknowledged(true);
            this.showChainPanel = true;
          }
        }
      });
    } catch (_dialogErr) {
      this.store.setChainWarningAcknowledged(true);
      this.showChainPanel = true;
    }
  }

  private async exitChainMode(): Promise<void> {
    if (this.store.chainConnected) {
      if (this.store.vpnEnabled) {
        await this.store.disconnectProxyChainAsync();
      } else {
        this.store.disconnectProxyChain();
      }
    }
    this.showChainPanel = false;
  }

  private getFilteredNodesForGroup(group: ProxyGroupItem): ProxyNodeItem[] {
    const _tick: number = this.localTick + this.revisionTick + this.selectedGroupIdState.length + this.selectedNodeNameState.length;
    const freshGroup: ProxyGroupItem = (_tick >= 0 ? this.store.getGroupById(group.id) : null) ?? group;
    const result: ProxyNodeItem[] = [];
    const kw: string = this.searchKeyword.trim().toLowerCase();
    for (let i = 0; i < freshGroup.nodeNames.length; i++) {
      const memberName: string = freshGroup.nodeNames[i];
      let node: ProxyNodeItem | null = this.store.getNodeByName(memberName);
      if (node === null) {
        // Might be another group referenced inside this group (e.g. Auto / Fallback / DIRECT)
        node = {
          id: `node_${freshGroup.id}_${i}_${memberName}`,
          name: memberName,
          protocol: memberName === 'DIRECT' || memberName === 'REJECT' ? memberName : 'Group',
          regionCode: YamlProfileParser.inferRegionFromName(memberName),
          server: '',
          port: 0,
          udp: true,
          delayMs: 0,
          isTesting: false,
          providerName: 'Profile'
        };
      }
      if (this.store.hideTimeoutProxies && node.delayMs < 0) {
        continue;
      }
      if (kw.length > 0 && !node.name.toLowerCase().includes(kw) && !node.protocol.toLowerCase().includes(kw)) {
        continue;
      }
      result.push(node);
    }

    if (this.store.proxiesSortKind === 'delay') {
      result.sort((a: ProxyNodeItem, b: ProxyNodeItem): number => {
        const da: number = a.delayMs <= 0 ? 999999 : a.delayMs;
        const db: number = b.delayMs <= 0 ? 999999 : b.delayMs;
        return da - db;
      });
    } else if (this.store.proxiesSortKind === 'name') {
      result.sort((a: ProxyNodeItem, b: ProxyNodeItem): number => a.name.localeCompare(b.name));
    }

    return result;
  }

  private isGroupExpanded(groupId: string): boolean {
    return this.expandedGroupIds.includes(groupId);
  }

  private toggleGroupExpand(groupId: string): void {
    const idx: number = this.expandedGroupIds.indexOf(groupId);
    if (idx >= 0) {
      const next: string[] = [];
      for (let i = 0; i < this.expandedGroupIds.length; i++) {
        if (this.expandedGroupIds[i] !== groupId) {
          next.push(this.expandedGroupIds[i]);
        }
      }
      this.expandedGroupIds = next;
    } else {
      const nextAdd: string[] = this.expandedGroupIds.slice();
      nextAdd.push(groupId);
      this.expandedGroupIds = nextAdd;
    }
  }

  @Builder
  mainHeader() {
    Row({ space: 10 }) {
      Text(I18n.t('proxies', this.store.localeLang))
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .layoutWeight(1)

      if (this.hasActiveGroups() || this.store.profiles.length > 0) {
        Button('链式')
          .id('open-proxy-chain')
          .fontSize(12).height(34).fontColor(this.palette.primary).backgroundColor(this.palette.primarySoft)
          .onClick((): void => { this.openChainModeWithConfirm(); })
        if (this.getCurrentGroup() !== null) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.bolt_fill'))
              .fontSize(15)
              .fontColor([this.palette.primary])
              .rotate({ angle: this.getCurrentGroup()!.isTestingGroup ? 360 : 0 })
              .animation({ duration: 500, curve: Curve.EaseInOut })
            Text(this.getCurrentGroup()!.isTestingGroup
              ? (this.store.localeLang === 'en_US' ? 'Testing...' : '测速中')
              : (this.store.localeLang === 'en_US' ? 'Test' : '测速'))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.primary)
          }
          .height(34)
          .padding({ left: 12, right: 12 })
          .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, true))
          .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, true))
          .borderRadius(17)
          .onClick((): void => {
            const grp: ProxyGroupItem | null = this.getCurrentGroup();
            if (grp !== null) {
              this.store.testGroupDelays(grp.id);
            }
          })
        }

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(16)
            .fontColor([this.showAddNodePanel ? this.palette.primary : this.palette.onSurface])
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, false))
        .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, false))
        .onClick((): void => {
          this.showAddNodePanel = !this.showAddNodePanel;
        })

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([this.showSearchBar ? this.palette.primary : this.palette.onSurface])
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, false))
        .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, false))
        .onClick((): void => {
          this.showSearchBar = !this.showSearchBar;
          if (!this.showSearchBar) {
            this.searchKeyword = '';
          }
        })

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
            .fontSize(16)
            .fontColor([this.showStylePanel ? this.palette.primary : this.palette.onSurface])
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, false))
        .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, false))
        .onClick((): void => {
          this.showStylePanel = !this.showStylePanel;
        })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  chainHeader() {
    Row({ space: 10 }) {
      ImmersiveBackButton({
        palette: this.palette,
        immersiveEnabled: this.store.liquidGlass,
        onBack: (): void => {
          this.exitChainMode();
        }
      })

      Text('链式代理模式')
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
  chainBody() {
    Column() {
      ProxyChainPanel({
        palette: this.palette,
        revisionTick: this.localTick + this.revisionTick,
        onExitChainMode: (): void => {
          this.exitChainMode();
        }
      })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pageBody() {
    Column({ space: 12 }) {
      if (!this.hasActiveGroups()) {
        Column({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.globe_badge_heart'))
              .fontSize(34)
              .fontColor([this.palette.onSurfaceVariant])
          }
          .width(76)
          .height(76)
          .borderRadius(28)
          .backgroundColor(this.palette.card)

          Text(this.store.localeLang === 'en_US' ? 'No Proxies' : '暂无代理')
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
            this.onGoAddProfile();
          })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 80 })
      } else {
        // Optional Add Node / Import Share Link panel (matches clash-verge-rev URI & SOCKS5 importer)
        if (this.showAddNodePanel) {
          Column({ space: 10 }) {
            Text('导入节点至当前配置（前置 / 后置）')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)

            NodeImportPanel({
              palette: this.palette,
              singleButtonMode: false,
              onImportEntries: (entries: ClashProxyEntry[], insertPosition: 'prepend' | 'append'): void => {
                this.handleImportQuickNodes(entries, insertPosition);
              }
            })
          }
          .width('92%')
          .padding(14)
          .backgroundColor(this.palette.card)
          .borderRadius(22)
          .alignItems(HorizontalAlign.Start)
        }

        if (this.showSearchBar) {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([this.palette.onSurfaceVariant])
            TextInput({
              placeholder: this.store.localeLang === 'en_US' ? 'Search proxies...' : '搜索代理节点...',
              text: this.searchKeyword
            })
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .fontColor(this.palette.onSurface)
              .placeholderColor(this.palette.onSurfaceVariant)
              .backgroundColor(Color.Transparent)
              .onChange((val: string): void => {
                this.searchKeyword = val;
              })
          }
          .width('92%')
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.palette.card)
          .borderRadius(20)
        }

        if (this.showStylePanel) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text(this.store.localeLang === 'en_US' ? 'Style' : '风格')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.onSurfaceVariant)
                .width(64)

              ForEach(
                ['tab', 'list'],
                (st: string) => {
                  Text(st === 'tab' ? '标签页' : '列表')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.proxiesViewStyle === st ? this.palette.onPrimary : this.palette.onSurface)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.store.proxiesViewStyle === st ? this.palette.primary : this.palette.block)
                    .borderRadius(14)
                    .onClick((): void => {
                      this.store.proxiesViewStyle = st as ProxiesViewStyle;
                      this.store.notify();
                    })
                },
                (st: string): string => `${st}_${this.store.proxiesViewStyle}`
              )
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row({ space: 8 }) {
              Text(this.store.localeLang === 'en_US' ? 'Sort' : '排序')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.onSurfaceVariant)
                .width(64)

              ForEach(
                ['none', 'delay', 'name'],
                (sk: string) => {
                  Text(sk === 'none' ? '默认' : sk === 'delay' ? '延迟' : '名称')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.store.proxiesSortKind === sk ? this.palette.onPrimary : this.palette.onSurface)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.store.proxiesSortKind === sk ? this.palette.primary : this.palette.block)
                    .borderRadius(14)
                    .onClick((): void => {
                      this.store.proxiesSortKind = sk as ProxiesSortKind;
                      this.store.notify();
                    })
                },
                (sk: string): string => `${sk}_${this.store.proxiesSortKind}`
              )

              Blank()

              Row({ space: 6 }) {
                Text('隐藏超时')
                  .fontSize(12)
                  .fontColor(this.palette.onSurfaceVariant)
                Toggle({ type: ToggleType.Switch, isOn: this.store.hideTimeoutProxies })
                  .selectedColor(this.palette.primary)
                  .onChange((val: boolean): void => {
                    this.store.hideTimeoutProxies = val;
                    this.store.notify();
                  })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('92%')
          .padding(16)
          .backgroundColor(this.palette.card)
          .borderRadius(24)
        }

        if (this.isTabViewStyle()) {
          // Group Choice Chips Row
          Scroll() {
            Row({ space: 8 }) {
              ForEach(
                this.getProxyGroupsReactive(),
                (grp: ProxyGroupItem) => {
                  ProxyGroupChipItem({
                    groupId: grp.id,
                    groupName: grp.name,
                    groupType: grp.groupType,
                    isSelected: this.getCurrentGroup()!.id === grp.id,
                    palette: this.palette,
                    onSelectGroup: (groupId: string): void => {
                      const nextGrp: ProxyGroupItem | null = this.store.getGroupById(groupId);
                      this.store.selectCurrentGroup(groupId);
                      if (nextGrp !== null) {
                        this.selectedGroupIdState = nextGrp.id;
                        this.selectedNodeNameState = nextGrp.selectedName;
                        this.lastStoreGroupId = nextGrp.id;
                        this.localTick += 1;
                      }
                    }
                  })
                },
                (grp: ProxyGroupItem): string => grp.id
              )
            }
            .padding({ left: 18, right: 18 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          // Active Group Selected Node Indicator Bar
          Row({ space: 6 }) {
            Text(`${this.getCurrentGroup()!.name} (${this.getCurrentGroup()!.groupType})`)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurfaceVariant)
            Text('·')
              .fontSize(12)
              .fontColor(this.palette.onSurfaceVariant)
            Text(this.getGroupSelectedName(this.getCurrentGroup()!))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.primary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ left: 20, right: 20 })

          // Nodes Grid
          if (this.getFilteredNodesForGroup(this.getCurrentGroup()!).length === 0) {
            Column({ space: 8 }) {
              Text(this.store.localeLang === 'en_US' ? 'No matching nodes' : '没有匹配的节点')
                .fontSize(14)
                .fontColor(this.palette.onSurfaceVariant)
            }
            .layoutWeight(1)
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ bottom: 108 + this.bottomInset })
          } else {
            Scroll() {
              Grid() {
                ForEach(
                  this.getFilteredNodesForGroup(this.getCurrentGroup()!),
                  (node: ProxyNodeItem) => {
                    GridItem() {
                      ProxyNodeCardItem({
                        nodeName: node.name,
                        nodeProtocol: node.protocol,
                        nodeRegion: node.regionCode,
                        nodeDelayMs: this.getNodeDelay(node),
                        nodeIsTesting: this.getNodeIsTesting(node),
                        isSelected: this.isNodeSelectedInGroup(this.getCurrentGroup()!, node.name),
                        isCompactCard: this.store.proxyCardSize === 'min',
                        palette: this.palette,
                        onSelectNode: (targetName: string): void => {
                          const grp: ProxyGroupItem | null = this.getCurrentGroup();
                          if (grp !== null) {
                            this.handleSelectNode(grp, targetName);
                          }
                        },
                        onTestNodeDelay: (targetName: string): void => {
                          this.store.testSingleNodeDelay(targetName);
                        }
                      })
                    }
                  },
                  (node: ProxyNodeItem): string => `${this.selectedGroupIdState}_${node.id}`
                )
              }
              .columnsTemplate(ResponsiveLayout.proxyColumnsTemplate(this.windowWidthVp))
              .columnsGap(10)
              .rowsGap(10)
              .width('100%')
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.bottomContentPadding(this.windowWidthVp, this.bottomInset)
              })
            }
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.Top)
          }
        } else {
          // Grouped List View
          Scroll() {
            Column({ space: 12 }) {
              ForEach(
                this.getProxyGroupsReactive(),
                (grp: ProxyGroupItem) => {
                  ProxyGroupListCard({
                    groupId: grp.id,
                    groupName: grp.name,
                    groupType: grp.groupType,
                    iconText: grp.iconText,
                    selectedNodeName: this.getGroupSelectedName(grp),
                    isExpanded: this.isGroupExpanded(grp.id),
                    searchKeyword: this.searchKeyword,
                    proxiesSortKind: this.store.proxiesSortKind,
                    hideTimeoutProxies: this.store.hideTimeoutProxies,
                    isCompactCard: this.store.proxyCardSize === 'min',
                    revisionTick: this.localTick + this.revisionTick,
                    palette: this.palette,
                    onToggleExpand: (groupId: string): void => {
                      this.toggleGroupExpand(groupId);
                    },
                    onSelectNode: (groupId: string, targetName: string): void => {
                      const freshGrp: ProxyGroupItem | null = this.store.getGroupById(groupId);
                      if (freshGrp !== null) {
                        this.handleSelectNode(freshGrp, targetName);
                      }
                    },
                    onTestNodeDelay: (targetName: string): void => {
                      this.store.testSingleNodeDelay(targetName);
                    }
                  })
                },
                (grp: ProxyGroupItem): string => grp.id
              )
            }
            .padding({
              left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
              right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
              bottom: ResponsiveLayout.bottomContentPadding(this.windowWidthVp, this.bottomInset)
            })
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.Top)
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  proxiesNavDestination(name: string) {
    if (name === 'chain') {
      ImmersiveNavDestination({
        palette: this.palette,
        immersiveEnabled: this.store.liquidGlass,
        scrollUnderTitle: false,
        revisionTick: this.localTick,
        header: (): void => { this.chainHeader(); },
        bodyContent: (): void => { this.chainBody(); },
        onBackRequest: (): boolean => {
          if (BackNavigationCoordinator.dispatch('chainModal')) {
            return true;
          }
          this.exitChainMode();
          return true;
        }
      })
    }
  }

  build() {
    ImmersiveTitlePage({
      palette: this.palette,
      immersiveEnabled: this.store.liquidGlass,
      revisionTick: this.localTick,
      navPathStack: this.proxiesNavStack,
      header: (): void => { this.mainHeader(); },
      bodyContent: (): void => { this.pageBody(); },
      navDestinationBuilder: (name: string): void => {
        this.proxiesNavDestination(name);
      },
      onNavBarVisibilityChange: (isVisible: boolean): void => {
        if (isVisible && this.proxiesNavStack.size() === 0 && this.showChainPanel) {
          this.exitChainMode();
        }
      }
    })
  }
}

// MonitorComponents.ets — Standalone Mobile Views for Live Connections, Requests, DNS Queries, External Resources & Logs

import { ImmersiveTitleStyle } from '../common/ImmersiveTitleStyle';
import { ImmersiveTitlePage } from './ImmersiveTitlePage';
import { ImmersiveBackButton } from './ImmersiveBackButton';
import { ResponsiveLayout } from '../common/ResponsiveLayout';
import { FlClashColorPalette, I18n, ThemeManager } from '../common/ThemeManager';
import {
  CoreLogRecordItem,
  DnsQueryRecordItem,
  ExternalResourceItem,
  TrackerRecordItem
} from '../core/CoreProtocol';
import { AppStateStore } from '../store/AppStateStore';

class MonitorDataHelper {
  static filterConnections(
    items: TrackerRecordItem[],
    keyword: string,
    networkFilter: string
  ): TrackerRecordItem[] {
    const result: TrackerRecordItem[] = [];
    const kw: string = keyword.trim().toLowerCase();
    for (let i = 0; i < items.length; i++) {
      const c: TrackerRecordItem = items[i];
      if (networkFilter === 'TCP' && c.network !== 'TCP') {
        continue;
      }
      if (networkFilter === 'UDP' && c.network !== 'UDP') {
        continue;
      }
      if (kw.length > 0) {
        const matchHost: boolean = c.targetHost.toLowerCase().includes(kw);
        const matchProc: boolean = c.sourceProcess.toLowerCase().includes(kw);
        const matchExit: boolean = c.exitNodeName.toLowerCase().includes(kw);
        const matchRule: boolean = c.ruleName.toLowerCase().includes(kw) || c.rulePayload.toLowerCase().includes(kw);
        if (!matchHost && !matchProc && !matchExit && !matchRule) {
          continue;
        }
      }
      result.push(c);
    }
    return result;
  }

  static filterDns(items: DnsQueryRecordItem[], keyword: string): DnsQueryRecordItem[] {
    const result: DnsQueryRecordItem[] = [];
    const kw: string = keyword.trim().toLowerCase();
    for (let i = 0; i < items.length; i++) {
      const d: DnsQueryRecordItem = items[i];
      if (kw.length > 0 && !d.domain.toLowerCase().includes(kw) && !d.answerText.toLowerCase().includes(kw)) {
        continue;
      }
      result.push(d);
    }
    return result;
  }

  static filterLogs(items: CoreLogRecordItem[], keyword: string, levelFilter: string): CoreLogRecordItem[] {
    const result: CoreLogRecordItem[] = [];
    const kw: string = keyword.trim().toLowerCase();
    const targetLevel: string = levelFilter.toLowerCase();
    for (let i = 0; i < items.length; i++) {
      const l: CoreLogRecordItem = items[i];
      if (targetLevel !== 'all' && l.level.toLowerCase() !== targetLevel) {
        continue;
      }
      if (kw.length > 0 && !l.payloadText.toLowerCase().includes(kw) && !l.sourceText.toLowerCase().includes(kw)) {
        continue;
      }
      result.push(l);
    }
    return result;
  }

  static logToneColor(level: string, palette: FlClashColorPalette): string {
    const low: string = level.toLowerCase();
    if (low === 'error') { return palette.error; }
    if (low === 'warning') { return palette.warn; }
    if (low === 'debug') { return palette.primary; }
    return palette.onSurfaceVariant;
  }

  static logToneBg(level: string, palette: FlClashColorPalette): string {
    const low: string = level.toLowerCase();
    if (low === 'error') { return palette.errorContainer; }
    if (low === 'warning') { return palette.warnContainer; }
    if (low === 'debug') { return palette.primarySoft; }
    return palette.block;
  }
}

@Component
struct MonitorEmptyView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop labelText: string = '';

  build() {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(30)
          .fontColor([this.palette.onSurfaceVariant])
      }
      .width(68)
      .height(68)
      .borderRadius(24)
      .backgroundColor(this.palette.card)

      Text(this.labelText)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurfaceVariant)
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: 80 })
  }
}

@Component
struct MonitorSearchRow {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop keyword: string = '';
  @Prop placeholderText: string = '搜索...';
  onKeywordChange: (val: string) => void = (_val: string): void => {};

  build() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(15)
        .fontColor([this.palette.onSurfaceVariant])
      TextInput({
        placeholder: this.placeholderText,
        text: this.keyword
      })
        .layoutWeight(1)
        .height(38)
        .fontSize(13)
        .fontColor(this.palette.onSurface)
        .placeholderColor(this.palette.onSurfaceVariant)
        .backgroundColor(Color.Transparent)
        .onChange((val: string): void => {
          this.onKeywordChange(val);
        })
    }
    .width('92%')
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.palette.card)
    .borderRadius(20)
  }
}

@Component
export struct LiveConnectionsPage {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  @Prop showBackButton: boolean = true;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  onBack: () => void = (): void => {};

  @State searchKeyword: string = '';
  @State activeNetworkFilter: string = 'ALL';
  private store: AppStateStore = AppStateStore.getInstance();

  private getItems(): TrackerRecordItem[] {
    const _tick: number = this.revisionTick;
    return _tick >= 0
      ? MonitorDataHelper.filterConnections(this.store.liveConnections, this.searchKeyword, this.activeNetworkFilter)
      : [];
  }

  @Builder
  pageHeader() {
    Row({ space: 10 }) {
      if (this.showBackButton) {
        ImmersiveBackButton({
          palette: this.palette,
          immersiveEnabled: this.store.liquidGlass,
          onBack: (): void => {
            this.onBack();
          }
        })
      }

      Text(I18n.t('liveConnections', this.store.localeLang))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .layoutWeight(1)

      if (this.store.liveConnections.length > 0) {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(13)
            .fontColor([this.palette.error])
          Text(this.store.localeLang === 'en_US' ? 'Close All' : '断开全部')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.error)
        }
        .height(34)
        .padding({ left: 12, right: 12 })
        .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, false))
        .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, false))
        .borderRadius(17)
        .onClick((): void => {
          this.store.closeAllConnections();
        })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  protocolFilterChip(tag: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.activeNetworkFilter === tag ? this.palette.onPrimary : this.palette.onSurface)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.activeNetworkFilter === tag ? this.palette.primary : this.palette.card)
      .borderRadius(14)
      .onClick((): void => {
        this.activeNetworkFilter = tag;
      })
  }

  @Builder
  pageBody() {
    Column({ space: 10 }) {
      MonitorSearchRow({
        palette: this.palette,
        keyword: this.searchKeyword,
        placeholderText: this.store.localeLang === 'en_US' ? 'Search host, process, rule...' : '搜索目标地址、进程、规则...',
        onKeywordChange: (val: string): void => {
          this.searchKeyword = val;
        }
      })

      Row({ space: 8 }) {
        this.protocolFilterChip('ALL', this.store.localeLang === 'en_US' ? 'All' : '全部')
        this.protocolFilterChip('TCP', 'TCP')
        this.protocolFilterChip('UDP', 'UDP')
        Blank()
        Text(`${this.getItems().length} ${this.store.localeLang === 'en_US' ? 'active' : '条连接'}`)
          .fontSize(12)
          .fontColor(this.palette.onSurfaceVariant)
      }
      .width('92%')
      .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.windowWidthVp) })
      .alignItems(VerticalAlign.Center)

      if (this.getItems().length === 0) {
        MonitorEmptyView({
          palette: this.palette,
          labelText: this.store.localeLang === 'en_US' ? 'No connections' : '暂无实时连接'
        })
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(
              this.getItems(),
              (conn: TrackerRecordItem) => {
                Column({ space: 8 }) {
                  Row({ space: 8 }) {
                    Text(conn.sourceProcess)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.onSurface)
                    Text(conn.network)
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.onSurfaceVariant)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(this.palette.block)
                      .borderRadius(6)
                    Blank()
                    Text(conn.startTimeText)
                      .fontSize(11)
                      .fontColor(this.palette.onSurfaceVariant)
                    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                      SymbolGlyph($r('sys.symbol.xmark'))
                        .fontSize(11)
                        .fontColor([this.palette.error])
                    }
                    .width(26)
                    .height(26)
                    .padding(0)
                    .backgroundColor(this.palette.errorContainer)
                    .onClick((): void => {
                      this.store.closeConnectionById(conn.id);
                    })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)

                  Text(conn.targetHost)
                    .fontSize(14)
                    .fontColor(this.palette.onSurface)
                    .width('100%')

                  Row({ space: 8 }) {
                    Text(`${conn.ruleName}(${conn.rulePayload})`)
                      .fontSize(11)
                      .fontColor(this.palette.onSurfaceVariant)
                      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                      .backgroundColor(this.palette.block)
                      .borderRadius(8)
                    Text(`→ ${conn.exitNodeName}`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.primary)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor(this.palette.card)
                .borderRadius(22)
              },
              (conn: TrackerRecordItem): string => `conn_${conn.id}`
            )
          }
          .width('100%')
          .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.windowWidthVp) })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 6 })
  }

  build() {
    ImmersiveTitlePage({
      palette: this.palette,
      immersiveEnabled: this.store.liquidGlass,
      revisionTick: this.revisionTick,
      scrollUnderTitle: false,
      header: (): void => { this.pageHeader(); },
      bodyContent: (): void => { this.pageBody(); }
    })
  }
}

@Component
export struct RequestsMonitorPage {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  @Prop showBackButton: boolean = true;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  onBack: () => void = (): void => {};

  @State searchKeyword: string = '';
  private store: AppStateStore = AppStateStore.getInstance();

  private getRequests(): TrackerRecordItem[] {
    const _tick: number = this.revisionTick;
    return _tick >= 0
      ? MonitorDataHelper.filterConnections(this.store.recentRequests, this.searchKeyword, 'ALL')
      : [];
  }

  @Builder
  pageHeader() {
    Row({ space: 10 }) {
      if (this.showBackButton) {
        ImmersiveBackButton({
          palette: this.palette,
          immersiveEnabled: this.store.liquidGlass,
          onBack: (): void => {
            this.onBack();
          }
        })
      }

      Text(I18n.t('recentRequests', this.store.localeLang))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .layoutWeight(1)

      Text(`${this.getRequests().length}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.primary)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, true))
        .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, true))
        .borderRadius(14)
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  pageBody() {
    Column({ space: 12 }) {
      MonitorSearchRow({
        palette: this.palette,
        keyword: this.searchKeyword,
        placeholderText: this.store.localeLang === 'en_US' ? 'Search requested host or rule...' : '搜索请求域名、规则或出站...',
        onKeywordChange: (val: string): void => {
          this.searchKeyword = val;
        }
      })

      if (this.getRequests().length === 0) {
        MonitorEmptyView({
          palette: this.palette,
          labelText: this.store.localeLang === 'en_US' ? 'No requests' : '暂无请求记录'
        })
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(
              this.getRequests(),
              (req: TrackerRecordItem) => {
                Column({ space: 8 }) {
                  Row({ space: 8 }) {
                    Text(req.network)
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.primary)
                      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                      .backgroundColor(this.palette.primarySoft)
                      .borderRadius(6)
                    Text(req.targetHost)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.onSurface)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(req.startTimeText)
                      .fontSize(11)
                      .fontColor(this.palette.onSurfaceVariant)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)

                  Row({ space: 8 }) {
                    Text(req.sourceProcess)
                      .fontSize(11)
                      .fontColor(this.palette.onSurfaceVariant)
                    Text(`${req.ruleName}(${req.rulePayload})`)
                      .fontSize(11)
                      .fontColor(this.palette.onSurfaceVariant)
                      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                      .backgroundColor(this.palette.block)
                      .borderRadius(8)
                    Blank()
                    Text(`→ ${req.exitNodeName}`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.primary)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(15)
                .backgroundColor(this.palette.card)
                .borderRadius(20)
              },
              (req: TrackerRecordItem): string => `req_${req.id}`
            )
          }
          .width('100%')
          .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.windowWidthVp) })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 6 })
  }

  build() {
    ImmersiveTitlePage({
      palette: this.palette,
      immersiveEnabled: this.store.liquidGlass,
      revisionTick: this.revisionTick,
      scrollUnderTitle: false,
      header: (): void => { this.pageHeader(); },
      bodyContent: (): void => { this.pageBody(); }
    })
  }
}

@Component
export struct DnsQueriesMonitorPage {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  @Prop showBackButton: boolean = true;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  onBack: () => void = (): void => {};

  @State searchKeyword: string = '';
  private store: AppStateStore = AppStateStore.getInstance();

  private getDnsList(): DnsQueryRecordItem[] {
    const _tick: number = this.revisionTick;
    return _tick >= 0 ? MonitorDataHelper.filterDns(this.store.dnsQueries, this.searchKeyword) : [];
  }

  @Builder
  pageHeader() {
    Row({ space: 10 }) {
      if (this.showBackButton) {
        ImmersiveBackButton({
          palette: this.palette,
          immersiveEnabled: this.store.liquidGlass,
          onBack: (): void => {
            this.onBack();
          }
        })
      }

      Text(I18n.t('dnsQueries', this.store.localeLang))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .layoutWeight(1)

      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(13)
          .fontColor([this.palette.primary])
        Text(this.store.localeLang === 'en_US' ? 'Clear Cache' : '清空缓存')
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
        this.store.clearDnsCache();
      })
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  pageBody() {
    Column({ space: 12 }) {
      MonitorSearchRow({
        palette: this.palette,
        keyword: this.searchKeyword,
        placeholderText: this.store.localeLang === 'en_US' ? 'Search domain or answer...' : '搜索查询域名或解析结果...',
        onKeywordChange: (val: string): void => {
          this.searchKeyword = val;
        }
      })

      if (this.getDnsList().length === 0) {
        MonitorEmptyView({
          palette: this.palette,
          labelText: this.store.localeLang === 'en_US'
            ? 'DNS query logging is not connected. This page cannot verify DNS leaks.'
            : '暂未接入真实 DNS 查询日志，此页无法判断 DNS 是否泄露。'
        })
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(
              this.getDnsList(),
              (q: DnsQueryRecordItem) => {
                Column({ space: 6 }) {
                  Row({ space: 8 }) {
                    Text(q.qtype)
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.primary)
                      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                      .backgroundColor(this.palette.primarySoft)
                      .borderRadius(6)
                    Text(q.domain)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.onSurface)
                      .layoutWeight(1)
                    Text(`${q.durationMs} ms`)
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(ThemeManager.delayColor(q.durationMs, this.palette))
                  }
                  .width('100%')

                  Text(`${q.answerText} · ${q.upstreamServer}`)
                    .fontSize(12)
                    .fontColor(this.palette.onSurfaceVariant)
                    .width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor(this.palette.card)
                .borderRadius(20)
              },
              (q: DnsQueryRecordItem): string => `dns_${q.id}`
            )
          }
          .width('100%')
          .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.windowWidthVp) })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 6 })
  }

  build() {
    ImmersiveTitlePage({
      palette: this.palette,
      immersiveEnabled: this.store.liquidGlass,
      revisionTick: this.revisionTick,
      scrollUnderTitle: false,
      header: (): void => { this.pageHeader(); },
      bodyContent: (): void => { this.pageBody(); }
    })
  }
}

@Component
export struct ExternalResourcesPage {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  @Prop showBackButton: boolean = true;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  onBack: () => void = (): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

  private getResourcesList(): ExternalResourceItem[] {
    const _tick: number = this.revisionTick;
    return _tick >= 0 ? this.store.externalResources : [];
  }

  @Builder
  pageHeader() {
    Row({ space: 10 }) {
      if (this.showBackButton) {
        ImmersiveBackButton({
          palette: this.palette,
          immersiveEnabled: this.store.liquidGlass,
          onBack: (): void => {
            this.onBack();
          }
        })
      }

      Text(I18n.t('resources', this.store.localeLang))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  pageBody() {
    Column() {
      if (this.getResourcesList().length === 0) {
        MonitorEmptyView({
          palette: this.palette,
          labelText: this.store.localeLang === 'en_US' ? 'No external resources' : '暂无外部资源'
        })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(
              this.getResourcesList(),
              (resItem: ExternalResourceItem) => {
                Row({ space: 12 }) {
                  Column({ space: 4 }) {
                    Text(resItem.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.onSurface)
                    Text(`${resItem.entriesCount} entries · ${resItem.sizeText} · ${resItem.updatedAtText}`)
                      .fontSize(12)
                      .fontColor(this.palette.onSurfaceVariant)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                      .fontSize(14)
                      .fontColor([this.palette.primary])
                  }
                  .width(34)
                  .height(34)
                  .padding(0)
                  .backgroundColor(this.palette.primarySoft)
                  .onClick((): void => {
                    this.store.updateExternalResource(resItem.id);
                  })
                }
                .width('100%')
                .padding(16)
                .backgroundColor(this.palette.card)
                .borderRadius(24)
                .alignItems(VerticalAlign.Center)
              },
              (resItem: ExternalResourceItem): string => `res_${resItem.id}`
            )
          }
          .width('100%')
          .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.windowWidthVp) })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 6 })
  }

  build() {
    ImmersiveTitlePage({
      palette: this.palette,
      immersiveEnabled: this.store.liquidGlass,
      revisionTick: this.revisionTick,
      scrollUnderTitle: false,
      header: (): void => { this.pageHeader(); },
      bodyContent: (): void => { this.pageBody(); }
    })
  }
}

@Component
export struct LogsMonitorPage {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  @Prop showBackButton: boolean = true;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  onBack: () => void = (): void => {};

  @State searchKeyword: string = '';
  @State selectedLogLevel: string = 'ALL';
  private store: AppStateStore = AppStateStore.getInstance();

  private getLogsList(): CoreLogRecordItem[] {
    const _tick: number = this.revisionTick;
    return _tick >= 0
      ? MonitorDataHelper.filterLogs(this.store.coreLogs, this.searchKeyword, this.selectedLogLevel)
      : [];
  }

  @Builder
  pageHeader() {
    Row({ space: 10 }) {
      if (this.showBackButton) {
        ImmersiveBackButton({
          palette: this.palette,
          immersiveEnabled: this.store.liquidGlass,
          onBack: (): void => {
            this.onBack();
          }
        })
      }

      Text(I18n.t('logs', this.store.localeLang))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .layoutWeight(1)

      Text(`${this.getLogsList().length}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.primary)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.store.liquidGlass, true))
        .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.store.liquidGlass, true))
        .borderRadius(14)
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  logLevelChip(levelKey: string) {
    Text(levelKey === 'ALL' ? (this.store.localeLang === 'en_US' ? 'ALL' : '全部') : levelKey)
      .fontSize(11)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.selectedLogLevel === levelKey ? this.palette.onPrimary : this.palette.onSurface)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.selectedLogLevel === levelKey ? this.palette.primary : this.palette.card)
      .borderRadius(14)
      .onClick((): void => {
        this.selectedLogLevel = levelKey;
      })
  }

  @Builder
  pageBody() {
    Column({ space: 10 }) {
      MonitorSearchRow({
        palette: this.palette,
        keyword: this.searchKeyword,
        placeholderText: this.store.localeLang === 'en_US' ? 'Search log content or source...' : '搜索日志内容或来源...',
        onKeywordChange: (val: string): void => {
          this.searchKeyword = val;
        }
      })

      Scroll() {
        Row({ space: 6 }) {
          this.logLevelChip('ALL')
          this.logLevelChip('INFO')
          this.logLevelChip('WARNING')
          this.logLevelChip('ERROR')
          this.logLevelChip('DEBUG')
        }
        .padding({ left: 18, right: 18 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.getLogsList().length === 0) {
        MonitorEmptyView({
          palette: this.palette,
          labelText: this.store.localeLang === 'en_US' ? 'No logs' : '暂无日志'
        })
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(
              this.getLogsList(),
              (logItem: CoreLogRecordItem) => {
                Column({ space: 6 }) {
                  Row({ space: 8 }) {
                    Text(logItem.timeText)
                      .fontSize(11)
                      .fontColor(this.palette.onSurfaceVariant)
                    Text(logItem.level.toUpperCase())
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(MonitorDataHelper.logToneColor(logItem.level, this.palette))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(MonitorDataHelper.logToneBg(logItem.level, this.palette))
                      .borderRadius(6)
                    Text(`${logItem.tag} · ${logItem.sourceText}`)
                      .fontSize(12)
                      .fontColor(this.palette.onSurfaceVariant)
                      .layoutWeight(1)
                  }
                  .width('100%')

                  Text(logItem.payloadText)
                    .fontSize(13)
                    .fontColor(this.palette.onSurface)
                    .width('100%')
                }
                .width('100%')
                .padding(15)
                .backgroundColor(this.palette.card)
                .borderRadius(20)
                .alignItems(HorizontalAlign.Start)
              },
              (logItem: CoreLogRecordItem): string => `log_${logItem.id}`
            )
          }
          .width('100%')
          .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.windowWidthVp) })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 6 })
  }

  build() {
    ImmersiveTitlePage({
      palette: this.palette,
      immersiveEnabled: this.store.liquidGlass,
      revisionTick: this.revisionTick,
      scrollUnderTitle: false,
      header: (): void => { this.pageHeader(); },
      bodyContent: (): void => { this.pageBody(); }
    })
  }
}

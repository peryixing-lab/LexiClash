import { ImmersiveTitleStyle } from '../common/ImmersiveTitleStyle';
// Index.ets — Mobile Shell of LexiClash (FlClash for HarmonyOS NEXT)

import { accessibility } from '@kit.AccessibilityKit';
import { curves, uiMaterial } from '@kit.ArkUI';
import { ImmersiveTitlePage } from '../components/ImmersiveTitlePage';
import { LexiLaunchScreen } from '../components/LexiLaunchScreen';
import { BackNavigationCoordinator, ImmersivePageTransition } from '../components/ImmersiveBackButton';
import { ImmersiveWindowController } from '../common/ImmersiveWindowController';
import { ResponsiveLayout } from '../common/ResponsiveLayout';
import { FlClashColorPalette, I18n, ThemeManager } from '../common/ThemeManager';
import {
  DashboardFeedKind,
  DashboardWidgetConfigItem,
  LexiMonitorTab,
  ServiceProbeItem
} from '../core/CoreProtocol';
import { AppStateStore } from '../store/AppStateStore';
import {
  ConnectionStatsCardView,
  CurrentOutboundCardView,
  DashboardEditorView,
  IntranetIpCardView,
  MemoryInfoCardView,
  MobileNetworkSpeedCardView,
  OutboundModeCardView,
  ProfileSummaryCardView,
  ProxyGroupsCardView,
  ServiceStatusCardView,
  VpnCardView
} from '../components/DashboardComponents';
import {
  DnsQueriesMonitorPage,
  LiveConnectionsPage,
  RequestsMonitorPage
} from '../components/MonitorComponents';
import { ProfilesMainView } from '../components/ProfilesComponents';
import { ProxiesMainView } from '../components/ProxiesComponents';
import { ToolsMainView } from '../components/ToolsComponents';

type MainTabKey = 'dashboard' | 'proxies' | 'profiles' | 'connections' | 'tools';

@Entry
@Component
struct Index {
  @State currentTab: MainTabKey = 'dashboard';
  @State selectedDockTab: MainTabKey = 'dashboard';
  @State dashboardDetailOpen: boolean = false;
  @State monitorInitialTab: LexiMonitorTab = 'connections';
  @State reduceMotion: boolean = false;
  @State revisionTick: number = 0;
  @State uiLocaleLang: string = AppStateStore.getInstance().localeLang;
  @State windowWidthVp: number = 390;
  @StorageProp('lexiWindowWidthVp') storedWindowWidthVp: number = 0;
  @StorageProp('lexiTopInset') titleTopInset: number = 0;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiProfilesSecondary') profilesSecondaryOpen: boolean = false;
  @StorageProp('lexiToolsSecondary') toolsSecondaryOpen: boolean = false;
  @State isEditingDashboard: boolean = false;
  @State activeSheet: 'none' | 'ipDetail' | 'serviceDetail' = 'none';
  @State launchReady: boolean = false;
  @State startupStep: number = 0;
  @State startupError: string = '';
  private launchDestroyed: boolean = false;
  private launchTimerIds: number[] = [];

  @StorageProp('lexiSystemDark') @Watch('updateWindowChrome') systemDarkMode: boolean = false;
  @StorageProp('lexiWindowReady') @Watch('updateWindowChrome') immersiveWindowReady: boolean = false;
  private mobileTabsController: TabsController = new TabsController();
  private dashboardNavStack: NavPathStack = new NavPathStack();
  // Match LexiNote-Harmony's native tab spring and 220ms base transition.
  private readonly tabSpring: curves.ICurve = curves.springMotion(0.35, 0.86);
  private readonly selectionCurve: curves.ICurve = curves.cubicBezierCurve(0.23, 1, 0.32, 1);
  private readonly dockMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    interactive: false,
    applyShadow: true,
    lightEffect: null
  });
  private motionListening: boolean = false;
  private readonly motionListener: (enabled: boolean) => void = (enabled: boolean): void => {
    this.reduceMotion = enabled;
    AppStorage.setOrCreate('lexiReduceMotion', enabled);
  };
  private store: AppStateStore = AppStateStore.getInstance();
  private storeListener: () => void = (): void => {
    this.revisionTick += 1;
    this.uiLocaleLang = this.store.localeLang;
    this.updateWindowChrome();
  };

  aboutToAppear(): void {
    this.launchDestroyed = false;
    this.uiLocaleLang = this.store.localeLang;
    this.store.subscribe(this.storeListener);
    this.updateWindowChrome();
    try {
      this.reduceMotion = accessibility.isAnimationReduceEnabledSync();
    } catch (error) {
      this.reduceMotion = false;
    }
    AppStorage.setOrCreate('lexiReduceMotion', this.reduceMotion);
    if (!this.motionListening) {
      try {
        accessibility.onAnimationReduceStateChange(this.motionListener);
        this.motionListening = true;
      } catch (error) {
        this.motionListening = false;
      }
    }
    this.runLaunchSequenceAsync();
  }

  private pauseLaunchMs(ms: number): Promise<void> {
    if (ms <= 0 || this.launchDestroyed) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      const id: number = setTimeout((): void => {
        const idx: number = this.launchTimerIds.indexOf(id);
        if (idx >= 0) {
          this.launchTimerIds.splice(idx, 1);
        }
        resolve();
      }, ms);
      this.launchTimerIds.push(id);
    });
  }

  private async runLaunchSequenceAsync(): Promise<void> {
    this.startupError = '';
    this.startupStep = 0;
    try {
      await this.pauseLaunchMs(this.reduceMotion ? 0 : 280);
      if (this.launchDestroyed) { return; }
      this.startupStep = 1;

      await Promise.all([
        this.store.awaitStartupReadyAsync(320),
        this.pauseLaunchMs(this.reduceMotion ? 0 : 260)
      ]);
      if (this.launchDestroyed) { return; }
      this.startupStep = 2;

      await this.pauseLaunchMs(this.reduceMotion ? 40 : 240);
      if (!this.launchDestroyed) {
        this.launchReady = true;
      }
    } catch (err) {
      this.startupError = err instanceof Error ? err.message : String(err);
    }
  }

  aboutToDisappear(): void {
    this.launchDestroyed = true;
    for (let i: number = 0; i < this.launchTimerIds.length; i++) {
      clearTimeout(this.launchTimerIds[i]);
    }
    this.launchTimerIds = [];
    this.store.unsubscribe(this.storeListener);
    if (this.motionListening) {
      try {
        accessibility.offAnimationReduceStateChange(this.motionListener);
      } catch (error) {
        // The accessibility service may have disconnected during window teardown.
      }
      this.motionListening = false;
    }
  }

  onBackPress(): boolean {
    if (!this.launchReady) {
      return true;
    }
    if (this.activeSheet !== 'none') {
      this.activeSheet = 'none';
      return true;
    }
    const activeTab: MainTabKey = this.currentTab;
    if (activeTab === 'dashboard' || activeTab === 'connections') {
      if (this.dashboardDetailOpen) {
        this.selectTab('dashboard');
        return true;
      }
      if (this.isEditingDashboard) {
        this.isEditingDashboard = false;
        return true;
      }
      return false;
    }
    if (BackNavigationCoordinator.dispatch(activeTab)) {
      return true;
    }
    this.selectTab('dashboard');
    return true;
  }

  private getPalette(): FlClashColorPalette {
    return ThemeManager.resolvePalette(
      this.store.themeMode === 'auto' ? (this.systemDarkMode ? 'dark' : 'light') : this.store.themeMode,
      this.store.seedColorId,
      this.store.colorStyle,
      this.store.pureBlack
    );
  }

  private updateWindowChrome(): void {
    const palette: FlClashColorPalette = this.getPalette();
    ImmersiveWindowController.applyTheme(this.store.themeMode, palette.isDark, palette.page);
  }

  private getMobileTabIndex(tab: MainTabKey): number {
    if (tab === 'proxies') return 1;
    if (tab === 'profiles') return 2;
    if (tab === 'tools') return 3;
    return 0;
  }

  private getTabForIndex(index: number): MainTabKey {
    if (index === 1) return 'proxies';
    if (index === 2) return 'profiles';
    if (index === 3) return 'tools';
    return 'dashboard';
  }

  private selectTab(tab: MainTabKey): void {
    if (tab === 'connections') {
      this.dashboardDetailOpen = true;
      ImmersivePageTransition.push(this.dashboardNavStack, this.monitorInitialTab);
    } else if (tab === 'dashboard') {
      this.dashboardDetailOpen = false;
      ImmersivePageTransition.clear(this.dashboardNavStack);
    }
    this.selectedDockTab = tab === 'connections' ? 'dashboard' : tab;
    const index: number = this.getMobileTabIndex(tab);
    if (index === this.getMobileTabIndex(this.currentTab)) {
      this.currentTab = tab;
    }
    // Let the controller animate first; updating its bound index beforehand skips the transition.
    this.mobileTabsController.changeIndex(index);
  }

  private activateTab(index: number): void {
    this.currentTab = index === 0 && this.dashboardDetailOpen ? 'connections' : this.getTabForIndex(index);
    this.selectedDockTab = this.getTabForIndex(index);
  }

  private getMediaIcon(iconName: string): Resource {
    if (iconName === 'google') return $r('app.media.google');
    if (iconName === 'github') return $r('app.media.github');
    if (iconName === 'openai') return $r('app.media.openai');
    if (iconName === 'claude') return $r('app.media.claude');
    if (iconName === 'youtube') return $r('app.media.youtube');
    if (iconName === 'netflix') return $r('app.media.netflix');
    if (iconName === 'spotify') return $r('app.media.spotify');
    if (iconName === 'disneyplus') return $r('app.media.disneyplus');
    if (iconName === 'gemini') return $r('app.media.gemini');
    if (iconName === 'discord') return $r('app.media.discord');
    if (iconName === 'bilibili') return $r('app.media.bilibili');
    return $r('app.media.tiktok');
  }

  private getServiceDetailLabel(srv: ServiceProbeItem): string {
    if (srv.status === 'checking') {
      return this.uiLocaleLang === 'en_US' ? 'Loading…' : '加载中…';
    }
    if (srv.delayMs > 0) {
      return `${srv.delayMs} ms`;
    }
    if (srv.delayMs < 0) {
      return this.uiLocaleLang === 'en_US' ? 'Failed' : '检测失败';
    }
    return this.uiLocaleLang === 'en_US' ? 'Pending' : '待检测';
  }

  @Builder
  mobileDockItem(tab: MainTabKey, iconRes: Resource, labelKey: string) {
    Column({ space: 3 }) {
      SymbolGlyph(iconRes)
        .fontSize(20)
        .fontColor([this.selectedDockTab === tab ? this.getPalette().primary : this.getPalette().onSurfaceVariant])
      Text(I18n.t(labelKey, this.uiLocaleLang))
        .fontSize(11)
        .fontWeight(this.selectedDockTab === tab ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.selectedDockTab === tab ? this.getPalette().primary : this.getPalette().onSurfaceVariant)
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Transparent)
    .borderRadius(24)
    .animation({ duration: this.reduceMotion ? 0 : 160, curve: this.selectionCurve })
    .onClick((): void => {
      this.selectTab(tab);
    })
  }

  @Builder
  dashboardTopBar() {
    Row({ space: 10 }) {
      Text(this.isEditingDashboard
        ? I18n.t('editDashboard', this.uiLocaleLang)
        : I18n.t('dashboard', this.uiLocaleLang))
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getPalette().onSurface)
        .layoutWeight(1)

      // Edit Dashboard Button (Pencil / Check — matching FlClash mobile Dashboard top bar)
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.isEditingDashboard ? $r('sys.symbol.checkmark') : $r('sys.symbol.square_and_pencil'))
          .fontSize(16)
          .fontColor([this.isEditingDashboard ? this.getPalette().primary : this.getPalette().onSurface])
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor(ImmersiveTitleStyle.background(this.getPalette(), this.store.liquidGlass, this.isEditingDashboard))
      .systemMaterial(ImmersiveTitleStyle.material(this.getPalette(), this.store.liquidGlass, this.isEditingDashboard))
      .onClick((): void => {
        this.isEditingDashboard = !this.isEditingDashboard;
      })
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
  }

  private effectiveWidthVp(): number {
    return this.storedWindowWidthVp > 0 ? this.storedWindowWidthVp : this.windowWidthVp;
  }

  private isSecondaryPageActive(): boolean {
    if (this.currentTab === 'connections' || (this.currentTab === 'dashboard' && this.dashboardDetailOpen)) {
      return true;
    }
    // Proxy chain mode shares the Proxies workspace and keeps the dock accessible.
    if (this.currentTab === 'profiles' && this.profilesSecondaryOpen) {
      return true;
    }
    if (this.currentTab === 'tools' && this.toolsSecondaryOpen) {
      return true;
    }
    return false;
  }

  private shouldHideBottomDock(): boolean {
    return ResponsiveLayout.isExpanded(this.effectiveWidthVp()) || this.isSecondaryPageActive();
  }

  private buildBarFloatingStyle(): FloatingTabBarStyle | undefined {
    if (this.shouldHideBottomDock()) {
      return undefined;
    }
    return {
      barWidth: {
        smallBarWidth: ResponsiveLayout.floatingBarWidth(this.effectiveWidthVp(), this.store.navBarStyle),
        mediumBarWidth: ResponsiveLayout.floatingBarWidth(this.effectiveWidthVp(), this.store.navBarStyle),
        largeBarWidth: ResponsiveLayout.floatingBarWidth(this.effectiveWidthVp(), this.store.navBarStyle)
      },
      barSideMargin: this.store.navBarStyle === 'floating' ? 16 : 0,
      barBottomMargin: this.bottomInset,
      maskColor: this.getPalette().page,
      maskHeight: 100 + this.bottomInset,
      systemMaterial: this.store.liquidGlass && ImmersiveTitleStyle.isSupported()
        ? this.dockMaterial : uiMaterial.Material.empty
    };
  }

  private enabledWidgetsForColumn(colIdx: number, totalCols: number): DashboardWidgetConfigItem[] {
    const enabled: DashboardWidgetConfigItem[] = this.store.dashboardWidgets.filter(
      (item: DashboardWidgetConfigItem): boolean => item.enabled
    );
    if (totalCols <= 1) {
      return enabled;
    }
    const result: DashboardWidgetConfigItem[] = [];
    for (let i: number = 0; i < enabled.length; i++) {
      if (i % totalCols === colIdx) {
        result.push(enabled[i]);
      }
    }
    return result;
  }

  @Builder
  renderDashboardWidget(wItem: DashboardWidgetConfigItem) {
    if (wItem.id === 'currentOutbound') {
      CurrentOutboundCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        onOpenIpSheet: (): void => {
          this.activeSheet = 'ipDetail';
        },
        onRequireProfile: (): void => {
          this.selectTab('profiles');
        }
      })
    } else if (wItem.id === 'networkSpeed') {
      MobileNetworkSpeedCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick
      })
    } else if (wItem.id === 'outboundMode') {
      OutboundModeCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick
      })
    } else if (wItem.id === 'vpnButton') {
      VpnCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        onRequireProfile: (): void => {
          this.selectTab('profiles');
        }
      })
    } else if (wItem.id === 'profiles') {
      ProfileSummaryCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        onNavigateProfiles: (): void => {
          this.selectTab('profiles');
        }
      })
    } else if (wItem.id === 'serviceStatus') {
      ServiceStatusCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        onOpenServicesSheet: (): void => {
          this.activeSheet = 'serviceDetail';
        }
      })
    } else if (wItem.id === 'proxyGroups') {
      ProxyGroupsCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        onSelectGroupToSwitch: (groupId: string): void => {
          this.store.selectCurrentGroup(groupId);
          this.selectTab('proxies');
        }
      })
    } else if (wItem.id === 'connectionStats') {
      ConnectionStatsCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        onOpenFeed: (feed: DashboardFeedKind): void => {
          this.monitorInitialTab = feed;
          this.selectTab('connections');
        }
      })
    } else if (wItem.id === 'intranetIp') {
      IntranetIpCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick
      })
    } else if (wItem.id === 'memoryInfo') {
      MemoryInfoCardView({
        palette: this.getPalette(),
        revisionTick: this.revisionTick
      })
    }
  }

  @Builder
  mobileDashboardList() {
    Column({ space: 10 }) {
      Scroll() {
        Column({ space: 14 }) {
          if (this.isEditingDashboard) {
            Column() {
              DashboardEditorView({
                palette: this.getPalette(),
                revisionTick: this.revisionTick,
                onFinishEdit: (): void => {
                  this.isEditingDashboard = false;
                }
              })
            }
            .width('100%')
            .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.effectiveWidthVp()) })
          } else if (ResponsiveLayout.dashboardColumns(this.effectiveWidthVp()) === 1) {
            ForEach(
              this.enabledWidgetsForColumn(0, 1),
              (wItem: DashboardWidgetConfigItem) => {
                this.renderDashboardWidget(wItem)
              },
              (wItem: DashboardWidgetConfigItem): string => `${wItem.id}_${wItem.enabled}_${this.revisionTick}`
            )
          } else if (ResponsiveLayout.dashboardColumns(this.effectiveWidthVp()) === 2) {
            Row({ space: 14 }) {
              Column({ space: 14 }) {
                ForEach(
                  this.enabledWidgetsForColumn(0, 2),
                  (wItem: DashboardWidgetConfigItem) => {
                    this.renderDashboardWidget(wItem)
                  },
                  (wItem: DashboardWidgetConfigItem): string => `c0_${wItem.id}_${this.revisionTick}`
                )
              }
              .layoutWeight(1)

              Column({ space: 14 }) {
                ForEach(
                  this.enabledWidgetsForColumn(1, 2),
                  (wItem: DashboardWidgetConfigItem) => {
                    this.renderDashboardWidget(wItem)
                  },
                  (wItem: DashboardWidgetConfigItem): string => `c1_${wItem.id}_${this.revisionTick}`
                )
              }
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Row({ space: 14 }) {
              Column({ space: 14 }) {
                ForEach(
                  this.enabledWidgetsForColumn(0, 3),
                  (wItem: DashboardWidgetConfigItem) => {
                    this.renderDashboardWidget(wItem)
                  },
                  (wItem: DashboardWidgetConfigItem): string => `w0_${wItem.id}_${this.revisionTick}`
                )
              }
              .layoutWeight(1)

              Column({ space: 14 }) {
                ForEach(
                  this.enabledWidgetsForColumn(1, 3),
                  (wItem: DashboardWidgetConfigItem) => {
                    this.renderDashboardWidget(wItem)
                  },
                  (wItem: DashboardWidgetConfigItem): string => `w1_${wItem.id}_${this.revisionTick}`
                )
              }
              .layoutWeight(1)

              Column({ space: 14 }) {
                ForEach(
                  this.enabledWidgetsForColumn(2, 3),
                  (wItem: DashboardWidgetConfigItem) => {
                    this.renderDashboardWidget(wItem)
                  },
                  (wItem: DashboardWidgetConfigItem): string => `w2_${wItem.id}_${this.revisionTick}`
                )
              }
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: ResponsiveLayout.contentMaxWidth(this.effectiveWidthVp()) })
        .padding({
          left: ResponsiveLayout.horizontalPadding(this.effectiveWidthVp()),
          right: ResponsiveLayout.horizontalPadding(this.effectiveWidthVp()),
          top: 4,
          bottom: ResponsiveLayout.bottomContentPadding(this.effectiveWidthVp(), this.bottomInset)
        })
      }
      .contentStartOffset(64 + this.titleTopInset)
      .contentEndOffset(this.bottomInset)
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ipQualityDetailSheetOverlay() {
    Stack({ alignContent: ResponsiveLayout.isCompact(this.effectiveWidthVp()) ? Alignment.Bottom : Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#70000000')
        .onClick((): void => {
          this.activeSheet = 'none';
        })

      Column({ space: 14 }) {
        Row() {
          Text(this.uiLocaleLang === 'en_US' ? 'Outbound IP Details' : '出口 IP 详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getPalette().onSurface)
            .layoutWeight(1)

          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([this.getPalette().onSurfaceVariant])
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(this.getPalette().block)
          .onClick((): void => {
            this.activeSheet = 'none';
          })
        }
        .width('100%')

        Row({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            Text(
              ThemeManager.countryFlagEmoji(
                this.store.outboundIpInfo.countryCode,
                this.store.outboundIpInfo.countryName
              ) || this.store.outboundIpInfo.countryCode
            )
              .fontSize(
                ThemeManager.countryFlagEmoji(
                  this.store.outboundIpInfo.countryCode,
                  this.store.outboundIpInfo.countryName
                ).length > 0 ? 26 : 16
              )
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getPalette().primary)
          }
          .width(48)
          .height(48)
          .borderRadius(16)
          .backgroundColor(this.getPalette().primarySoft)

          Column({ space: 3 }) {
            Text(this.store.outboundIpInfo.ip)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getPalette().onSurface)
            Text(
              ThemeManager.countryDisplayName(
                this.store.outboundIpInfo.countryCode,
                this.store.outboundIpInfo.countryName,
                this.uiLocaleLang
              )
            )
              .fontSize(13)
              .fontColor(this.getPalette().onSurfaceVariant)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.getPalette().block)
        .borderRadius(20)

        Column({ space: 10 }) {
          Row() {
            Text(this.uiLocaleLang === 'en_US' ? 'Network Type' : '网络类型')
              .fontSize(13)
              .fontColor(this.getPalette().onSurfaceVariant)
            Blank()
            Text(ThemeManager.formatIpTypeLabel(this.store.outboundIpInfo.ipType, this.uiLocaleLang))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getPalette().onSurface)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.getPalette().inset)
              .borderRadius(10)
          }
          .width('100%')

          Row() {
            Text(this.uiLocaleLang === 'en_US' ? 'Line Quality' : '线路评估')
              .fontSize(13)
              .fontColor(this.getPalette().onSurfaceVariant)
            Blank()
            Text(ThemeManager.formatIpQualityLabel(this.store.outboundIpInfo.qualityLevel, this.uiLocaleLang))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeManager.ipQualityTextColor(this.store.outboundIpInfo.qualityLevel, this.getPalette()))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(ThemeManager.ipQualityBgColor(this.store.outboundIpInfo.qualityLevel, this.getPalette()))
              .borderRadius(10)
          }
          .width('100%')

          Row() {
            Text('ASN / ISP')
              .fontSize(13)
              .fontColor(this.getPalette().onSurfaceVariant)
            Blank()
            Text(`${this.store.outboundIpInfo.asn} ${this.store.outboundIpInfo.organization}`.trim() || '-')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getPalette().onSurface)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.End)
              .constraintSize({ maxWidth: 260 })
          }
          .width('100%')

          if (this.store.outboundIpInfo.timezone.length > 0) {
            Row() {
              Text(this.uiLocaleLang === 'en_US' ? 'Timezone' : '所在时区')
                .fontSize(13)
                .fontColor(this.getPalette().onSurfaceVariant)
              Blank()
              Text(this.store.outboundIpInfo.timezone)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getPalette().onSurface)
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getPalette().block)
        .borderRadius(20)
      }
      .width('100%')
      .constraintSize({ maxWidth: ResponsiveLayout.sheetMaxWidth(this.effectiveWidthVp()) })
      .padding({ left: 22, right: 22, top: 20, bottom: 28 })
      .margin(ResponsiveLayout.isCompact(this.effectiveWidthVp()) ? 0 : 20)
      .backgroundColor(this.getPalette().card)
      .borderRadius(ResponsiveLayout.isCompact(this.effectiveWidthVp())
        ? { topLeft: 32, topRight: 32 }
        : 28)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  serviceStatusDetailSheetOverlay() {
    Stack({ alignContent: ResponsiveLayout.isCompact(this.effectiveWidthVp()) ? Alignment.Bottom : Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#70000000')
        .onClick((): void => {
          this.activeSheet = 'none';
        })

      Column({ space: 12 }) {
        Row({ space: 10 }) {
          Text(I18n.t('serviceStatus', this.uiLocaleLang))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getPalette().onSurface)
            .layoutWeight(1)

          Button() {
            Text(this.uiLocaleLang === 'en_US' ? 'Check All' : '全部检测')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getPalette().onPrimary)
          }
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.getPalette().primary)
          .borderRadius(15)
          .onClick((): void => {
            this.store.recheckAllServices();
          })

          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([this.getPalette().onSurfaceVariant])
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(this.getPalette().block)
          .onClick((): void => {
            this.activeSheet = 'none';
          })
        }
        .width('100%')

        Grid() {
          ForEach(
            this.store.serviceProbes,
            (srv: ServiceProbeItem) => {
              GridItem() {
                Row({ space: 10 }) {
                  Stack({ alignContent: Alignment.Center }) {
                    Image(this.getMediaIcon(srv.iconName))
                      .width(18)
                      .height(18)
                      .fillColor(this.getPalette().onSurface)
                  }
                  .width(32)
                  .height(32)
                  .borderRadius(10)
                  .backgroundColor(this.getPalette().inset)

                  Column({ space: 2 }) {
                    Text(srv.name)
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.getPalette().onSurface)
                    Text(this.getServiceDetailLabel(srv))
                      .fontSize(11)
                      .fontColor(ThemeManager.delayColor(srv.delayMs, this.getPalette()))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.getPalette().block)
                .borderRadius(16)
              }
            },
            (srv: ServiceProbeItem): string => `${srv.id}_${srv.delayMs}_${srv.status}`
          )
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .height(380)
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxWidth: ResponsiveLayout.sheetMaxWidth(this.effectiveWidthVp()) })
      .padding({ left: 20, right: 20, top: 20, bottom: 26 })
      .margin(ResponsiveLayout.isCompact(this.effectiveWidthVp()) ? 0 : 20)
      .backgroundColor(this.getPalette().card)
      .borderRadius(ResponsiveLayout.isCompact(this.effectiveWidthVp())
        ? { topLeft: 32, topRight: 32 }
        : 28)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  dashboardNavDestination(name: string) {
    if (name === 'requests') {
      RequestsMonitorPage({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        showBackButton: true,
        onBack: (): void => {
          this.selectTab('dashboard');
        }
      })
    } else if (name === 'dns') {
      DnsQueriesMonitorPage({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        showBackButton: true,
        onBack: (): void => {
          this.selectTab('dashboard');
        }
      })
    } else {
      LiveConnectionsPage({
        palette: this.getPalette(),
        revisionTick: this.revisionTick,
        showBackButton: true,
        onBack: (): void => {
          this.selectTab('dashboard');
        }
      })
    }
  }

  @Builder
  dashboardPage() {
    ImmersiveTitlePage({
      palette: this.getPalette(),
      immersiveEnabled: this.store.liquidGlass,
      scrollUnderTitle: true,
      revisionTick: this.revisionTick,
      navPathStack: this.dashboardNavStack,
      header: (): void => { this.dashboardTopBar(); },
      bodyContent: (): void => {
        this.mobileDashboardList()
      },
      navDestinationBuilder: (name: string): void => {
        this.dashboardNavDestination(name);
      },
      onNavBarVisibilityChange: (isVisible: boolean): void => {
        if (isVisible && this.dashboardNavStack.size() === 0 && this.dashboardDetailOpen) {
          this.dashboardDetailOpen = false;
          if (this.currentTab === 'connections') {
            this.currentTab = 'dashboard';
          }
        }
      }
    })
  }

  @Builder
  railNavItem(tab: MainTabKey, iconRes: Resource, labelKey: string, isWideRail: boolean) {
    if (isWideRail) {
      Row({ space: 12 }) {
        SymbolGlyph(iconRes)
          .fontSize(19)
          .fontColor([this.selectedDockTab === tab ? this.getPalette().primary : this.getPalette().onSurfaceVariant])
        Text(I18n.t(labelKey, this.uiLocaleLang))
          .fontSize(14)
          .fontWeight(this.selectedDockTab === tab ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedDockTab === tab ? this.getPalette().primary : this.getPalette().onSurface)
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 14 })
      .backgroundColor(this.selectedDockTab === tab ? this.getPalette().primarySoft : Color.Transparent)
      .borderRadius(14)
      .animation({ duration: this.reduceMotion ? 0 : 160, curve: this.selectionCurve })
      .onClick((): void => {
        this.selectTab(tab);
      })
    } else {
      Column({ space: 4 }) {
        SymbolGlyph(iconRes)
          .fontSize(20)
          .fontColor([this.selectedDockTab === tab ? this.getPalette().primary : this.getPalette().onSurfaceVariant])
        Text(I18n.t(labelKey, this.uiLocaleLang))
          .fontSize(11)
          .fontWeight(this.selectedDockTab === tab ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedDockTab === tab ? this.getPalette().primary : this.getPalette().onSurfaceVariant)
      }
      .width('100%')
      .height(54)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.selectedDockTab === tab ? this.getPalette().primarySoft : Color.Transparent)
      .borderRadius(16)
      .animation({ duration: this.reduceMotion ? 0 : 160, curve: this.selectionCurve })
      .onClick((): void => {
        this.selectTab(tab);
      })
    }
  }

  @Builder
  expandedNavigationRail() {
    Column({ space: 8 }) {
      if (this.effectiveWidthVp() >= ResponsiveLayout.WIDE_MIN_VP) {
        Row({ space: 10 }) {
          Image($r('app.media.startIcon'))
            .width(28)
            .height(28)
            .borderRadius(8)
          Text('LexiClash')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getPalette().onSurface)
        }
        .width('100%')
        .padding({ left: 10, right: 8, bottom: 14 })
      } else {
        Image($r('app.media.startIcon'))
          .width(34)
          .height(34)
          .borderRadius(10)
          .margin({ bottom: 12 })
      }

      this.railNavItem('dashboard', $r('sys.symbol.square_grid_2x2'), 'dashboard',
        this.effectiveWidthVp() >= ResponsiveLayout.WIDE_MIN_VP)
      this.railNavItem('proxies', $r('sys.symbol.globe_badge_heart'), 'proxies',
        this.effectiveWidthVp() >= ResponsiveLayout.WIDE_MIN_VP)
      this.railNavItem('profiles', $r('sys.symbol.doc_text'), 'profiles',
        this.effectiveWidthVp() >= ResponsiveLayout.WIDE_MIN_VP)
      this.railNavItem('tools', $r('sys.symbol.gearshape'), 'tools',
        this.effectiveWidthVp() >= ResponsiveLayout.WIDE_MIN_VP)

      Blank()

      if (this.effectiveWidthVp() >= ResponsiveLayout.WIDE_MIN_VP) {
        Row({ space: 8 }) {
          Circle({ width: 8, height: 8 })
            .fill(this.revisionTick >= 0 && this.store.isRunning
              ? this.getPalette().onOkContainer : this.getPalette().onSurfaceVariant)
          Text(this.revisionTick >= 0 && this.store.isRunning
            ? I18n.t('running', this.uiLocaleLang)
            : I18n.t('stopped', this.uiLocaleLang))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.revisionTick >= 0 && this.store.isRunning
              ? this.getPalette().onOkContainer : this.getPalette().onSurfaceVariant)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.revisionTick >= 0 && this.store.isRunning
          ? this.getPalette().okContainer : this.getPalette().block)
        .borderRadius(14)
      }
    }
    .width(this.effectiveWidthVp() >= ResponsiveLayout.WIDE_MIN_VP ? 196 : 86)
    .height('100%')
    .padding({
      left: 12,
      right: 12,
      top: this.titleTopInset + 18,
      bottom: Math.max(18, this.bottomInset + 12)
    })
    .backgroundColor(this.getPalette().floating)
    .border({ width: { right: 0.5 }, color: this.getPalette().divider })
    .alignItems(this.effectiveWidthVp() >= ResponsiveLayout.WIDE_MIN_VP ? HorizontalAlign.Start : HorizontalAlign.Center)
  }

  @Builder
  mobileTabs() {
    Tabs({ index: this.getMobileTabIndex(this.currentTab), controller: this.mobileTabsController }) {
      TabContent() {
        this.dashboardPage()
      }
      .tabBar(this.mobileDockItem('dashboard', $r('sys.symbol.square_grid_2x2'), 'dashboard'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      TabContent() {
        ProxiesMainView({
          palette: this.getPalette(),
          revisionTick: this.revisionTick,
          onGoAddProfile: (): void => { this.selectTab('profiles'); }
        })
      }
      .tabBar(this.mobileDockItem('proxies', $r('sys.symbol.globe_badge_heart'), 'proxies'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      TabContent() {
        ProfilesMainView({ palette: this.getPalette(), revisionTick: this.revisionTick })
      }
      .tabBar(this.mobileDockItem('profiles', $r('sys.symbol.doc_text'), 'profiles'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      TabContent() {
        ToolsMainView({
          palette: this.getPalette(),
          revisionTick: this.revisionTick
        })
      }
      .tabBar(this.mobileDockItem('tools', $r('sys.symbol.gearshape'), 'tools'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .scrollable(false)
    .animationCurve(this.reduceMotion ? Curve.Linear : this.tabSpring)
    .animationDuration(this.reduceMotion ? 0 : 220)
    .barOverlap(!this.shouldHideBottomDock())
    .vertical(false)
    .barPosition(BarPosition.End)
    .barHeight(this.shouldHideBottomDock() ? 0 : 64)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .barBackgroundColor(this.shouldHideBottomDock() || this.store.liquidGlass
      ? Color.Transparent : this.getPalette().floating)
    .barFloatingStyle(this.buildBarFloatingStyle())
    .onAnimationStart((_index: number, targetIndex: number, _extraInfo: TabsAnimationEvent): void => {
      this.selectedDockTab = this.getTabForIndex(targetIndex);
    })
    .onChange((index: number): void => {
      this.activateTab(index);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row() {
        if (ResponsiveLayout.isExpanded(this.effectiveWidthVp())) {
          this.expandedNavigationRail()
        }
        Column() {
          this.mobileTabs()
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .opacity(this.launchReady ? 1 : 0)
      .animation({ duration: this.reduceMotion ? 0 : 220, curve: this.selectionCurve })

      if (this.activeSheet === 'ipDetail') {
        this.ipQualityDetailSheetOverlay()
      } else if (this.activeSheet === 'serviceDetail') {
        this.serviceStatusDetailSheetOverlay()
      }

      if (!this.launchReady) {
        Column() {
          LexiLaunchScreen({
            palette: this.getPalette(),
            startupStep: this.startupStep,
            errorMessage: this.startupError,
            reduceMotion: this.reduceMotion,
            localeLang: this.uiLocaleLang,
            topInset: this.titleTopInset,
            bottomInset: this.bottomInset,
            onRetry: (): void => {
              this.runLaunchSequenceAsync();
            }
          })
        }
        .width('100%')
        .height('100%')
        .zIndex(20)
        .transition(ImmersivePageTransition.launchOverlay())
      }
    }
    .width('100%')
    .height(LayoutPolicy.matchParent)
    .background(this.getPalette().page)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onAreaChange((_oldVal: Area, newVal: Area): void => {
      const w: number = Number(newVal.width);
      if (w > 0 && Math.abs(w - this.windowWidthVp) > 4) {
        this.windowWidthVp = w;
        AppStorage.setOrCreate<number>('lexiWindowWidthVp', w);
      }
    })
  }
}

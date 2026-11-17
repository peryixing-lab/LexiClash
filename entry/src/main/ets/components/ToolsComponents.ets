import { ImmersiveTitleStyle } from '../common/ImmersiveTitleStyle';
// ToolsComponents.ets — Mobile FlClash Tools & Settings View with ImmersivePage

import { ImmersiveTitlePage } from './ImmersiveTitlePage';
import { AppAccessSettingsView } from './AppAccessSettingsView';
import { TunSettingsView } from './TunSettingsView';
import { BackNavigationCoordinator, ImmersiveBackButton, ImmersivePageTransition } from './ImmersiveBackButton';
import { ResponsiveLayout } from '../common/ResponsiveLayout';
import {
  DnsQueriesMonitorPage,
  ExternalResourcesPage,
  LogsMonitorPage,
  RequestsMonitorPage
} from './MonitorComponents';
import { FlClashColorPalette, I18n, SeedPresetItem, ThemeManager } from '../common/ThemeManager';
import { CoreController } from '../core/CoreController';
import {
  ColorStyleKind,
  LexiMonitorTab,
  NavBarStyleKind,
  ThemeModeKind
} from '../core/CoreProtocol';
import { AppStateStore } from '../store/AppStateStore';

export type ToolsSubPageKind =
  'main'
    | 'requests'
    | 'dns'
    | 'resources'
    | 'logs'
    | 'language'
    | 'theme'
    | 'tun'
    | 'access'
    | 'backup'
    | 'advanced'
    | 'general'
    | 'disclaimer'
    | 'developer'
    | 'about';

@Component
struct LanguageOptionRowView {
  @Prop langCode: string = 'zh_CN';
  @Prop titleText: string = '';
  @Prop subtitleText: string = '';
  @Prop selected: boolean = false;
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  onSelectLanguage: (langCode: string) => void = (_code: string): void => {};

  build() {
    Row({ space: 14 }) {
      Column({ space: 3 }) {
        Text(this.titleText)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Text(this.subtitleText)
          .fontSize(12)
          .fontColor(this.palette.onSurfaceVariant)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.selected) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(13)
            .fontColor([this.palette.onPrimary])
        }
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor(this.palette.primary)
      } else {
        Stack()
          .width(24)
          .height(24)
          .borderRadius(12)
          .border({ width: 1.5, color: this.palette.divider })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 15, bottom: 15 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onSelectLanguage(this.langCode);
    })
  }
}

@Component
struct ToolsGroupedRowItem {
  @Prop iconRes: Resource = $r('sys.symbol.gearshape');
  @Prop titleText: string = '';
  @Prop subtitleText: string = '';
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  onTapAction: () => void = (): void => {};

  build() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.iconRes)
          .fontSize(18)
          .fontColor([this.palette.primary])
      }
      .width(38)
      .height(38)
      .borderRadius(12)
      .backgroundColor(this.palette.primarySoft)

      Column({ space: 2 }) {
        Text(this.titleText)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        if (this.subtitleText.length > 0) {
          Text(this.subtitleText)
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(15)
        .fontColor([this.palette.onSurfaceVariant])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onTapAction();
    })
  }
}

@Component
export struct ToolsMainView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop @Watch('onRevisionChange') revisionTick: number = 0;
  @StorageProp('lexiTopInset') titleTopInset: number = 0;
  @StorageProp('lexiBottomInset') bottomInset: number = 0;
  @StorageProp('lexiWindowWidthVp') windowWidthVp: number = 390;
  onOpenMonitorPage: (tab: LexiMonitorTab) => void = (_tab: LexiMonitorTab): void => {};

  @State @Watch('onSecondaryStateChange') subPage: ToolsSubPageKind = 'main';
  @State lastSettingsSubPage: ToolsSubPageKind = 'language';
  @State selectedLocaleLang: string = AppStateStore.getInstance().localeLang;
  @State selectedThemeMode: ThemeModeKind = AppStateStore.getInstance().themeMode;
  @State selectedSeedColorId: string = AppStateStore.getInstance().seedColorId;
  @State selectedColorStyle: ColorStyleKind = AppStateStore.getInstance().colorStyle;
  @State portMixedInput: string = '7890';
  @State testUrlInput: string = 'https://www.gstatic.com/generate_204';
  @State webdavUrlInput: string = '';
  @State webdavUserInput: string = '';
  @State webdavPassInput: string = '';

  private store: AppStateStore = AppStateStore.getInstance();
  private core: CoreController = CoreController.getInstance();

  onRevisionChange(): void {
    this.selectedLocaleLang = this.store.localeLang;
    this.selectedThemeMode = this.store.themeMode;
    this.selectedSeedColorId = this.store.seedColorId;
    this.selectedColorStyle = this.store.colorStyle;
  }

  private syncSecondaryDockState(): void {
    AppStorage.setOrCreate<boolean>('lexiToolsSecondary', this.subPage !== 'main');
  }

  onSecondaryStateChange(): void {
    this.syncSecondaryDockState();
  }

  aboutToAppear(): void {
    this.syncSecondaryDockState();
    BackNavigationCoordinator.register('tools', (): boolean => {
      if (this.subPage !== 'main') {
        this.subPage = 'main';
        return true;
      }
      return false;
    });
  }

  aboutToDisappear(): void {
    BackNavigationCoordinator.unregister('tools');
    AppStorage.setOrCreate<boolean>('lexiToolsSecondary', false);
  }

  @Builder
  switchSettingRow(titleText: string, descText: string, isOnVal: boolean, onChangeFn: (val: boolean) => void, settingEnabled: boolean = true) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(titleText)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        if (descText.length > 0) {
          Text(descText)
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOnVal })
        .selectedColor(this.palette.primary)
        .enabled(settingEnabled)
        .onChange((v: boolean): void => {
          onChangeFn(v);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.palette.card)
    .borderRadius(22)
    .alignItems(VerticalAlign.Center)
  }

  private openSubPage(target: ToolsSubPageKind): void {
    if (
      target !== 'main' &&
        target !== 'requests' &&
        target !== 'dns' &&
        target !== 'resources' &&
        target !== 'logs'
    ) {
      this.lastSettingsSubPage = target;
    }
    this.subPage = target;
  }

  private activeSettingsKey(): ToolsSubPageKind {
    if (
      this.subPage === 'main' ||
        this.subPage === 'requests' ||
        this.subPage === 'dns' ||
        this.subPage === 'resources' ||
        this.subPage === 'logs'
    ) {
      return this.lastSettingsSubPage;
    }
    return this.subPage;
  }

  private getSubPageTitle(): string {
    const key: ToolsSubPageKind = this.activeSettingsKey();
    const lang: string = this.selectedLocaleLang;
    if (key === 'language') return I18n.t('language', lang);
    if (key === 'theme') return I18n.t('theme', lang);
    if (key === 'tun') return lang === 'en_US' ? 'TUN Settings' : 'TUN 设置';
    if (key === 'access') return I18n.t('accessControl', lang);
    if (key === 'backup') return I18n.t('backupRestore', lang);
    if (key === 'advanced') return I18n.t('advancedConfig', lang);
    if (key === 'general') return I18n.t('general', lang);
    if (key === 'disclaimer') return I18n.t('disclaimer', lang);
    if (key === 'developer') return I18n.t('developerMode', lang);
    if (key === 'about') return I18n.t('about', lang);
    return I18n.t('tools', lang);
  }

  @Builder
  mainToolsHeader() {
    Row({ space: 10 }) {
      Text(I18n.t('tools', this.selectedLocaleLang))
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
  subPageHeader() {
    Row({ space: 10 }) {
      ImmersiveBackButton({
        palette: this.palette,
        immersiveEnabled: this.store.liquidGlass,
        onBack: (): void => {
          this.subPage = 'main';
        }
      })

      Text(this.getSubPageTitle())
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
  mainToolsBody() {
    Column({ space: 12 }) {
      Scroll() {
        Column({ space: 18 }) {
          // Section 1: More Tools (Requests, DNS, Resources, Logs — each opens its own standalone page)
          Column() {
            ToolsGroupedRowItem({
              iconRes: $r('sys.symbol.arrow_left_arrow_right'),
              titleText: this.selectedLocaleLang === 'en_US' ? 'Requests' : '请求',
              subtitleText: '',
              palette: this.palette,
              onTapAction: (): void => {
                this.subPage = 'requests';
              }
            })
            Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
            ToolsGroupedRowItem({
              iconRes: $r('sys.symbol.globe_badge_heart'),
              titleText: I18n.t('dnsQueries', this.selectedLocaleLang),
              subtitleText: '',
              palette: this.palette,
              onTapAction: (): void => {
                this.subPage = 'dns';
              }
            })
            Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
            ToolsGroupedRowItem({
              iconRes: $r('sys.symbol.folder'),
              titleText: I18n.t('resources', this.selectedLocaleLang),
              subtitleText: '',
              palette: this.palette,
              onTapAction: (): void => {
                this.subPage = 'resources';
              }
            })
            Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
            ToolsGroupedRowItem({
              iconRes: $r('sys.symbol.doc_plaintext'),
              titleText: I18n.t('logs', this.selectedLocaleLang),
              subtitleText: '',
              palette: this.palette,
              onTapAction: (): void => {
                this.subPage = 'logs';
              }
            })
          }
                .width('100%')
                .backgroundColor(this.palette.card)
                .borderRadius(26)

                // Section 2: Settings (matching FlClash tools.dart _getSettingList)
                Column({ space: 8 }) {
                  Text(I18n.t('settings', this.selectedLocaleLang))
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurfaceVariant)
                    .padding({ left: 6 })

                  Column() {
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.globe_badge_heart'),
                      titleText: I18n.t('language', this.selectedLocaleLang),
                      subtitleText: this.selectedLocaleLang === 'en_US' ? 'English' : '中文简体',
                      palette: this.palette,
                      onTapAction: (): void => {
                        this.openSubPage('language');
                      }
                    })
                    Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.paintbrush'),
                      titleText: I18n.t('theme', this.selectedLocaleLang),
                      subtitleText: '',
                      palette: this.palette,
                      onTapAction: (): void => {
                        this.openSubPage('theme');
                      }
                    })
                    Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.shield_checkered'),
                      titleText: this.selectedLocaleLang === 'en_US' ? 'TUN Settings' : 'TUN 设置',
                      subtitleText: (this.revisionTick >= 0 && this.store.vpnEnabled)
                        ? (this.selectedLocaleLang === 'en_US' ? 'Active' : '已开启')
                        : (this.selectedLocaleLang === 'en_US' ? 'Off' : '未开启'),
                      palette: this.palette,
                      onTapAction: (): void => { this.openSubPage('tun'); }
                    })
                    Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.checkmark_shield'),
                      titleText: I18n.t('accessControl', this.selectedLocaleLang),
                      subtitleText: '',
                      palette: this.palette,
                      onTapAction: (): void => {
                        this.openSubPage('access');
                      }
                    })
                    Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.arrow_clockwise'),
                      titleText: I18n.t('backupRestore', this.selectedLocaleLang),
                      subtitleText: '',
                      palette: this.palette,
                      onTapAction: (): void => {
                        this.webdavUrlInput = this.store.webdavUrl;
                        this.webdavUserInput = this.store.webdavUser;
                        this.openSubPage('backup');
                      }
                    })
                    Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.slider_horizontal_2'),
                      titleText: I18n.t('advancedConfig', this.selectedLocaleLang),
                      subtitleText: '',
                      palette: this.palette,
                      onTapAction: (): void => {
                        this.portMixedInput = `${this.store.mixedPort}`;
                        this.openSubPage('advanced');
                      }
                    })
                    Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.gearshape'),
                      titleText: I18n.t('general', this.selectedLocaleLang),
                      subtitleText: '',
                      palette: this.palette,
                      onTapAction: (): void => {
                        this.testUrlInput = this.store.testUrl;
                        this.openSubPage('general');
                      }
                    })
                  }
                  .width('100%')
                  .backgroundColor(this.palette.card)
                  .borderRadius(26)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)

                // Section 3: Other (matching FlClash tools.dart _getOtherList)
                Column({ space: 8 }) {
                  Text(I18n.t('other', this.selectedLocaleLang))
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurfaceVariant)
                    .padding({ left: 6 })

                  Column() {
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.doc_text'),
                      titleText: I18n.t('disclaimer', this.selectedLocaleLang),
                      subtitleText: '',
                      palette: this.palette,
                      onTapAction: (): void => {
                        this.openSubPage('disclaimer');
                      }
                    })
                    Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 68, right: 16 })
                    ToolsGroupedRowItem({
                      iconRes: $r('sys.symbol.info_circle'),
                      titleText: I18n.t('about', this.selectedLocaleLang),
                      subtitleText: '',
                      palette: this.palette,
                      onTapAction: (): void => {
                        this.openSubPage('about');
                      }
                    })
                  }
                  .width('100%')
                  .backgroundColor(this.palette.card)
                  .borderRadius(26)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
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
    .width('100%')
    .height('100%')
  }

  private applyLanguageSelection(langCode: string): void {
    this.selectedLocaleLang = langCode;
    if (this.store.localeLang !== langCode) {
      this.store.localeLang = langCode;
      this.store.notify();
    }
  }

  @Builder
  subPageBody() {
    Column({ space: 12 }) {
      if (this.activeSettingsKey() === 'language') {
        Scroll() {
          Column({ space: 14 }) {
            Text(this.selectedLocaleLang === 'en_US'
              ? 'Choose interface display language'
              : '请选择应用界面显示语言')
              .fontSize(13)
              .fontColor(this.palette.onSurfaceVariant)
              .padding({ left: 4 })

            Column() {
              LanguageOptionRowView({
                langCode: 'zh_CN',
                titleText: '中文简体',
                subtitleText: '简体中文 (中国大陆)',
                selected: this.selectedLocaleLang === 'zh_CN',
                palette: this.palette,
                onSelectLanguage: (code: string): void => {
                  this.applyLanguageSelection(code);
                }
              })
              Divider().color(this.palette.divider).strokeWidth(0.5).margin({ left: 16, right: 16 })
              LanguageOptionRowView({
                langCode: 'en_US',
                titleText: 'English',
                subtitleText: 'English (United States)',
                selected: this.selectedLocaleLang === 'en_US',
                palette: this.palette,
                onSelectLanguage: (code: string): void => {
                  this.applyLanguageSelection(code);
                }
              })
            }
            .width('100%')
            .backgroundColor(this.palette.card)
            .borderRadius(26)
          }
          .width('100%')
          .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
          .padding({
            left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
            bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
          })
          .alignItems(HorizontalAlign.Start)
        }
        .contentStartOffset(64 + this.titleTopInset)
        .contentEndOffset(this.bottomInset)
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
      } else if (this.activeSettingsKey() === 'theme') {
            Scroll() {
              Column({ space: 14 }) {
                Column({ space: 10 }) {
                  Text(this.selectedLocaleLang === 'en_US' ? 'Theme Mode' : '主题模式')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)

                  Row({ space: 8 }) {
                    ForEach(
                      ['auto', 'light', 'dark'],
                      (tm: string) => {
                        Text(tm === 'auto'
                          ? (this.selectedLocaleLang === 'en_US' ? 'Auto' : '自动')
                          : tm === 'light'
                            ? (this.selectedLocaleLang === 'en_US' ? 'Light' : '浅色')
                            : (this.selectedLocaleLang === 'en_US' ? 'Dark' : '深色'))
                          .fontSize(13)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.selectedThemeMode === tm ? this.palette.onPrimary : this.palette.onSurface)
                          .padding({ top: 10, bottom: 10 })
                          .backgroundColor(this.selectedThemeMode === tm ? this.palette.primary : this.palette.block)
                          .borderRadius(16)
                          .layoutWeight(1)
                          .textAlign(TextAlign.Center)
                          .onClick((): void => {
                            this.selectedThemeMode = tm as ThemeModeKind;
                            this.store.themeMode = tm as ThemeModeKind;
                            this.store.notify();
                          })
                      },
                      (tm: string): string => `${tm}_${this.selectedThemeMode === tm}_${this.selectedLocaleLang}`
                    )
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(26)
                .alignItems(HorizontalAlign.Start)

                Column({ space: 10 }) {
                  Text(this.selectedLocaleLang === 'en_US' ? 'Theme Color' : '主题色彩')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)

                  Grid() {
                    ForEach(
                      ThemeManager.SEED_PRESETS,
                      (preset: SeedPresetItem) => {
                        GridItem() {
                          Row({ space: 10 }) {
                            Circle({ width: 22, height: 22 })
                              .fill(this.palette.isDark ? preset.darkHex : preset.lightHex)
                            Text(this.selectedLocaleLang === 'en_US' ? preset.nameEn : preset.nameZh)
                              .fontSize(12)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(this.selectedSeedColorId === preset.id ? this.palette.onPrimary : this.palette.onSurface)
                              .layoutWeight(1)
                              .maxLines(1)
                          }
                          .width('100%')
                          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                          .backgroundColor(this.selectedSeedColorId === preset.id ? this.palette.primary : this.palette.block)
                          .borderRadius(16)
                          .onClick((): void => {
                            this.selectedSeedColorId = preset.id;
                            this.store.seedColorId = preset.id;
                            this.store.notify();
                          })
                        }
                      },
                      (preset: SeedPresetItem): string => `${preset.id}_${this.selectedSeedColorId === preset.id}_${this.selectedLocaleLang}`
                    )
                  }
                  .columnsTemplate(ResponsiveLayout.seedGridColumnsTemplate(this.windowWidthVp))
                  .columnsGap(8)
                  .rowsGap(8)
                  .height(ResponsiveLayout.isCompact(this.windowWidthVp) ? 148 : 100)
                  .width('100%')
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(26)
                .alignItems(HorizontalAlign.Start)

                Column({ space: 10 }) {
                  Text(this.selectedLocaleLang === 'en_US' ? 'Color Style' : '配色风格')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)

                  Row({ space: 6 }) {
                    ForEach(
                      ['vivid', 'tinted', 'soft', 'monochrome'],
                      (cs: string) => {
                        Text(cs === 'vivid' ? '鲜明' : cs === 'tinted' ? '氛围' : cs === 'soft' ? '柔和' : '单色')
                          .fontSize(12)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.selectedColorStyle === cs ? this.palette.onPrimary : this.palette.onSurface)
                          .padding({ top: 9, bottom: 9 })
                          .backgroundColor(this.selectedColorStyle === cs ? this.palette.primary : this.palette.block)
                          .borderRadius(14)
                          .layoutWeight(1)
                          .textAlign(TextAlign.Center)
                          .onClick((): void => {
                            this.selectedColorStyle = cs as ColorStyleKind;
                            this.store.colorStyle = cs as ColorStyleKind;
                            this.store.notify();
                          })
                      },
                      (cs: string): string => `${cs}_${this.selectedColorStyle === cs}`
                    )
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(26)
                .alignItems(HorizontalAlign.Start)

                this.switchSettingRow(
                  this.selectedLocaleLang === 'en_US' ? 'Pure Black' : '纯黑模式',
                  '',
                  this.store.pureBlack,
                  (v: boolean): void => {
                    this.store.pureBlack = v;
                    this.store.notify();
                  }
                )

                this.switchSettingRow(
                  this.selectedLocaleLang === 'en_US' ? 'Liquid Glass' : '液态玻璃',
                  '',
                  this.store.liquidGlass,
                  (v: boolean): void => {
                    this.store.liquidGlass = v;
                    this.store.notify();
                  }
                )

                this.switchSettingRow(
                  this.selectedLocaleLang === 'en_US' ? 'Floating Navigation Bar' : '悬浮底栏',
                  '',
                  this.store.navBarStyle === 'floating',
                  (v: boolean): void => {
                    this.store.navBarStyle = v ? 'floating' : 'docked' as NavBarStyleKind;
                    this.store.notify();
                  }
                )
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
              })
            }
            .contentStartOffset(64 + this.titleTopInset)
            .contentEndOffset(this.bottomInset)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.Top)
          } else if (this.activeSettingsKey() === 'tun') {
            Scroll() {
              Column() {
                TunSettingsView({ palette: this.palette, revisionTick: this.revisionTick })
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
              })
            }
            .contentStartOffset(64 + this.titleTopInset)
            .contentEndOffset(this.bottomInset)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.Top)
          } else if (this.activeSettingsKey() === 'access') {
            Scroll() {
              Column({ space: 12 }) {
                AppAccessSettingsView({ palette: this.palette, revisionTick: this.revisionTick })
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
              })
            }
            .contentStartOffset(64 + this.titleTopInset)
            .contentEndOffset(this.bottomInset)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.Top)
          } else if (this.activeSettingsKey() === 'backup') {
            Scroll() {
              Column({ space: 14 }) {
                Text('备份与恢复尚未接入。本地配置会自动保存在应用沙箱中。')
                  .fontSize(13).fontColor(this.palette.onSurfaceVariant)
                Column({ space: 12 }) {
                  Row({ space: 8 }) {
                    Text('WebDAV 配置')
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.onSurface)
                      .layoutWeight(1)
                    Text('尚未实现')
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.store.webdavConnected ? this.palette.onOkContainer : this.palette.onSurfaceVariant)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .backgroundColor(this.store.webdavConnected ? this.palette.okContainer : this.palette.block)
                      .borderRadius(10)
                  }
                  .width('100%')

                  TextInput({ text: this.webdavUrlInput, placeholder: '请输入有效的 WebDAV 地址' })
                    .height(42)
                    .fontSize(13)
                    .fontColor(this.palette.onSurface)
                    .placeholderColor(this.palette.onSurfaceVariant)
                    .backgroundColor(this.palette.block)
                    .borderRadius(12)
                    .onChange((val: string): void => {
                      this.webdavUrlInput = val;
                      this.store.webdavUrl = val;
                      this.store.webdavConnected = false;
                    })

                  TextInput({ text: this.webdavUserInput, placeholder: '账号' })
                    .height(42)
                    .fontSize(13)
                    .fontColor(this.palette.onSurface)
                    .placeholderColor(this.palette.onSurfaceVariant)
                    .backgroundColor(this.palette.block)
                    .borderRadius(12)
                    .onChange((val: string): void => {
                      this.webdavUserInput = val;
                      this.store.webdavUser = val;
                    })

                  TextInput({ text: this.webdavPassInput, placeholder: '密码' })
                    .type(InputType.Password)
                    .height(42)
                    .fontSize(13)
                    .fontColor(this.palette.onSurface)
                    .placeholderColor(this.palette.onSurfaceVariant)
                    .backgroundColor(this.palette.block)
                    .borderRadius(12)
                    .onChange((val: string): void => {
                      this.webdavPassInput = val;
                      this.store.webdavPassword = val;
                    })

                  Row({ space: 10 }) {
                    Button() {
                      Text('备份')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onPrimary)
                    }
                    .layoutWeight(1)
                    .height(42)
                    .backgroundColor(this.palette.primary)
                    .borderRadius(16)
                    .enabled(false)
                    .onClick((): void => {
                      if (!this.store.webdavConnected) {
                        return;
                      }
                      this.getUIContext().getPromptAction().showToast({ message: 'WebDAV 备份尚未实现', duration: 2000 });
                    })

                    Button() {
                      Text('恢复')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onSurface)
                    }
                    .layoutWeight(1)
                    .height(42)
                    .backgroundColor(this.palette.block)
                    .borderRadius(16)
                    .enabled(false)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(26)
                .alignItems(HorizontalAlign.Start)

                Column({ space: 10 }) {
                  Text('本地')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)

                  Row({ space: 10 }) {
                    Button() {
                      Text('备份')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.primary)
                    }
                    .layoutWeight(1)
                    .height(42)
                    .backgroundColor(this.palette.primarySoft)
                    .borderRadius(16)
                    .enabled(false)

                    Button() {
                      Text('恢复')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onSurface)
                    }
                    .layoutWeight(1)
                    .height(42)
                    .backgroundColor(this.palette.block)
                    .borderRadius(16)
                    .enabled(false)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(26)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
              })
            }
            .contentStartOffset(64 + this.titleTopInset)
            .contentEndOffset(this.bottomInset)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.Top)
          } else if (this.activeSettingsKey() === 'advanced') {
            Scroll() {
              Column({ space: 12 }) {
                Column({ space: 10 }) {
                  Text('端口')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)

                  Row({ space: 10 }) {
                    Text('混合端口')
                      .fontSize(13)
                      .fontColor(this.palette.onSurfaceVariant)
                      .layoutWeight(1)
                    TextInput({ text: this.portMixedInput })
                      .width(100)
                      .height(36)
                      .fontSize(13)
                      .fontColor(this.palette.onSurface)
                      .backgroundColor(this.palette.block)
                      .borderRadius(10)
                      .onChange((val: string): void => {
                        this.portMixedInput = val;
                        const p: number = parseInt(val, 10);
                        if (!isNaN(p) && p >= 1024 && p <= 65535) {
                          this.store.mixedPort = p;
                        }
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(26)
                .alignItems(HorizontalAlign.Start)

                ToolsGroupedRowItem({
                  iconRes: $r('sys.symbol.shield_checkered'),
                  titleText: this.selectedLocaleLang === 'en_US' ? 'TUN Settings' : 'TUN 设置',
                  subtitleText: this.selectedLocaleLang === 'en_US' ? 'Stack, MTU and connection status' : '协议栈、MTU 与连接状态',
                  palette: this.palette,
                  onTapAction: (): void => { this.openSubPage('tun'); }
                })

                this.switchSettingRow(
                  'IPv6',
                  '关闭时拦截 IPv6；开启后通过 VPN 处理。',
                  this.store.ipv6Enabled,
                  (v: boolean): void => {
                    this.store.ipv6Enabled = v;
                    this.store.applyNetworkSettings();
                  }
                )

                this.switchSettingRow(
                  'WebRTC 防泄露',
                  '拦截 STUN 探测，可能影响语音、视频和 P2P 连接。',
                  this.store.blockStun,
                  (v: boolean): void => {
                    this.store.blockStun = v;
                    this.store.applyNetworkSettings();
                  }
                )

                this.switchSettingRow(
                  '域名嗅探',
                  '',
                  this.store.snifferEnabled,
                  (v: boolean): void => {
                    this.store.snifferEnabled = v;
                    this.store.applyNetworkSettings();
                  }
                )
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
              })
            }
            .contentStartOffset(64 + this.titleTopInset)
            .contentEndOffset(this.bottomInset)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.Top)
          } else if (this.activeSettingsKey() === 'general') {
            Scroll() {
              Column({ space: 12 }) {
                this.switchSettingRow(
                  '自动运行',
                  '自动运行会在打开应用时启动代理。',
                  this.store.autoRun,
                  (v: boolean): void => {
                    this.store.autoRun = v;
                    this.store.notify();
                  }
                )
                this.switchSettingRow(
                  '统一延迟',
                  '',
                  this.store.unifiedDelay,
                  (v: boolean): void => {
                    this.store.unifiedDelay = v;
                    this.store.notify();
                  }
                )
                this.switchSettingRow(
                  'TCP 并发',
                  '',
                  this.store.tcpConcurrent,
                  (v: boolean): void => {
                    this.store.tcpConcurrent = v;
                    this.store.notify();
                  }
                )
                this.switchSettingRow(
                  '自动关闭连接',
                  '',
                  this.store.autoCloseConnections,
                  (v: boolean): void => {
                    this.store.autoCloseConnections = v;
                    this.store.notify();
                  }
                )

                Column({ space: 8 }) {
                  Text('测速链接')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)
                  TextInput({ text: this.testUrlInput })
                    .height(40)
                    .fontSize(13)
                    .fontColor(this.palette.onSurface)
                    .backgroundColor(this.palette.block)
                    .borderRadius(12)
                    .onChange((val: string): void => {
                      this.testUrlInput = val;
                      this.store.testUrl = val;
                    })
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(26)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
              })
            }
            .contentStartOffset(64 + this.titleTopInset)
            .contentEndOffset(this.bottomInset)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.Top)
          } else if (this.activeSettingsKey() === 'disclaimer') {
            Scroll() {
              Column({ space: 14 }) {
                Column({ space: 8 }) {
                  Text('软件性质')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)
                  Text('本软件是基于 Clash.Meta（mihomo）内核的开源网络代理客户端，仅提供配置管理、规则分流与流量转发等本地工具功能。\n本软件自身不提供任何代理服务器、节点、订阅、机场或网络接入服务，也不与任何此类服务的提供者存在合作、代理或担保关系。')
                    .fontSize(13)
                    .lineHeight(20)
                    .fontColor(this.palette.onSurfaceVariant)
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(24)
                .alignItems(HorizontalAlign.Start)

                Column({ space: 8 }) {
                  Text('数据收集与隐私')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)
                  Text('本软件不会收集或上传你的订阅地址、节点信息、配置内容、访问的网站、连接记录、流量内容和日志，这些数据仅保存在你的设备本地，开发者无法获取。')
                    .fontSize(13)
                    .lineHeight(20)
                    .fontColor(this.palette.onSurfaceVariant)
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(24)
                .alignItems(HorizontalAlign.Start)

                Column({ space: 8 }) {
                  Text('开源协议')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)
                  Text('本软件以 GPL-3.0 协议开源，你可以依该协议运行、研究、修改和分发本软件；分发本软件或其修改版本时，须同样以 GPL-3.0 协议提供源代码并保留原有的版权声明。')
                    .fontSize(13)
                    .lineHeight(20)
                    .fontColor(this.palette.onSurfaceVariant)
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.palette.card)
                .borderRadius(24)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
              })
            }
            .contentStartOffset(64 + this.titleTopInset)
            .contentEndOffset(this.bottomInset)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.Top)
          } else if (this.activeSettingsKey() === 'about') {
            Scroll() {
              Column({ space: 16 }) {
                Column({ space: 10 }) {
                  Image($r('app.media.startIcon'))
                    .width(76)
                    .height(76)
                    .borderRadius(22)

                  Text('LexiClash')
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)

                  Text('v1.0.1')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.palette.primary)

                  Text('基于 ClashMeta 的多平台代理客户端，简单易用，开源无广告。')
                    .fontSize(13)
                    .fontColor(this.palette.onSurfaceVariant)
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .padding(24)
                .backgroundColor(this.palette.card)
                .borderRadius(28)
                .alignItems(HorizontalAlign.Center)

                Column({ space: 12 }) {
                  Text(this.selectedLocaleLang === 'en_US' ? 'Contributor' : '贡献者')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)

                  Row({ space: 14 }) {
                    Image($r('app.media.peryixing_lab'))
                      .width(48)
                      .height(48)
                      .borderRadius(24)
                    Column({ space: 2 }) {
                      Text('peryixing-lab')
                        .fontSize(15)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.palette.onSurface)
                      Text('github.com/peryixing-lab')
                        .fontSize(12)
                        .fontColor(this.palette.onSurfaceVariant)
                    }
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(20)
                .backgroundColor(this.palette.card)
                .borderRadius(26)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .constraintSize({ maxWidth: ResponsiveLayout.readingMaxWidth(this.windowWidthVp) })
              .padding({
                left: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                right: ResponsiveLayout.horizontalPadding(this.windowWidthVp),
                bottom: ResponsiveLayout.secondaryBottomPadding(this.bottomInset)
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
          header: (): void => { this.mainToolsHeader(); },
          bodyContent: (): void => { this.mainToolsBody(); }
        })
      }
      .width('100%')
      .height('100%')

      if (this.subPage === 'requests') {
        Column() {
          RequestsMonitorPage({
            palette: this.palette,
            revisionTick: this.revisionTick,
            showBackButton: true,
            onBack: (): void => {
              this.subPage = 'main';
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.page)
        .zIndex(1)
        .transition(ImmersivePageTransition.secondaryPage())
      } else if (this.subPage === 'dns') {
        Column() {
          DnsQueriesMonitorPage({
            palette: this.palette,
            revisionTick: this.revisionTick,
            showBackButton: true,
            onBack: (): void => {
              this.subPage = 'main';
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.page)
        .zIndex(1)
        .transition(ImmersivePageTransition.secondaryPage())
      } else if (this.subPage === 'resources') {
        Column() {
          ExternalResourcesPage({
            palette: this.palette,
            revisionTick: this.revisionTick,
            showBackButton: true,
            onBack: (): void => {
              this.subPage = 'main';
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.page)
        .zIndex(1)
        .transition(ImmersivePageTransition.secondaryPage())
      } else if (this.subPage === 'logs') {
        Column() {
          LogsMonitorPage({
            palette: this.palette,
            revisionTick: this.revisionTick,
            showBackButton: true,
            onBack: (): void => {
              this.subPage = 'main';
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.page)
        .zIndex(1)
        .transition(ImmersivePageTransition.secondaryPage())
      } else if (this.subPage !== 'main') {
        Column() {
          ImmersiveTitlePage({
            palette: this.palette,
            immersiveEnabled: this.store.liquidGlass,
            scrollUnderTitle: true,
            revisionTick: this.revisionTick,
            header: (): void => { this.subPageHeader(); },
            bodyContent: (): void => { this.subPageBody(); }
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

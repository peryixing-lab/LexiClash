import { LengthMetrics, uiMaterial } from '@kit.ArkUI';
import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';
import { ImmersiveTitleStyle } from '../common/ImmersiveTitleStyle';

@Component
export struct ImmersiveTitlePage {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop immersiveEnabled: boolean = true;
  @Prop revisionTick: number = 0;
  @Prop scrollUnderTitle: boolean = false;
  @StorageProp('lexiTopInset') titleTopInset: number = 0;
  @StorageProp('lexiTitleButtonWidth') titleButtonWidth: number = 0;
  @BuilderParam header: () => void;
  @BuilderParam bodyContent: () => void;

  private titleTheme(): CustomTheme {
    return { colors: { compBackgroundGray: this.palette.page } };
  }

  @Builder
  materialTitle() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.immersiveEnabled) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [
              [ImmersiveTitleStyle.scrim(this.palette), 0],
              [ImmersiveTitleStyle.scrim(this.palette), (48 + this.titleTopInset) / (64 + this.titleTopInset)],
              [Color.Transparent, 1]
            ]
          })
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }
      Row() {
        this.header()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.titleTopInset, right: this.titleButtonWidth })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.immersiveEnabled ? Color.Transparent : this.palette.page)
    .clip(false)
  }

  build() {
    WithTheme({ theme: this.titleTheme() }) {
      Navigation() {
        Column() {
          this.bodyContent()
        }
        .width('100%')
        .height('100%')
        // Main scrolls reserve this space inside the Scroll so it can scroll away.
        .padding({ top: this.scrollUnderTitle ? 0 : 64 + this.titleTopInset })
      }
      .mode(NavigationMode.Stack)
      .titleMode(NavigationTitleMode.Mini)
      .hideBackButton(true)
      .hideToolBar(true)
      .title({ builder: (): void => { this.materialTitle(); }, height: 64 + this.titleTopInset }, {
        barStyle: BarStyle.STACK,
        backgroundColor: Color.Transparent,
        scrollEffectOptions: this.immersiveEnabled && this.scrollUnderTitle
          ? {
            scrollEffectType: ScrollEffectType.GRADUAL_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(8),
            blurEffectiveEndOffset: LengthMetrics.vp(32)
          }
          : undefined,
        systemMaterial: this.immersiveEnabled && this.scrollUnderTitle ? undefined : uiMaterial.Material.empty
      })
      .width('100%')
      .height('100%')
      .background(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }
}

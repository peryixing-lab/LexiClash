// LexiLaunchScreen.ets — Concentric Halo & Progressive Step Launch Screen (modeled on LexiNote-Harmony)
import { curves } from '@kit.ArkUI';
import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';

@Component
export struct LexiLaunchScreen {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop startupStep: number = 0;
  @Prop errorMessage: string = '';
  @Prop reduceMotion: boolean = false;
  @Prop localeLang: string = 'zh_CN';
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  onRetry: () => void = (): void => {};

  @State launchWidth: number = 390;
  @State launchHeight: number = 760;
  @State iconScale: number = 0.94;
  @State iconOpacity: number = 0;
  @State outerRingScale: number = 0.84;
  @State midRingScale: number = 0.88;
  @State haloPulse: boolean = false;
  private entranceCurve: curves.ICurve = curves.cubicBezierCurve(0.23, 1, 0.32, 1);
  private pulseTimerId: number = -1;
  private isUnmounted: boolean = false;

  aboutToAppear(): void {
    this.isUnmounted = false;
    if (this.reduceMotion) {
      this.iconScale = 1;
      this.iconOpacity = 1;
      this.outerRingScale = 1;
      this.midRingScale = 1;
      return;
    }
    this.getUIContext().animateTo({
      duration: 280,
      curve: this.entranceCurve
    }, (): void => {
      this.iconScale = 1;
      this.iconOpacity = 1;
      this.outerRingScale = 1;
      this.midRingScale = 1;
    });
    this.pulseTimerId = setTimeout((): void => {
      this.pulseTimerId = -1;
      if (this.isUnmounted) {
        return;
      }
      this.getUIContext().animateTo({
        duration: 850,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, (): void => {
        this.haloPulse = true;
      });
    }, 240);
  }

  aboutToDisappear(): void {
    this.isUnmounted = true;
    if (this.pulseTimerId !== -1) {
      clearTimeout(this.pulseTimerId);
      this.pulseTimerId = -1;
    }
  }

  private compact(): boolean {
    return this.launchHeight < 620;
  }

  private brandSize(): number {
    const preferred: number = this.compact() ? Math.max(104, this.launchHeight * 0.32) : 268;
    return Math.min(preferred, Math.max(80, this.launchWidth - 48));
  }

  private contentMinHeight(): number {
    const footerHeight: number = this.compact() ? 34 : 70;
    return Math.max(0, this.launchHeight - (this.compact() ? 16 : 24) - footerHeight - this.topInset - this.bottomInset);
  }

  private stepLabel(): string {
    const isEn: boolean = this.localeLang === 'en_US';
    if (this.startupStep === 1) {
      return isEn ? 'Preparing mihomo proxy core' : '正在加载 mihomo 代理内核';
    }
    if (this.startupStep >= 2) {
      return isEn ? 'Restoring tunnel & network status' : '正在恢复网络与服务状态';
    }
    return isEn ? 'Loading local profiles & settings' : '正在初始化本地配置';
  }

  @Builder
  brandMark() {
    Stack() {
      Column()
        .width(this.brandSize() * 260 / 268)
        .height(this.brandSize() * 260 / 268)
        .borderRadius(this.brandSize() / 2)
        .border({ width: 1, color: this.palette.divider })
        .opacity(this.haloPulse ? 0.45 : 0.65)
        .scale({
          x: this.outerRingScale * (this.haloPulse ? 1.035 : 1),
          y: this.outerRingScale * (this.haloPulse ? 1.035 : 1)
        })

      Column()
        .width(this.brandSize() * 216 / 268)
        .height(this.brandSize() * 216 / 268)
        .borderRadius(this.brandSize() / 2)
        .backgroundColor(this.palette.primarySoft)
        .opacity(this.haloPulse ? 0.42 : 0.32)
        .scale({
          x: this.midRingScale * (this.haloPulse ? 1.02 : 1),
          y: this.midRingScale * (this.haloPulse ? 1.02 : 1)
        })

      Column()
        .width(this.brandSize() * 172 / 268)
        .height(this.brandSize() * 172 / 268)
        .borderRadius(this.brandSize() / 2)
        .backgroundColor(this.palette.primarySoft)
        .opacity(0.55)
        .scale({ x: this.midRingScale, y: this.midRingScale })

      Image($r('app.media.startIcon'))
        .width(this.brandSize() * 124 / 268)
        .height(this.brandSize() * 124 / 268)
        .borderRadius(this.brandSize() * 32 / 268)
        .objectFit(ImageFit.Contain)
        .shadow({
          radius: 24,
          color: this.palette.isDark ? '#38000000' : '#1E000000',
          offsetX: 0,
          offsetY: 8
        })
        .scale({ x: this.iconScale, y: this.iconScale })
        .opacity(this.iconOpacity)
        .accessibilityLevel('no')
    }
    .width(this.brandSize())
    .height(this.brandSize())
    .accessibilityLevel('no')
  }

  @Builder
  progressStep(index: number) {
    Column()
      .width(this.startupStep === index ? 24 : 12)
      .height(4)
      .borderRadius(2)
      .backgroundColor(index <= this.startupStep ? this.palette.primary : this.palette.divider)
      .animation({ duration: this.reduceMotion ? 0 : 180, curve: Curve.EaseOut })
      .accessibilityLevel('no')
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          this.brandMark()

          Text('LexiClash')
            .fontSize(this.compact() ? 26 : 30)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurface)
            .letterSpacing(0.3)
            .margin({ top: 10 })
            .opacity(this.iconOpacity)

          Column({ space: this.compact() ? 12 : 16 }) {
            if (this.errorMessage.length > 0) {
              Text(this.localeLang === 'en_US' ? 'Unable to initialize workspace' : '代理环境暂时未能初始化')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.onSurface)
                .textAlign(TextAlign.Center)

              Text(this.errorMessage)
                .fontSize(12)
                .lineHeight(20)
                .fontColor(this.palette.onSurfaceVariant)
                .textAlign(TextAlign.Center)
                .constraintSize({ maxWidth: 288 })

              Button(this.localeLang === 'en_US' ? 'Retry' : '重新加载', { type: ButtonType.Capsule })
                .height(44)
                .padding({ left: 28, right: 28 })
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .backgroundColor(this.palette.primary)
                .fontColor(this.palette.onPrimary)
                .onClick((): void => {
                  this.onRetry();
                })
            } else {
              Row({ space: 6 }) {
                this.progressStep(0)
                this.progressStep(1)
                this.progressStep(2)
              }
              .height(4)
              .accessibilityLevel('no')

              Text(this.stepLabel())
                .fontSize(12)
                .fontColor(this.palette.onSurfaceVariant)
                .textAlign(TextAlign.Center)
                .accessibilityText(this.stepLabel())
            }
          }
          .margin({ top: this.compact() ? 22 : 36 })
          .constraintSize({ minHeight: this.compact() ? 58 : 84 })
        }
        .width('100%')
        .constraintSize({ minHeight: this.contentMinHeight(), maxWidth: 560 })
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 24,
      right: 24,
      top: (this.compact() ? 16 : 24) + this.topInset,
      bottom: (this.compact() ? 16 : 24) + this.bottomInset
    })
    .backgroundColor(this.palette.page)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_old: Area, current: Area): void => {
      const w: number = Number(current.width);
      const h: number = Number(current.height);
      if (w > 0) { this.launchWidth = w; }
      if (h > 0) { this.launchHeight = h; }
    })
  }
}

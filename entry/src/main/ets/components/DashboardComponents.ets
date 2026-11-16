// DashboardComponents.ets — Pure Mobile FlClash Dashboard Cards & Editor (No Desktop View, No Pre-installed Examples)

import { pasteboard } from '@kit.BasicServicesKit';
import { FlClashColorPalette, I18n, ThemeManager } from '../common/ThemeManager';
import {
  DashboardFeedKind,
  DashboardWidgetConfigItem,
  OutboundModeType,
  ProfileSubscriptionModel,
  ProxyGroupItem,
  ServiceProbeItem
} from '../core/CoreProtocol';
import { AppStateStore } from '../store/AppStateStore';

@Component
export struct WaveLineChartView {
  @Prop waveValues: number[] = [];
  @Prop lineColor: string = '#007AFF';
  @Prop fillAlphaHex: string = '#26007AFF';
  @Prop chartHeight: number = 50;
  @Prop @Watch('onRevisionChange') revisionTick: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  onRevisionChange(): void {
    this.drawWave();
  }

  private drawWave(): void {
    const w: number = this.ctx.width;
    const h: number = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, w, h);
    const pts: number[] = this.waveValues;
    if (pts.length < 2) {
      return;
    }

    // In FlClash traffic.dart: idle traffic (all zero) leaves no line
    let hasNonZero: boolean = false;
    let maxVal: number = 100;
    for (let i = 0; i < pts.length; i++) {
      if (pts[i] > 0) {
        hasNonZero = true;
      }
      if (pts[i] > maxVal) {
        maxVal = pts[i];
      }
    }
    if (!hasNonZero) {
      return;
    }

    const stepX: number = w / (pts.length - 1);
    const topPad: number = 6;
    const usableH: number = h - topPad - 2;

    this.ctx.beginPath();
    for (let i = 0; i < pts.length; i++) {
      const x: number = i * stepX;
      const ratio: number = Math.min(1, Math.max(0, pts[i] / maxVal));
      const y: number = topPad + usableH * (1 - ratio);
      if (i === 0) {
        this.ctx.moveTo(x, y);
      } else {
        const prevX: number = (i - 1) * stepX;
        const prevRatio: number = Math.min(1, Math.max(0, pts[i - 1] / maxVal));
        const prevY: number = topPad + usableH * (1 - prevRatio);
        const midX: number = (prevX + x) / 2;
        this.ctx.bezierCurveTo(midX, prevY, midX, y, x, y);
      }
    }
    this.ctx.strokeStyle = this.lineColor;
    this.ctx.lineWidth = 2.0;
    this.ctx.lineCap = 'round';
    this.ctx.stroke();

    this.ctx.lineTo(w, h);
    this.ctx.lineTo(0, h);
    this.ctx.closePath();
    this.ctx.fillStyle = this.fillAlphaHex;
    this.ctx.fill();
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(this.chartHeight)
      .onReady((): void => {
        this.drawWave();
      })
  }
}

@Component
export struct WavyProgressView {
  @Prop progressRatio: number = 0.0;
  @Prop activeColor: string = '#007AFF';
  @Prop trackColor: string = '#3C3C44';
  @Prop @Watch('onProgressChanged') revisionTick: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  onProgressChanged(): void {
    this.drawWavyBar();
  }

  private drawWavyBar(): void {
    const w: number = this.ctx.width;
    const h: number = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, w, h);

    const mid: number = h / 2;
    const stroke: number = 3.5;
    const amplitude: number = 2.8;
    const wavelength: number = 14.0;
    const gap: number = 6.0;
    const stopRadius: number = 2.2;
    const startX: number = stroke / 2;
    const endX: number = w - stroke / 2;
    const clamped: number = Math.min(1.0, Math.max(0.0, this.progressRatio));
    const splitX: number = startX + (endX - startX) * clamped;

    if (clamped > 0) {
      this.ctx.beginPath();
      this.ctx.moveTo(startX, mid);
      for (let x = startX; x <= splitX; x += 1) {
        const y: number = mid + amplitude * Math.sin(((x - startX) / wavelength) * 2 * Math.PI);
        this.ctx.lineTo(x, y);
      }
      this.ctx.strokeStyle = this.activeColor;
      this.ctx.lineWidth = stroke;
      this.ctx.lineCap = 'round';
      this.ctx.stroke();
    }

    const trackStart: number = clamped > 0 ? (splitX + gap + stroke) : startX;
    if (trackStart < endX - stopRadius * 2) {
      this.ctx.beginPath();
      this.ctx.moveTo(trackStart, mid);
      this.ctx.lineTo(endX - stopRadius * 2 - gap, mid);
      this.ctx.strokeStyle = this.trackColor;
      this.ctx.lineWidth = stroke;
      this.ctx.lineCap = 'round';
      this.ctx.stroke();
    }

    if (clamped < 1.0) {
      this.ctx.beginPath();
      this.ctx.arc(endX - stopRadius, mid, stopRadius, 0, 2 * Math.PI);
      this.ctx.fillStyle = this.activeColor;
      this.ctx.fill();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(14)
      .onReady((): void => {
        this.drawWavyBar();
      })
  }
}

@Component
export struct CurrentOutboundCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  onOpenIpSheet: () => void = (): void => {};
  onRequireProfile: () => void = (): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

  private isRunningReactive(): boolean {
    return this.revisionTick >= 0 && this.store.isRunning;
  }

  private isTransitioningReactive(): boolean {
    return this.revisionTick >= 0 && this.store.isVpnTransitioning;
  }

  private getStatusBadgeText(): string {
    if (this.isTransitioningReactive()) {
      if (this.isRunningReactive()) {
        return this.store.localeLang === 'en_US' ? 'Stopping…' : '断开中…';
      }
      return this.store.localeLang === 'en_US' ? 'Connecting…' : '连接中…';
    }
    return this.isRunningReactive()
      ? I18n.t('running', this.store.localeLang)
      : I18n.t('stopped', this.store.localeLang);
  }

  private hasProfilesReactive(): boolean {
    return this.revisionTick >= 0 && this.store.hasProfiles();
  }

  private getCoreUnavailableNotice(): string {
    const _t: number = this.revisionTick;
    if (_t < 0) {
      return '';
    }
    const err: string = this.store.lastOperationError.length > 0
      ? this.store.lastOperationError
      : this.store.getRuntimeUnavailableReason();
    return err;
  }

  private showConnectUnavailableFeedback(): void {
    const reason: string = this.getCoreUnavailableNotice();
    const msg: string = reason.length > 0
      ? reason
      : (this.store.localeLang === 'en_US'
        ? 'Failed to start mihomo core or system VPN. Check your profile and VPN permission.'
        : '代理核心或系统 VPN 启动失败，请检查配置有效性及系统 VPN 授权状态后重试。');
    try {
      this.getUIContext().showAlertDialog({
        title: this.store.localeLang === 'en_US' ? 'Cannot Connect' : '无法启动代理连接',
        message: msg,
        confirm: {
          value: this.store.localeLang === 'en_US' ? 'OK' : '知道了',
          action: (): void => {}
        }
      });
    } catch (_dialogErr) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: msg, duration: 3000 });
      } catch (_toastErr) {
        // ignore
      }
    }
  }

  private async handleToggleConnect(): Promise<void> {
    const toggled: boolean = await this.store.toggleRunningAsync();
    if (toggled) {
      try {
        this.getUIContext().animateTo({ duration: 350, curve: Curve.EaseOut }, (): void => {});
      } catch (_animErr) {
        // ignore
      }
    } else {
      this.showConnectUnavailableFeedback();
    }
  }

  private getDisplayedIp(): string {
    const _t: number = this.revisionTick;
    if (_t >= 0 && this.store.isProbingIp) {
      return this.store.localeLang === 'en_US' ? 'Checking...' : '检测中…';
    }
    if (this.store.outboundIpInfo.ip.length === 0) {
      if (this.store.outboundProbeFailed) {
        return this.store.localeLang === 'en_US' ? 'Check failed' : '检测失败';
      }
      return '—';
    }
    if (this.store.hideIp) {
      return '*****';
    }
    return this.store.outboundIpInfo.ip;
  }

  private getRunTimeText(): string {
    if (!this.isRunningReactive()) {
      return '—';
    }
    return ThemeManager.formatDurationHMS(this.store.runTimeSeconds);
  }

  private getOrgText(): string {
    const _t: number = this.revisionTick;
    if (_t >= 0 && this.store.outboundIpInfo.organization.length === 0) {
      return '—';
    }
    return this.store.outboundIpInfo.organization;
  }

  private getDisplayedFlag(): string {
    const _t: number = this.revisionTick;
    if (_t < 0) {
      return '';
    }
    return ThemeManager.countryFlagEmoji(
      this.store.outboundIpInfo.countryCode,
      this.store.outboundIpInfo.countryName
    );
  }

  private getDisplayedCountryName(): string {
    const _t: number = this.revisionTick;
    if (_t < 0) {
      return '';
    }
    return ThemeManager.countryDisplayName(
      this.store.outboundIpInfo.countryCode,
      this.store.outboundIpInfo.countryName,
      this.store.localeLang
    );
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // Decorative background shape (FlClash current_outbound.dart _decorationSize: 240 on mobile)
      Stack()
        .width(210)
        .height(210)
        .borderRadius(95)
        .backgroundColor(this.isRunningReactive() ? this.palette.primarySoft : this.palette.block)
        .rotate({ angle: this.isRunningReactive() ? 30 : 0 })
        .offset({ x: 48, y: -54 })
        .animation({ duration: 400, curve: Curve.EaseOut })

      Row({ space: 10 }) {
        Column() {
          // Header row: Status icon + title + Running/Not running pill chip
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.shield_checkered'))
              .fontSize(16)
              .fontColor([this.palette.onSurfaceVariant])
            Text(I18n.t('status', this.store.localeLang))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)

            Row({ space: 5 }) {
              if (this.isRunningReactive()) {
                Circle({ width: 6, height: 6 })
                  .fill(this.palette.ok)
              }
              Text(this.getStatusBadgeText())
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isRunningReactive() ? this.palette.onOkContainer : this.palette.onSurfaceVariant)
            }
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .backgroundColor(this.isRunningReactive() ? this.palette.okContainer : this.palette.block)
            .borderRadius(12)
          }
          .alignItems(VerticalAlign.Center)

          // Exit Row: Flag + Country + IP + Chips
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Stack({ alignContent: Alignment.Center }) {
                Column()
                  .width(48)
                  .height(48)
                  .borderRadius(17)
                  .backgroundColor(this.palette.inset)
                  .rotate({ angle: (this.revisionTick >= 0 && this.store.isProbingIp) ? 180 : 0 })
                  .animation({ duration: 450, curve: Curve.EaseInOut })

                if (this.getDisplayedFlag().length > 0) {
                  Text(this.getDisplayedFlag())
                    .fontSize(26)
                } else {
                  SymbolGlyph($r('sys.symbol.globe_badge_heart'))
                    .fontSize(20)
                    .fontColor([this.isRunningReactive() ? this.palette.onSurface : this.palette.onSurfaceVariant])
                }
              }

              if (this.getDisplayedCountryName().length > 0) {
                Text(this.getDisplayedCountryName())
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.onSurfaceVariant)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 68 })
                  .textAlign(TextAlign.Center)
              }
            }
            .alignItems(HorizontalAlign.Center)
            .onClick((): void => {
              this.store.refreshOutboundIp();
            })

            Column({ space: 5 }) {
              Text(this.getDisplayedIp())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isRunningReactive() ? this.palette.onSurface : this.palette.onSurfaceVariant)
                .maxLines(1)
                .onClick((): void => {
                  if (this.store.outboundIpInfo.ip.length > 0) {
                    this.onOpenIpSheet();
                  } else {
                    this.store.refreshOutboundIp();
                  }
                })

              if (this.revisionTick >= 0 && this.store.outboundIpInfo.ip.length > 0) {
                Row({ space: 6 }) {
                  Text(ThemeManager.formatIpTypeLabel(this.store.outboundIpInfo.ipType, this.store.localeLang))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.palette.onSurfaceVariant)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .backgroundColor(this.palette.block)
                    .borderRadius(10)

                  Text(ThemeManager.formatIpQualityLabel(this.store.outboundIpInfo.qualityLevel, this.store.localeLang))
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeManager.ipQualityTextColor(this.store.outboundIpInfo.qualityLevel, this.palette))
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .backgroundColor(ThemeManager.ipQualityBgColor(this.store.outboundIpInfo.qualityLevel, this.palette))
                    .borderRadius(10)
                }
              } else {
                Row({ space: 6 }) {
                  Text(this.store.localeLang === 'en_US' ? 'Unknown' : '未知')
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.palette.onSurfaceVariant)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .backgroundColor(this.palette.block)
                    .borderRadius(10)
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .margin({ top: 14, bottom: 16 })
          .alignItems(VerticalAlign.Center)

          // Bottom cells: Run time & Organization
          Row({ space: 24 }) {
            Column({ space: 2 }) {
              Text(I18n.t('runTime', this.store.localeLang))
                .fontSize(12)
                .fontColor(this.palette.onSurfaceVariant)
              Text(this.getRunTimeText())
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
            }
            .alignItems(HorizontalAlign.Start)

            Column({ space: 2 }) {
              Text(I18n.t('organization', this.store.localeLang))
                .fontSize(12)
                .fontColor(this.palette.onSurfaceVariant)
              Text(this.getOrgText())
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }

          if (!this.isRunningReactive() && this.hasProfilesReactive() && this.getCoreUnavailableNotice().length > 0) {
            Text(this.getCoreUnavailableNotice())
              .fontSize(11)
              .fontColor(this.palette.error)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .margin({ top: 12 })
              .width('100%')
              .backgroundColor(this.palette.errorContainer)
              .borderRadius(12)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // Start / Pause Button (disabled tone2 when no profile exists, matching FlClash current_outbound.dart)
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(82)
            .height(82)
            .borderRadius(this.isRunningReactive() ? 26 : 41)
            .backgroundColor(this.hasProfilesReactive() ? this.palette.primary : this.palette.inset)
            .rotate({ angle: this.isRunningReactive() ? 22.5 : 0 })
            .animation({ duration: 380, curve: Curve.EaseOut })

          Column()
            .width(82)
            .height(82)
            .borderRadius(this.isRunningReactive() ? 26 : 41)
            .backgroundColor(this.hasProfilesReactive() ? this.palette.primary : this.palette.inset)
            .rotate({ angle: this.isRunningReactive() ? 67.5 : 0 })
            .animation({ duration: 380, curve: Curve.EaseOut })

          SymbolGlyph(this.isRunningReactive() ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(26)
            .fontColor([this.hasProfilesReactive() ? this.palette.onPrimary : this.palette.onSurfaceVariant])
        }
        .id('dashboard-connect-button')
        .width(88)
        .height(88)
        .opacity(this.isTransitioningReactive() ? 0.72 : 1)
        .onClick((): void => {
          if (!this.store.hasProfiles()) {
            try {
              this.getUIContext().getPromptAction().showToast({
                message: this.store.localeLang === 'en_US'
                  ? 'Add a profile to get started'
                  : '添加一个配置文件后即可开始使用',
                duration: 1600
              });
            } catch (_err) {
              // ignore
            }
            this.onRequireProfile();
            return;
          }
          if (this.store.isVpnTransitioning) {
            return;
          }
          this.handleToggleConnect();
        })
      }
      .width('100%')
      .padding({ left: 20, right: 16, top: 18, bottom: 18 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.palette.card)
    .borderRadius(34)
    .clip(true)
  }
}

@Component
export struct MobileNetworkSpeedCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;

  private store: AppStateStore = AppStateStore.getInstance();

  private getSpeedNum(isUp: boolean): string {
    const val: number = isUp ? this.store.currentUploadSpeed : this.store.currentDownloadSpeed;
    if (val <= 0) {
      return '0';
    }
    return ThemeManager.formatSpeedValueAndUnit(val)[0];
  }

  private getSpeedUnit(isUp: boolean): string {
    const val: number = isUp ? this.store.currentUploadSpeed : this.store.currentDownloadSpeed;
    if (val <= 0) {
      return 'B/s';
    }
    return ThemeManager.formatSpeedValueAndUnit(val)[1];
  }

  private getTotalStr(isUp: boolean): string {
    const val: number = isUp ? this.store.totalUploadBytes : this.store.totalDownloadBytes;
    return `${I18n.t('total', this.store.localeLang)} ${ThemeManager.formatBytes(val)}`;
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.bolt_fill'))
          .fontSize(17)
          .fontColor([this.palette.onSurfaceVariant])
        Text(I18n.t('networkSpeed', this.store.localeLang))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        // Upload Tile (block level)
        Stack({ alignContent: Alignment.Bottom }) {
          WaveLineChartView({
            waveValues: this.store.uploadWaveHistory,
            lineColor: this.palette.series2,
            fillAlphaHex: this.palette.primarySoft,
            chartHeight: 50,
            revisionTick: this.revisionTick
          })

          Column({ space: 4 }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_up'))
                .fontSize(13)
                .fontColor([this.palette.onSurfaceVariant])
              Text(I18n.t('upload', this.store.localeLang))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.onSurfaceVariant)
            }
            Row({ space: 4 }) {
              Text(this.getSpeedNum(true))
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
              Text(this.getSpeedUnit(true))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.onSurfaceVariant)
                .margin({ bottom: 2 })
            }
            .alignItems(VerticalAlign.Bottom)
            Text(this.getTotalStr(true))
              .fontSize(11)
              .fontColor(this.palette.onSurfaceVariant)
            Blank()
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 12 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .height(114)
        .backgroundColor(this.palette.block)
        .borderRadius(22)
        .clip(true)

        // Download Tile (block level)
        Stack({ alignContent: Alignment.Bottom }) {
          WaveLineChartView({
            waveValues: this.store.downloadWaveHistory,
            lineColor: this.palette.primary,
            fillAlphaHex: this.palette.primarySoft,
            chartHeight: 50,
            revisionTick: this.revisionTick
          })

          Column({ space: 4 }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_down'))
                .fontSize(13)
                .fontColor([this.palette.primary])
              Text(I18n.t('download', this.store.localeLang))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.onSurfaceVariant)
            }
            Row({ space: 4 }) {
              Text(this.getSpeedNum(false))
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
              Text(this.getSpeedUnit(false))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.onSurfaceVariant)
                .margin({ bottom: 2 })
            }
            .alignItems(VerticalAlign.Bottom)
            Text(this.getTotalStr(false))
              .fontSize(11)
              .fontColor(this.palette.onSurfaceVariant)
            Blank()
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 12 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .height(114)
        .backgroundColor(this.palette.block)
        .borderRadius(22)
        .clip(true)
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.palette.card)
    .borderRadius(34)
  }
}

@Component
export struct OutboundModeCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;

  private store: AppStateStore = AppStateStore.getInstance();

  private isModeSelected(mode: OutboundModeType): boolean {
    return this.revisionTick >= 0 && this.store.outboundMode === mode;
  }

  @Builder
  modeSegmentButton(mode: OutboundModeType, labelKey: string, isFirst: boolean, isLast: boolean) {
    Column({ space: 3 }) {
      if (mode === 'rule') {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(17)
          .fontColor([this.isModeSelected(mode) ? this.palette.onPrimary : this.palette.onSurfaceVariant])
      } else if (mode === 'global') {
        SymbolGlyph($r('sys.symbol.globe_badge_heart'))
          .fontSize(17)
          .fontColor([this.isModeSelected(mode) ? this.palette.onPrimary : this.palette.onSurfaceVariant])
      } else {
        SymbolGlyph($r('sys.symbol.paperplane'))
          .fontSize(17)
          .fontColor([this.isModeSelected(mode) ? this.palette.onPrimary : this.palette.onSurfaceVariant])
      }
      Text(I18n.t(labelKey, this.store.localeLang))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isModeSelected(mode) ? this.palette.onPrimary : this.palette.onSurface)
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isModeSelected(mode) ? this.palette.primary : this.palette.block)
    .borderRadius({
      topLeft: isFirst ? 26 : 12,
      bottomLeft: isFirst ? 26 : 12,
      topRight: isLast ? 26 : 12,
      bottomRight: isLast ? 26 : 12
    })
    .animation({ duration: 220, curve: Curve.EaseOut })
    .onClick((): void => {
      this.store.setOutboundMode(mode);
    })
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
          .fontSize(17)
          .fontColor([this.palette.onSurfaceVariant])
        Text(I18n.t('outboundMode', this.store.localeLang))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 4 }) {
        this.modeSegmentButton('rule', 'rule', true, false)
        this.modeSegmentButton('global', 'global', false, false)
        this.modeSegmentButton('direct', 'direct', false, true)
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.palette.card)
    .borderRadius(34)
  }
}

@Component
export struct VpnCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  onRequireProfile: () => void = (): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

  private isVpnEnabledReactive(): boolean {
    return this.revisionTick >= 0 && this.store.vpnEnabled;
  }

  private isTransitioningReactive(): boolean {
    return this.revisionTick >= 0 && this.store.isVpnTransitioning;
  }

  private hasProfilesReactive(): boolean {
    return this.revisionTick >= 0 && this.store.hasProfiles();
  }

  private getVpnSubtitle(): string {
    if (this.isTransitioningReactive()) {
      return this.isVpnEnabledReactive()
        ? (this.store.localeLang === 'en_US' ? 'Stopping VPN…' : '正在断开系统 VPN…')
        : (this.store.localeLang === 'en_US' ? 'Starting VPN…' : '正在拉起系统 VPN…');
    }
    if (this.isVpnEnabledReactive()) {
      return I18n.t('enabled', this.store.localeLang);
    }
    if (!this.hasProfilesReactive()) {
      return this.store.localeLang === 'en_US' ? 'Add a profile first' : '请先添加配置';
    }
    return this.store.localeLang === 'en_US' ? 'Tap to start system VPN' : '点击开启系统 VPN';
  }

  private showVpnFailureDialog(): void {
    const err: string = this.store.lastOperationError.length > 0
      ? this.store.lastOperationError
      : this.store.getRuntimeUnavailableReason();
    const message: string = err.length > 0
      ? err
      : (this.store.localeLang === 'en_US'
        ? 'Failed to start system VPN extension. Please confirm VPN authorization and profile settings.'
        : '系统 VPN 启动失败，请检查配置有效性及系统 VPN 授权状态后重试。');
    try {
      this.getUIContext().showAlertDialog({
        title: this.store.localeLang === 'en_US' ? 'VPN Start Failed' : 'VPN 启动失败',
        message: message,
        confirm: {
          value: this.store.localeLang === 'en_US' ? 'OK' : '知道了',
          action: (): void => {}
        }
      });
    } catch (_dialogErr) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: message, duration: 3000 });
      } catch (_toastErr) {
        // ignore
      }
    }
  }

  private async handleToggleVpn(): Promise<void> {
    if (!this.store.hasProfiles()) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: this.store.localeLang === 'en_US'
            ? 'Add a profile to get started'
            : '添加一个配置文件后即可开始使用',
          duration: 1600
        });
      } catch (_toastErr) {
        // ignore
      }
      this.onRequireProfile();
      return;
    }
    if (this.store.isVpnTransitioning) {
      return;
    }
    const ok: boolean = await this.store.toggleRunningAsync();
    if (!ok) {
      this.showVpnFailureDialog();
    }
  }

  build() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(48)
          .height(48)
          .borderRadius(this.isVpnEnabledReactive() ? 16 : 24)
          .backgroundColor(this.isVpnEnabledReactive() ? this.palette.primary : this.palette.block)
          .rotate({ angle: this.isVpnEnabledReactive() ? 15 : 0 })
          .animation({ duration: 280, curve: Curve.EaseOut })
        SymbolGlyph($r('sys.symbol.shield_checkered'))
          .fontSize(22)
          .fontColor([this.isVpnEnabledReactive() ? this.palette.onPrimary : this.palette.onSurfaceVariant])
      }

      Column({ space: 2 }) {
        Text('VPN')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Text(this.getVpnSubtitle())
          .fontSize(12)
          .fontColor(this.palette.onSurfaceVariant)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.isVpnEnabledReactive() })
        .selectedColor(this.palette.primary)
        .opacity(this.hasProfilesReactive() ? (this.isTransitioningReactive() ? 0.65 : 1) : 0.55)
        .hitTestBehavior(HitTestMode.None)
    }
    .id('dashboard-vpn-card')
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(this.palette.card)
    .borderRadius(34)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.handleToggleVpn();
    })
  }
}

@Component
export struct IntranetIpCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;

  private store: AppStateStore = AppStateStore.getInstance();

  private copyIpAddress(): void {
    const text: string = this.store.allowLan
      ? `${this.store.intranetIp}:${this.store.mixedPort}`
      : this.store.intranetIp;
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data);
      this.getUIContext().getPromptAction().showToast({
        message: `${this.store.localeLang === 'en_US' ? 'Copied' : '已复制'}: ${text}`,
        duration: 1500
      });
    } catch (e) {
      // ignore sandbox clipboard errors
    }
  }

  private getIntranetIpText(): string {
    return this.revisionTick >= 0 ? this.store.intranetIp : '—';
  }

  private isAllowLanReactive(): boolean {
    return this.revisionTick >= 0 && this.store.allowLan;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.globe_badge_heart'))
          .fontSize(16)
          .fontColor([this.palette.onSurfaceVariant])
        Text(I18n.t('intranetIp', this.store.localeLang))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Blank()
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.plus_square_on_square'))
            .fontSize(15)
            .fontColor([this.palette.onSurfaceVariant])
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(this.palette.block)
        .onClick((): void => {
          this.copyIpAddress();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.getIntranetIpText())
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.onSurface)
        .margin({ top: 12, bottom: 14 })

      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(I18n.t('allowLan', this.store.localeLang))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurface)
          Text(this.isAllowLanReactive()
            ? `端口 ${this.store.mixedPort}`
            : I18n.t('disabled', this.store.localeLang))
            .fontSize(11)
            .fontColor(this.palette.onSurfaceVariant)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.isAllowLanReactive() })
          .selectedColor(this.palette.primary)
          .onChange((isOn: boolean): void => {
            this.store.allowLan = isOn;
            this.store.notify();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 10, bottom: 10 })
      .backgroundColor(this.palette.block)
      .borderRadius(20)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.palette.card)
    .borderRadius(34)
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct ProfileSummaryCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  onNavigateProfiles: () => void = (): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

  private getUsageRatio(p: ProfileSubscriptionModel): number {
    if (p.totalBytes <= 0) {
      return 0;
    }
    const used: number = p.usedUploadBytes + p.usedDownloadBytes;
    return Math.min(1.0, Math.max(0.0, used / p.totalBytes));
  }

  private getDaysLeftStr(p: ProfileSubscriptionModel): string {
    if (p.expireTimestamp <= 0) {
      return p.sourceType === 'url' ? '远程' : p.sourceType === 'custom' ? '自定义' : '本地';
    }
    const diffDays: number = Math.max(0, Math.round((p.expireTimestamp - Date.now() / 1000) / 86400));
    return `${diffDays} ${I18n.t('daysLeft', this.store.localeLang)}`;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(16)
          .fontColor([this.palette.onSurfaceVariant])
        Text(I18n.t('profile', this.store.localeLang))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Blank()

        if (this.revisionTick >= 0 && this.store.getCurrentProfile() !== null && this.store.getCurrentProfile()!.sourceType === 'url') {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(14)
              .fontColor([this.palette.onSurfaceVariant])
              .rotate({ angle: this.store.getCurrentProfile()!.isUpdating ? 360 : 0 })
              .animation({ duration: 500, curve: Curve.EaseInOut })
          }
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor(this.palette.block)
          .onClick((): void => {
            const p: ProfileSubscriptionModel | null = this.store.getCurrentProfile();
            if (p !== null) {
              this.store.syncProfileById(p.id);
            }
          })
        }

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([this.palette.onSurfaceVariant])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.revisionTick >= 0 && this.store.getCurrentProfile() === null) {
        // Matches FlClash ProfilesCard when profile == null: shows "添加配置" (Add Profile)
        Text(this.store.localeLang === 'en_US' ? 'Add Profile' : '添加配置')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
          .margin({ top: 12 })
      } else {
        Row({ space: 8 }) {
          Text(this.store.getCurrentProfile()!.label)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(this.getDaysLeftStr(this.store.getCurrentProfile()!))
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
        }
        .width('100%')
        .margin({ top: 12, bottom: 14 })
        .alignItems(VerticalAlign.Center)

        if (this.store.getCurrentProfile()!.totalBytes > 0) {
          Row({ space: 6 }) {
            Text(`${Math.round(this.getUsageRatio(this.store.getCurrentProfile()!) * 100)}%`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
            Text(I18n.t('used', this.store.localeLang))
              .fontSize(12)
              .fontColor(this.palette.onSurfaceVariant)
            Blank()
            Text(`${ThemeManager.formatBytes(this.store.getCurrentProfile()!.usedUploadBytes + this.store.getCurrentProfile()!.usedDownloadBytes)} / ${ThemeManager.formatBytes(this.store.getCurrentProfile()!.totalBytes)}`)
              .fontSize(12)
              .fontColor(this.palette.onSurfaceVariant)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .margin({ bottom: 8 })

          WavyProgressView({
            progressRatio: this.getUsageRatio(this.store.getCurrentProfile()!),
            activeColor: this.palette.primary,
            trackColor: this.palette.inset,
            revisionTick: this.revisionTick
          })
        } else {
          // Matches FlClash _ConfigStats (groups, proxies, rules) when profile has no quota header
          Row() {
            Column({ space: 2 }) {
              Text(`${this.store.getCurrentProfile()!.groupsCount}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
              Text(I18n.t('proxyGroup', this.store.localeLang))
                .fontSize(12)
                .fontColor(this.palette.onSurfaceVariant)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column({ space: 2 }) {
              Text(`${this.store.getCurrentProfile()!.proxiesCount}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
              Text(I18n.t('proxies', this.store.localeLang))
                .fontSize(12)
                .fontColor(this.palette.onSurfaceVariant)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column({ space: 2 }) {
              Text(`${this.store.getCurrentProfile()!.rulesCount}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
              Text(I18n.t('rule', this.store.localeLang))
                .fontSize(12)
                .fontColor(this.palette.onSurfaceVariant)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.palette.card)
    .borderRadius(34)
    .alignItems(HorizontalAlign.Start)
    .onClick((): void => {
      this.onNavigateProfiles();
    })
  }
}

@Component
export struct ServiceStatusCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  onOpenServicesSheet: () => void = (): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

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

  private getServiceStateText(srv: ServiceProbeItem): string {
    if (srv.status === 'checking') {
      return this.store.localeLang === 'en_US' ? 'Loading…' : '加载中…';
    }
    if (srv.delayMs > 0) {
      return `${srv.delayMs} ms`;
    }
    if (srv.delayMs < 0) {
      return this.store.localeLang === 'en_US' ? 'Failed' : '检测失败';
    }
    return this.store.localeLang === 'en_US' ? 'Pending' : '待检测';
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.checkmark_shield'))
          .fontSize(16)
          .fontColor([this.palette.onSurfaceVariant])
        Text(I18n.t('serviceStatus', this.store.localeLang))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([this.palette.onSurfaceVariant])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // Mobile ServiceStatusCard shows 2 services side-by-side (shownCount = 1 * 2 = 2)
      Row({ space: 8 }) {
        ForEach(
          this.store.serviceProbes.slice(0, 2),
          (srv: ServiceProbeItem) => {
            Row({ space: 8 }) {
              Stack({ alignContent: Alignment.Center }) {
                Image(this.getMediaIcon(srv.iconName))
                  .width(16)
                  .height(16)
                  .fillColor(this.palette.onSurface)
              }
              .width(28)
              .height(28)
              .borderRadius(9)
              .backgroundColor(this.palette.inset)

              Text(this.getServiceStateText(srv))
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(srv.delayMs > 0 ? this.palette.onSurface : this.palette.onSurfaceVariant)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .layoutWeight(1)
            .height(44)
            .padding({ left: 10, right: 12 })
            .backgroundColor(this.palette.block)
            .borderRadius(16)
            .alignItems(VerticalAlign.Center)
          },
          (srv: ServiceProbeItem): string => `${srv.id}_${srv.delayMs}_${srv.status}`
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.palette.card)
    .borderRadius(34)
    .onClick((): void => {
      this.onOpenServicesSheet();
    })
  }
}

@Component
export struct ProxyGroupsCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  onSelectGroupToSwitch: (groupId: string) => void = (_groupId: string): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(16)
          .fontColor([this.palette.onSurfaceVariant])
        Text(I18n.t('proxyGroup', this.store.localeLang))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)

        if (this.revisionTick >= 0 && this.store.proxyGroups.length > 0) {
          Text(`${this.store.proxyGroups.length}`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurfaceVariant)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor(this.palette.block)
            .borderRadius(8)
        }

        Blank()
        if (this.revisionTick >= 0 && this.store.proxyGroups.length > 0) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([this.palette.onSurfaceVariant])
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        if (this.store.proxyGroups.length > 0) {
          this.onSelectGroupToSwitch(this.store.proxyGroups[0].id);
        }
      })

      if (this.revisionTick >= 0 && this.store.proxyGroups.length === 0) {
        Column({ space: 6 }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.square_grid_2x2'))
              .fontSize(24)
              .fontColor([this.palette.onSurfaceVariant])
          }
          .width(56)
          .height(56)
          .borderRadius(20)
          .backgroundColor(this.palette.block)
          .margin({ bottom: 4 })

          Text(this.store.localeLang === 'en_US' ? 'No proxy groups' : '暂无策略组')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurface)

          Text(this.store.localeLang === 'en_US'
            ? 'Add a profile to select proxy nodes'
            : '添加配置后即可在此切换策略组与节点')
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 8 }) {
          ForEach(
            this.revisionTick >= 0 ? this.store.proxyGroups.slice(0, 4) : [],
            (grp: ProxyGroupItem) => {
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Text(grp.iconText)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurfaceVariant)
                }
                .width(34)
                .height(34)
                .borderRadius(12)
                .backgroundColor(this.palette.inset)

                Column({ space: 2 }) {
                  Text(grp.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)
                  Text(grp.selectedName)
                    .fontSize(12)
                    .fontColor(this.palette.primary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(13)
                  .fontColor([this.palette.onSurfaceVariant])
              }
              .width('100%')
              .height(52)
              .padding({ left: 10, right: 14 })
              .backgroundColor(this.palette.block)
              .borderRadius(18)
              .alignItems(VerticalAlign.Center)
              .onClick((): void => {
                this.onSelectGroupToSwitch(grp.id);
              })
            },
            (grp: ProxyGroupItem): string => `${grp.id}_${grp.selectedName}_${this.revisionTick}`
          )
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.palette.card)
    .borderRadius(34)
  }
}

@Component
export struct ConnectionStatsCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  onOpenFeed: (feed: DashboardFeedKind) => void = (_feed: DashboardFeedKind): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

  private getConnectionsCountText(): string {
    return `${this.revisionTick >= 0 ? this.store.liveConnections.length : 0}`;
  }

  private getRequestsCountText(): string {
    return `${this.revisionTick >= 0 ? this.store.recentRequestsCount : 0}`;
  }

  private getDnsCountText(): string {
    return `${this.revisionTick >= 0 ? this.store.dnsQueriesCount : 0}`;
  }

  build() {
    Row() {
      Column({ space: 3 }) {
        Text(this.getConnectionsCountText())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Text(I18n.t('liveConnections', this.store.localeLang))
          .fontSize(12)
          .fontColor(this.palette.onSurfaceVariant)
      }
      .layoutWeight(1)
      .padding({ top: 10, bottom: 10 })
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.onOpenFeed('connections');
      })

      Column({ space: 3 }) {
        Text(this.getRequestsCountText())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Text(I18n.t('recentRequests', this.store.localeLang))
          .fontSize(12)
          .fontColor(this.palette.onSurfaceVariant)
      }
      .layoutWeight(1)
      .padding({ top: 10, bottom: 10 })
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.onOpenFeed('requests');
      })

      Column({ space: 3 }) {
        Text(this.getDnsCountText())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Text(I18n.t('dnsQueries', this.store.localeLang))
          .fontSize(12)
          .fontColor(this.palette.onSurfaceVariant)
      }
      .layoutWeight(1)
      .padding({ top: 10, bottom: 10 })
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.onOpenFeed('dns');
      })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.palette.card)
    .borderRadius(34)
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct MemoryInfoCardView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;

  private store: AppStateStore = AppStateStore.getInstance();

  private getTotalMB(): string {
    const _t: number = this.revisionTick;
    const total: number = _t >= 0 ? (this.store.memorySnapshot.appBytes + this.store.memorySnapshot.coreRssBytes) / 1048576 : 0;
    return total.toFixed(1);
  }

  private getAppMB(): string {
    const _t: number = this.revisionTick;
    return (_t >= 0 ? this.store.memorySnapshot.appBytes / 1048576 : 0).toFixed(1);
  }

  private getCoreMB(): string {
    const _t: number = this.revisionTick;
    if (_t < 0 || !this.store.isRunning || this.store.memorySnapshot.coreRssBytes <= 0) {
      return this.store.localeLang === 'en_US' ? 'Not running' : '内核未运行';
    }
    return `${(this.store.memorySnapshot.coreRssBytes / 1048576).toFixed(1)} MB`;
  }

  private getAppWeight(): number {
    const _t: number = this.revisionTick;
    return _t >= 0 ? Math.max(1, Math.round(this.store.memorySnapshot.appBytes / 1048576)) : 1;
  }

  private getCoreWeight(): number {
    const _t: number = this.revisionTick;
    return _t >= 0 ? Math.max(0, Math.round(this.store.memorySnapshot.coreRssBytes / 1048576)) : 0;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.memory_module'))
          .fontSize(16)
          .fontColor([this.palette.onSurfaceVariant])
        Text(I18n.t('memoryInfo', this.store.localeLang))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Blank()

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.paintbrush'))
            .fontSize(14)
            .fontColor([this.palette.onSurfaceVariant])
        }
        .width(26)
        .height(26)
        .borderRadius(13)
        .backgroundColor(this.palette.block)
        .onClick((): void => {
          const freedBytes: number = this.store.releaseMemoryGC();
          try {
            this.getUIContext().getPromptAction().showToast({
              message: this.store.lastOperationError.length > 0 ? this.store.lastOperationError
                : `${this.store.localeLang === 'en_US' ? 'Memory released' : '已释放'}: ${(freedBytes / 1048576).toFixed(1)} MB`,
              duration: 1600
            });
          } catch (e) {
            // ignore
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 4 }) {
        Text(this.getTotalMB())
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onSurface)
        Text('MB')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.onSurfaceVariant)
          .margin({ bottom: 3 })
      }
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 12, bottom: 14 })

      Row({ space: 3 }) {
        Row()
          .layoutWeight(this.getAppWeight())
          .height(8)
          .backgroundColor(this.palette.primary)
          .borderRadius({ topLeft: 4, bottomLeft: 4, topRight: 2, bottomRight: 2 })
        if (this.getCoreWeight() > 0) {
          Row()
            .layoutWeight(this.getCoreWeight())
            .height(8)
            .backgroundColor(this.palette.series2)
            .borderRadius(2)
        }
        Row()
          .layoutWeight(60)
          .height(8)
          .backgroundColor(this.palette.inset)
          .borderRadius({ topLeft: 2, bottomLeft: 2, topRight: 4, bottomRight: 4 })
      }
      .width('100%')
      .margin({ bottom: 10 })

      Row({ space: 16 }) {
        Row({ space: 6 }) {
          Circle({ width: 7, height: 7 })
            .fill(this.palette.primary)
          Text(I18n.t('app', this.store.localeLang))
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
          Text(`${this.getAppMB()} MB`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurface)
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 6 }) {
          Circle({ width: 7, height: 7 })
            .fill(this.palette.series2)
          Text(I18n.t('core', this.store.localeLang))
            .fontSize(12)
            .fontColor(this.palette.onSurfaceVariant)
          Text(this.getCoreMB())
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurface)
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.palette.card)
    .borderRadius(34)
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct DashboardEditorView {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop revisionTick: number = 0;
  onFinishEdit: () => void = (): void => {};

  private store: AppStateStore = AppStateStore.getInstance();

  build() {
    Column({ space: 12 }) {
      ForEach(
        this.store.dashboardWidgets,
        (wItem: DashboardWidgetConfigItem, index: number) => {
          Row({ space: 12 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: wItem.enabled })
              .selectedColor(this.palette.primary)
              .enabled(wItem.removable)
              .onChange((_val: boolean): void => {
                this.store.toggleDashboardWidget(wItem.id);
              })

            Column({ space: 3 }) {
              Text(I18n.t(wItem.titleKey, this.store.localeLang))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onSurface)
              Text(wItem.descKey)
                .fontSize(12)
                .fontColor(this.palette.onSurfaceVariant)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Row({ space: 6 }) {
              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph($r('sys.symbol.arrow_up'))
                  .fontSize(14)
                  .fontColor([index > 0 ? this.palette.onSurface : this.palette.onSurfaceVariant])
              }
              .width(32)
              .height(32)
              .borderRadius(10)
              .backgroundColor(this.palette.block)
              .onClick((): void => {
                this.store.moveDashboardWidget(index, -1);
              })

              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph($r('sys.symbol.arrow_down'))
                  .fontSize(14)
                  .fontColor([index < this.store.dashboardWidgets.length - 1 ? this.palette.onSurface : this.palette.onSurfaceVariant])
              }
              .width(32)
              .height(32)
              .borderRadius(10)
              .backgroundColor(this.palette.block)
              .onClick((): void => {
                this.store.moveDashboardWidget(index, 1);
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor(this.palette.card)
          .borderRadius(22)
          .alignItems(VerticalAlign.Center)
        },
        (wItem: DashboardWidgetConfigItem, index: number): string => `${wItem.id}_${wItem.enabled}_${index}`
      )
    }
    .width('100%')
  }
}

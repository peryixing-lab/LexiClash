// NodeImportPanel.ets — Shared URI batch & manual single-node importer (aligned with clash-verge-rev ProxiesEditorViewer)

import { pasteboard } from '@kit.BasicServicesKit';
import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';
import {
  ClashProxyEntry,
  ClashUriBatchResult,
  ClashUriParser,
  ManualProxyNodeForm
} from '../core/ClashUriParser';

@Component
export struct NodeImportPanel {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop singleButtonMode: boolean = false;
  @Prop primaryActionLabel: string = '导入并创建配置';
  onImportEntries: (entries: ClashProxyEntry[], insertPosition: 'prepend' | 'append') => void =
    (_entries: ClashProxyEntry[], _insertPosition: 'prepend' | 'append'): void => {};

  @State inputMode: 'uri' | 'manual' = 'uri';
  @State uriBatchText: string = '';
  @State manualProto: string = 'socks5';
  @State manualName: string = '';
  @State manualServer: string = '';
  @State manualPort: string = '1080';
  @State manualUsername: string = '';
  @State manualPassword: string = '';
  @State manualUuid: string = '';
  @State manualCipher: string = 'aes-256-gcm';
  @State manualSni: string = '';
  @State manualNetwork: string = 'tcp';
  @State manualWsHost: string = '';
  @State manualWsPath: string = '';
  @State manualFlow: string = '';
  @State manualPublicKey: string = '';
  @State manualShortId: string = '';
  @State manualTls: boolean = false;
  @State manualSkipCertVerify: boolean = false;
  @State manualUdp: boolean = true;
  @State feedbackText: string = '';
  @State feedbackIsError: boolean = false;

  private readonly protocols: string[] = [
    'socks5', 'http', 'ss', 'trojan', 'vmess', 'vless', 'hysteria2', 'tuic', 'anytls'
  ];

  private selectProtocol(proto: string): void {
    this.manualProto = proto;
    this.feedbackText = '';
    if (proto === 'socks5') {
      this.manualPort = '1080';
      this.manualTls = false;
    } else if (proto === 'http') {
      this.manualPort = '8080';
      this.manualTls = false;
    } else {
      this.manualPort = '443';
      this.manualTls = proto === 'vless' || proto === 'trojan' || proto === 'hysteria2' || proto === 'tuic' || proto === 'anytls';
    }
  }

  private async pasteFromClipboard(): Promise<void> {
    try {
      const data: pasteboard.PasteData = await pasteboard.getSystemPasteboard().getData();
      const text: string = data.getPrimaryText();
      if (text.length > 0) {
        this.uriBatchText = text;
        this.feedbackText = '';
      } else {
        this.feedbackIsError = true;
        this.feedbackText = '剪贴板中没有文本内容';
      }
    } catch (_err) {
      this.feedbackIsError = true;
      this.feedbackText = '读取剪贴板失败，请直接粘贴输入';
    }
  }

  private handleImport(insertPosition: 'prepend' | 'append'): void {
    this.feedbackText = '';
    this.feedbackIsError = false;
    if (this.inputMode === 'uri') {
      const trimmed: string = this.uriBatchText.trim();
      if (trimmed.length === 0) {
        this.feedbackIsError = true;
        this.feedbackText = '请粘贴至少一条节点分享链接（支持 socks5://、http://、ss://、vmess://、vless://、trojan://、hy2://、tuic://、anytls:// 或 Base64）';
        return;
      }
      const batch: ClashUriBatchResult = ClashUriParser.parseBatchUris(trimmed);
      if (batch.entries.length === 0) {
        this.feedbackIsError = true;
        this.feedbackText = batch.errors.length > 0 ? batch.errors[0] : '未解析出有效节点，请检查链接格式';
        return;
      }
      this.onImportEntries(batch.entries, insertPosition);
      this.uriBatchText = '';
      if (batch.errors.length > 0) {
        this.feedbackIsError = false;
        this.feedbackText = `已解析 ${batch.entries.length} 个节点（跳过 ${batch.errors.length} 行无效链接）`;
      }
      return;
    }

    const parsedPort: number = Number.parseInt(this.manualPort.trim(), 10);
    if (!Number.isSafeInteger(parsedPort) || parsedPort < 1 || parsedPort > 65535) {
      this.feedbackIsError = true;
      this.feedbackText = '请输入 1 ~ 65535 之间的有效端口号';
      return;
    }
    const form: ManualProxyNodeForm = {
      protocol: this.manualProto,
      name: this.manualName,
      server: this.manualServer,
      port: parsedPort,
      username: this.manualUsername,
      password: this.manualPassword,
      uuid: this.manualUuid,
      cipher: this.manualCipher,
      sni: this.manualSni,
      tls: this.manualTls,
      skipCertVerify: this.manualSkipCertVerify,
      udp: this.manualUdp,
      network: this.manualNetwork,
      wsHost: this.manualWsHost,
      wsPath: this.manualWsPath,
      flow: this.manualFlow,
      clientFingerprint: '',
      publicKey: this.manualPublicKey,
      shortId: this.manualShortId,
      obfs: '',
      obfsPassword: '',
      privateKey: '',
      peerPublicKey: '',
      localIp: ''
    };
    try {
      const built: ClashProxyEntry = ClashUriParser.buildEntryFromManualForm(form);
      this.onImportEntries([built], insertPosition);
      this.manualName = '';
      this.manualServer = '';
      this.manualUsername = '';
      this.manualPassword = '';
      this.manualUuid = '';
    } catch (err) {
      this.feedbackIsError = true;
      this.feedbackText = (err as Error).message;
    }
  }

  private usesUsernameField(): boolean {
    return this.manualProto === 'socks5' || this.manualProto === 'http';
  }

  private usesUuidField(): boolean {
    return this.manualProto === 'vmess' || this.manualProto === 'vless' || this.manualProto === 'tuic';
  }

  private usesPasswordField(): boolean {
    return this.manualProto === 'socks5' || this.manualProto === 'http' || this.manualProto === 'ss' ||
      this.manualProto === 'trojan' || this.manualProto === 'hysteria2' || this.manualProto === 'tuic' ||
      this.manualProto === 'anytls';
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('URI 链接 / Base64 导入')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.inputMode === 'uri' ? this.palette.onPrimary : this.palette.onSurface)
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor(this.inputMode === 'uri' ? this.palette.primary : this.palette.block)
          .borderRadius(12)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            this.inputMode = 'uri';
            this.feedbackText = '';
          })

        Text('手动填写 (SOCKS5 等)')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.inputMode === 'manual' ? this.palette.onPrimary : this.palette.onSurface)
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor(this.inputMode === 'manual' ? this.palette.primary : this.palette.block)
          .borderRadius(12)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            this.inputMode = 'manual';
            this.feedbackText = '';
          })
      }
      .width('100%')

      if (this.inputMode === 'uri') {
        Row({ space: 8 }) {
          Text('支持多条 URI 换行分隔或 Base64 订阅内容')
            .fontSize(11)
            .fontColor(this.palette.onSurfaceVariant)
            .layoutWeight(1)

          PasteButton({
            icon: PasteIconStyle.LINES,
            text: PasteDescription.PASTE,
            buttonType: ButtonType.Capsule
          })
            .fontSize(11)
            .fontColor(this.palette.onPrimary)
            .iconColor(this.palette.onPrimary)
            .backgroundColor(this.palette.primary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .onClick((_event: ClickEvent, result: PasteButtonOnClickResult): void => {
              if (result === PasteButtonOnClickResult.SUCCESS) {
                this.pasteFromClipboard();
              } else {
                this.feedbackIsError = true;
                this.feedbackText = '剪贴板临时授权未通过，请直接长按输入框粘贴';
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        TextArea({
          placeholder: '多条 URI 请使用换行分隔（支持 Base64 编码）\n示例: socks5://user:pass@1.2.3.4:1080#落地节点',
          text: this.uriBatchText
        })
          .height(104)
          .width('100%')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(this.palette.onSurface)
          .placeholderColor(this.palette.onSurfaceVariant)
          .backgroundColor(this.palette.block)
          .borderRadius(14)
          .onChange((val: string): void => {
            this.uriBatchText = val;
          })
      } else {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(
              this.protocols,
              (proto: string) => {
                Text(proto.toUpperCase())
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.manualProto === proto ? this.palette.onPrimary : this.palette.onSurface)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(this.manualProto === proto ? this.palette.primary : this.palette.block)
                  .borderRadius(10)
                  .onClick((): void => {
                    this.selectProtocol(proto);
                  })
              },
              (proto: string): string => `${proto}_${this.manualProto === proto}`
            )
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        Row({ space: 8 }) {
          TextInput({ placeholder: '节点名称 (可选)', text: this.manualName })
            .layoutWeight(1)
            .height(38)
            .fontSize(12)
            .fontColor(this.palette.onSurface)
            .placeholderColor(this.palette.onSurfaceVariant)
            .backgroundColor(this.palette.block)
            .borderRadius(12)
            .onChange((v: string): void => { this.manualName = v; })

          TextInput({ placeholder: '端口', text: this.manualPort })
            .width(86)
            .height(38)
            .fontSize(12)
            .type(InputType.Number)
            .fontColor(this.palette.onSurface)
            .placeholderColor(this.palette.onSurfaceVariant)
            .backgroundColor(this.palette.block)
            .borderRadius(12)
            .onChange((v: string): void => { this.manualPort = v; })
        }
        .width('100%')

        TextInput({ placeholder: '服务器域名或 IP (必填)', text: this.manualServer })
          .width('100%')
          .height(38)
          .fontSize(12)
          .fontColor(this.palette.onSurface)
          .placeholderColor(this.palette.onSurfaceVariant)
          .backgroundColor(this.palette.block)
          .borderRadius(12)
          .onChange((v: string): void => { this.manualServer = v; })

        if (this.usesUsernameField() || this.usesUuidField() || this.manualProto === 'ss') {
          Row({ space: 8 }) {
            if (this.usesUsernameField()) {
              TextInput({ placeholder: '用户名 (可选)', text: this.manualUsername })
                .layoutWeight(1)
                .height(38)
                .fontSize(12)
                .fontColor(this.palette.onSurface)
                .placeholderColor(this.palette.onSurfaceVariant)
                .backgroundColor(this.palette.block)
                .borderRadius(12)
                .onChange((v: string): void => { this.manualUsername = v; })
            } else if (this.usesUuidField()) {
              TextInput({ placeholder: 'UUID (必填)', text: this.manualUuid })
                .layoutWeight(1)
                .height(38)
                .fontSize(12)
                .fontColor(this.palette.onSurface)
                .placeholderColor(this.palette.onSurfaceVariant)
                .backgroundColor(this.palette.block)
                .borderRadius(12)
                .onChange((v: string): void => { this.manualUuid = v; })
            } else if (this.manualProto === 'ss') {
              TextInput({ placeholder: '加密方式 (aes-256-gcm)', text: this.manualCipher })
                .layoutWeight(1)
                .height(38)
                .fontSize(12)
                .fontColor(this.palette.onSurface)
                .placeholderColor(this.palette.onSurfaceVariant)
                .backgroundColor(this.palette.block)
                .borderRadius(12)
                .onChange((v: string): void => { this.manualCipher = v; })
            }

            if (this.usesPasswordField()) {
              TextInput({ placeholder: '密码', text: this.manualPassword })
                .layoutWeight(1)
                .height(38)
                .fontSize(12)
                .fontColor(this.palette.onSurface)
                .placeholderColor(this.palette.onSurfaceVariant)
                .backgroundColor(this.palette.block)
                .borderRadius(12)
                .onChange((v: string): void => { this.manualPassword = v; })
            }
          }
          .width('100%')
        } else if (this.usesPasswordField()) {
          TextInput({ placeholder: '密码', text: this.manualPassword })
            .width('100%')
            .height(38)
            .fontSize(12)
            .fontColor(this.palette.onSurface)
            .placeholderColor(this.palette.onSurfaceVariant)
            .backgroundColor(this.palette.block)
            .borderRadius(12)
            .onChange((v: string): void => { this.manualPassword = v; })
        }

        if (this.manualProto === 'vless') {
          Row({ space: 8 }) {
            TextInput({ placeholder: 'Reality Public Key (可选)', text: this.manualPublicKey })
              .layoutWeight(2)
              .height(38)
              .fontSize(12)
              .fontColor(this.palette.onSurface)
              .placeholderColor(this.palette.onSurfaceVariant)
              .backgroundColor(this.palette.block)
              .borderRadius(12)
              .onChange((v: string): void => { this.manualPublicKey = v; })

            TextInput({ placeholder: 'ShortId', text: this.manualShortId })
              .layoutWeight(1)
              .height(38)
              .fontSize(12)
              .fontColor(this.palette.onSurface)
              .placeholderColor(this.palette.onSurfaceVariant)
              .backgroundColor(this.palette.block)
              .borderRadius(12)
              .onChange((v: string): void => { this.manualShortId = v; })
          }
          .width('100%')
        }

        if (this.manualProto === 'trojan' || this.manualProto === 'vmess' || this.manualProto === 'vless' ||
          this.manualProto === 'hysteria2' || this.manualProto === 'tuic' || this.manualProto === 'anytls') {
          TextInput({ placeholder: 'SNI / Servername (可选)', text: this.manualSni })
            .width('100%')
            .height(38)
            .fontSize(12)
            .fontColor(this.palette.onSurface)
            .placeholderColor(this.palette.onSurfaceVariant)
            .backgroundColor(this.palette.block)
            .borderRadius(12)
            .onChange((v: string): void => { this.manualSni = v; })
        }

        Row({ space: 10 }) {
          Row({ space: 4 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.manualTls })
              .selectedColor(this.palette.primary)
              .onChange((val: boolean): void => { this.manualTls = val; })
            Text('TLS')
              .fontSize(11)
              .fontColor(this.palette.onSurface)
          }

          Row({ space: 4 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.manualSkipCertVerify })
              .selectedColor(this.palette.primary)
              .onChange((val: boolean): void => { this.manualSkipCertVerify = val; })
            Text('跳过证书验证')
              .fontSize(11)
              .fontColor(this.palette.onSurface)
          }

          Row({ space: 4 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.manualUdp })
              .selectedColor(this.palette.primary)
              .onChange((val: boolean): void => { this.manualUdp = val; })
            Text('UDP')
              .fontSize(11)
              .fontColor(this.palette.onSurface)
          }
        }
        .width('100%')
      }

      if (this.feedbackText.length > 0) {
        Text(this.feedbackText)
          .fontSize(11)
          .fontColor(this.feedbackIsError ? this.palette.error : this.palette.primary)
          .width('100%')
      }

      if (this.singleButtonMode) {
        Button(this.primaryActionLabel)
          .width('100%')
          .height(40)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.onPrimary)
          .backgroundColor(this.palette.primary)
          .borderRadius(14)
          .onClick((): void => {
            this.handleImport('append');
          })
      } else {
        Row({ space: 8 }) {
          Button('添加前置代理节点')
            .layoutWeight(1)
            .height(38)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onPrimary)
            .backgroundColor(this.palette.primary)
            .borderRadius(12)
            .onClick((): void => {
              this.handleImport('prepend');
            })

          Button('添加后置代理节点')
            .layoutWeight(1)
            .height(38)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onPrimary)
            .backgroundColor(this.palette.primary)
            .borderRadius(12)
            .onClick((): void => {
              this.handleImport('append');
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

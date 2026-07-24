import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../../tdkit/Globals';
import { AuthStage } from '../../tdkit/AuthService';
import { TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LoginHero } from './LoginHero';

@Preview
@Component
export struct CodePage {
  @State code: string = '';
  @State errorText: string = '';
  @State resendText: string = '';
  @State busy: boolean = false;
  @State codeLength: number = 5;
  @State phoneNumber: string = '';
  @State codeType: string = '';
  @State codeDestination: string = '';
  @State nextCodeType: string = '';
  @State codeSlots: number[] = [0, 1, 2, 3, 4];
  private lastSubmittedCode: string = '';
  private unsubscribeStage: (() => void) | null = null;

  aboutToAppear(): void {
    const auth = getAuthService();
    this.unsubscribeStage = auth.onStageChange((stage: AuthStage): void => {
      if (stage === AuthStage.WaitCode) { this.refreshCodeInfo(); }
    });
    this.refreshCodeInfo();
    setTimeout((): void => {
      focusControl.requestFocus('telegram_login_code');
    }, 220);
  }

  aboutToDisappear(): void {
    if (this.unsubscribeStage !== null) {
      this.unsubscribeStage();
      this.unsubscribeStage = null;
    }
  }

  private refreshCodeInfo(): void {
    const auth = getAuthService();
    this.codeLength = auth.getCodeLength();
    this.phoneNumber = auth.getPhoneNumber();
    this.codeType = auth.getCodeType();
    this.codeDestination = auth.getCodeDestination();
    this.nextCodeType = auth.getNextCodeType();
    const slots: number[] = [];
    for (let index = 0; index < this.codeLength; ++index) {
      slots.push(index);
    }
    this.codeSlots = slots;
  }

  private phoneTarget(): string {
    return this.phoneNumber !== '' ? this.phoneNumber : '你的手机号';
  }

  private deliveryDescription(): string {
    switch (this.codeType) {
      case 'authenticationCodeTypeTelegramMessage':
        return '验证码已发送到你另一台设备上的 Telegram';
      case 'authenticationCodeTypeSms':
      case 'authenticationCodeTypeSmsWord':
      case 'authenticationCodeTypeSmsPhrase':
      case 'authenticationCodeTypeFirebaseAndroid':
        return `验证码已通过短信发送至 ${this.phoneTarget()}`;
      case 'authenticationCodeTypeCall':
        return `Telegram 将致电 ${this.phoneTarget()} 并告知验证码`;
      case 'authenticationCodeTypeFlashCall':
        return `请留意发送到 ${this.phoneTarget()} 的验证来电`;
      case 'authenticationCodeTypeMissedCall':
        return `请留意发送到 ${this.phoneTarget()} 的未接来电`;
      case 'authenticationCodeTypeEmailAddress':
        return this.codeDestination !== ''
          ? `验证码已发送至邮箱 ${this.codeDestination}`
          : '验证码已发送至你的登录邮箱';
      case 'authenticationCodeTypeFragment':
        return '验证码已发送到 Fragment';
      default:
        return this.phoneNumber !== ''
          ? `验证码已发送至 ${this.phoneNumber}`
          : '验证码已通过 Telegram 或短信发送给你';
    }
  }

  private resendButtonText(): string {
    switch (this.nextCodeType) {
      case 'authenticationCodeTypeTelegramMessage':
        return '改用 Telegram 接收验证码';
      case 'authenticationCodeTypeSms':
      case 'authenticationCodeTypeSmsWord':
      case 'authenticationCodeTypeSmsPhrase':
        return '改用短信接收验证码';
      case 'authenticationCodeTypeCall':
      case 'authenticationCodeTypeFlashCall':
      case 'authenticationCodeTypeMissedCall':
        return '改用电话接收验证码';
      default:
        return '没有收到验证码？重新发送';
    }
  }

  private onCodeChange(value: string): void {
    const digits = value.replace(/[^0-9]/g, '');
    const next = digits.substring(0, Math.min(this.codeLength, digits.length));
    this.code = next;
    this.errorText = '';
    this.resendText = '';
    if (next.length === this.codeLength && next !== this.lastSubmittedCode && !this.busy) {
      setTimeout((): void => this.submitCode(), 120);
    }
  }

  private submitCode(): void {
    if (this.busy || this.code.length !== this.codeLength) { return; }
    this.busy = true;
    this.errorText = '';
    this.lastSubmittedCode = this.code;
    getAuthService().submitCode(this.code).catch((caught: TdError): void => {
      this.errorText = caught.message;
      this.code = '';
      this.lastSubmittedCode = '';
      setTimeout((): void => {
        focusControl.requestFocus('telegram_login_code');
      }, 80);
    }).finally((): void => {
      this.busy = false;
    });
  }

  private resendCode(): void {
    if (this.busy) { return; }
    this.busy = true;
    this.errorText = '';
    this.resendText = '';
    getAuthService().resendCode().then((): void => {
      this.resendText = '新的验证码已发送';
      this.code = '';
      this.lastSubmittedCode = '';
      setTimeout((): void => {
        focusControl.requestFocus('telegram_login_code');
      }, 80);
    }).catch((caught: TdError): void => {
      this.errorText = caught.message;
    }).finally((): void => {
      this.busy = false;
    });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        LoginHero({ mode: 'code' });

        Text('输入验证码')
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.deliveryDescription())
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).lineHeight(21);

        Stack({ alignContent: Alignment.Center }) {
          Row({ space: 8 }) {
            ForEach(this.codeSlots, (index: number) => {
              Column({ space: 4 }) {
                Text(index < this.code.length ? this.code.substring(index, index + 1) : '_')
                  .fontSize(27)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(index < this.code.length
                    ? COLOR_TEXT_PRIMARY
                    : (index === this.code.length ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY))
                  .textAlign(TextAlign.Center);
                Divider()
                  .strokeWidth(index === this.code.length ? 2.5 : 1.5)
                  .color(index === this.code.length ? COLOR_PRIMARY : '#4D8E8E93');
              }
              .layoutWeight(1)
              .constraintSize({ maxWidth: 48 })
              .height(58)
              .justifyContent(FlexAlign.Center);
            }, (index: number): string => `${index}`);
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 4, right: 4 });

          TextInput({ text: this.code })
            .key('telegram_login_code')
            .type(InputType.Number)
            .maxLength(this.codeLength)
            .fontColor(Color.Transparent)
            .caretColor(Color.Transparent)
            .selectedBackgroundColor(Color.Transparent)
            .backgroundColor(Color.Transparent)
            .width('100%').height(64)
            .opacity(0.02)
            .onChange((value: string): void => this.onCodeChange(value))
            .onSubmit((): void => this.submitCode());
        }
        .width('100%')
        .margin({ top: 10, bottom: 6 })
        .onClick((): void => {
          focusControl.requestFocus('telegram_login_code');
        });

        if (this.busy) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
            Text('正在验证…').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
        }
        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%').fontSize(13).fontColor('#FF3B30')
            .textAlign(TextAlign.Center);
        }
        if (this.resendText !== '') {
          Text(this.resendText)
            .width('100%').fontSize(13).fontColor('#34C759')
            .textAlign(TextAlign.Center);
        }

        Button('验证并登录')
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(COLOR_PRIMARY).borderRadius(14)
          .enabled(!this.busy && this.code.length === this.codeLength)
          .onClick((): void => this.submitCode());

        Button(this.resendButtonText())
          .width('100%').height(45)
          .fontSize(14).fontColor(COLOR_PRIMARY)
          .backgroundColor(Color.Transparent)
          .enabled(!this.busy)
          .onClick((): void => this.resendCode());

        if (canReturnToPreviousTdAccount()) {
          Button('返回原账号')
            .width('100%').height(45)
            .fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .enabled(!this.busy)
            .onClick((): void => {
              this.busy = true;
              returnToPreviousTdAccount().catch((caught: Error): void => {
                this.errorText = caught.message;
                this.busy = false;
              });
            });
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 430 })
      .padding({ left: 24, right: 24, top: 28, bottom: 28 });
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_bg'));
  }
}

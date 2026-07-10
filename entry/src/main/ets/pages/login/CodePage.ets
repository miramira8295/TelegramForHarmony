import { getAuthService } from '../../tdkit/Globals';
import { TdError } from '../../tdkit/TdTypes';

@Preview
@Component
export struct CodePage {
  @State code: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;

  build() {
    Column({ space: 16 }) {
      Text('Enter Code').fontSize(28).fontWeight(FontWeight.Bold);
      Text('We have sent you a message with the code.')
        .fontSize(14).fontColor('#8E8E93').textAlign(TextAlign.Center);
      TextInput({ text: this.code })
        .type(InputType.Number)
        .maxLength(6)
        .onChange((v: string) => { this.code = v; });
      if (this.errorText !== '') {
        Text(this.errorText).fontSize(13).fontColor('#FF3B30');
      }
      Button(this.busy ? 'Verifying…' : 'Next')
        .width('80%')
        .enabled(!this.busy)
        .onClick(async () => {
          this.busy = true;
          this.errorText = '';
          try {
            await getAuthService().submitCode(this.code);
          } catch (e) {
            this.errorText = (e as TdError).message;
          }
          this.busy = false;
        });
      Button('Resend code')
        .width('80%')
        .backgroundColor('#8E8E93')
        .onClick(async () => {
          this.errorText = '';
          try {
            await getAuthService().resendCode();
            this.errorText = 'Resend requested';
          } catch (e) {
            this.errorText = `Resend failed: ${(e as TdError).message}`;
          }
        });
    }
    .padding(24)
    .width('100%');
  }
}

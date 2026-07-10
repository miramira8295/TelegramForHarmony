import { getAuthService } from '../../tdkit/Globals';
import { TdError } from '../../tdkit/TdTypes';

@Preview
@Component
export struct PhoneNumberPage {
  @State phone: string = '+86';
  @State errorText: string = '';
  @State busy: boolean = false;

  build() {
    Column({ space: 16 }) {
      Text('Your Phone').fontSize(28).fontWeight(FontWeight.Bold);
      Text('Please confirm your country code\nand enter your phone number.')
        .fontSize(14).fontColor('#8E8E93').textAlign(TextAlign.Center);
      TextInput({ text: this.phone })
        .type(InputType.PhoneNumber)
        .onChange((v: string) => { this.phone = v; });
      if (this.errorText !== '') {
        Text(this.errorText).fontSize(13).fontColor('#FF3B30');
      }
      Button(this.busy ? 'Sending…' : 'Next')
        .width('80%')
        .enabled(!this.busy)
        .onClick(async () => {
          this.busy = true;
          this.errorText = '';
          try {
            await getAuthService().submitPhone(this.phone);
          } catch (e) {
            this.errorText = (e as TdError).message;
          }
          this.busy = false;
        });
    }
    .padding(24)
    .width('100%');
  }
}

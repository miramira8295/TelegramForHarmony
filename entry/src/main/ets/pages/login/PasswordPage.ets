import { getAuthService } from '../../tdkit/Globals';
import { TdError } from '../../tdkit/TdTypes';

@Preview
@Component
export struct PasswordPage {
  @State pw: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;

  build() {
    Column({ space: 16 }) {
      Text('Two-Step Verification').fontSize(28).fontWeight(FontWeight.Bold);
      Text('Enter the password you set up.')
        .fontSize(14).fontColor('#8E8E93').textAlign(TextAlign.Center);
      TextInput({ text: this.pw })
        .type(InputType.Password)
        .onChange((v: string) => { this.pw = v; });
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
            await getAuthService().submitPassword(this.pw);
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

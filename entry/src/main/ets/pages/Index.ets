import { AuthStage } from '../tdkit/AuthService';
import { getAuthService } from '../tdkit/Globals';
import { PhoneNumberPage } from './login/PhoneNumberPage';
import { CodePage } from './login/CodePage';
import { PasswordPage } from './login/PasswordPage';
import { MainScreen } from './main/MainScreen';

@Entry
@Preview
@Component
struct Index {
  @State stage: AuthStage = AuthStage.Init;
  @StorageProp('topSafeHeight') topSafe: number = 0;

  aboutToAppear(): void {
    getAuthService().onStageChange((s: AuthStage) => {
      this.stage = s;
    });
  }

  build() {
    Column() {
      if (this.stage === AuthStage.WaitPhone) {
        PhoneNumberPage()
      } else if (this.stage === AuthStage.WaitCode) {
        CodePage()
      } else if (this.stage === AuthStage.WaitPassword) {
        PasswordPage()
      } else if (this.stage === AuthStage.Ready) {
        MainScreen()
      } else if (this.stage === AuthStage.LoggedOut) {
        PhoneNumberPage()
      } else {
        LoadingProgress().width(48).height(48)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // ChatListPage does its own full-screen top inset; pad only the login stages.
    .padding({ top: this.stage === AuthStage.Ready ? 0 : this.topSafe })
  }
}

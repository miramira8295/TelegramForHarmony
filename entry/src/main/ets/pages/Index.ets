import { common } from '@kit.AbilityKit';
import { AuthStage } from '../tdkit/AuthService';
import { getAuthService } from '../tdkit/Globals';
import { PhoneNumberPage } from './login/PhoneNumberPage';
import { CodePage } from './login/CodePage';
import { PasswordPage } from './login/PasswordPage';
import { MainScreen } from './main/MainScreen';
import { handleIncomingLink } from '../util/deepLink';

@Entry
@Preview
@Component
struct Index {
  @State stage: AuthStage = AuthStage.Init;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // Set by EntryAbility when the app is opened via a tg:// deep link. Held here
  // until auth is Ready (routing needs a logged-in session + a live router).
  @StorageLink('pendingDeepLink') @Watch('onDeepLink') pendingDeepLink: string = '';

  aboutToAppear(): void {
    getAuthService().onStageChange((s: AuthStage) => {
      this.stage = s;
      // A link that arrived (or waited) through cold start / login flow.
      this.consumeDeepLink();
    });
  }

  // Fires when a deep link arrives while the app is already running.
  private onDeepLink(): void {
    this.consumeDeepLink();
  }

  // Route the pending link only once signed in; otherwise leave it queued for
  // the next stage change. Clear before routing so it's handled exactly once.
  private consumeDeepLink(): void {
    if (this.stage !== AuthStage.Ready || this.pendingDeepLink === '') {
      return;
    }
    const uri = this.pendingDeepLink;
    this.pendingDeepLink = '';
    handleIncomingLink(getContext(this) as common.UIAbilityContext, uri);
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

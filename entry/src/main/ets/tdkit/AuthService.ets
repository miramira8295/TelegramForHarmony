import { TdClient } from './TdClient';
import { TdObject, TdRequest } from './TdTypes';
import { clientRev, clientSig } from './ApiCredentials';
import { hilog } from '@kit.PerformanceAnalysisKit';

export enum AuthStage {
  Init = 'Init',
  WaitPhone = 'WaitPhone',
  WaitCode = 'WaitCode',
  WaitPassword = 'WaitPassword',
  Ready = 'Ready',
  LoggedOut = 'LoggedOut'
}

// Set true to connect to Telegram's test datacenter, which validates the login
// flow end-to-end without SMS or production flood limits. Test phone numbers are
// 99966<dc><4 digits> (e.g. 9996627777 for DC 2); the login code is the dc id
// repeated to the code length (DC 2 -> "22222"). Keep false for real accounts.
const USE_TEST_DC: boolean = false;

const STATE_TO_STAGE: Map<string, AuthStage> = new Map([
  ['authorizationStateWaitPhoneNumber', AuthStage.WaitPhone],
  ['authorizationStateWaitCode', AuthStage.WaitCode],
  ['authorizationStateWaitPassword', AuthStage.WaitPassword],
  ['authorizationStateReady', AuthStage.Ready],
  ['authorizationStateClosed', AuthStage.LoggedOut],
  ['authorizationStateLoggingOut', AuthStage.LoggedOut],
]);

export class AuthService {
  private client: TdClient;
  private filesDir: string;
  private callbacks: Array<(stage: AuthStage) => void> = [];
  private currentStage: AuthStage = AuthStage.Init;

  constructor(client: TdClient, filesDir: string) {
    this.client = client;
    this.filesDir = filesDir;
    client.onUpdate('updateAuthorizationState', (u: TdObject) => this.onAuthState(u));
  }

  // Registers a listener and immediately replays the current stage, so a
  // subscriber that mounts after the auth state has already arrived is not
  // left waiting for the next transition.
  onStageChange(cb: (stage: AuthStage) => void): void {
    this.callbacks = [...this.callbacks, cb];
    cb(this.currentStage);
  }

  async submitPhone(phone: string): Promise<void> {
    const request: TdRequest = { '@type': 'setAuthenticationPhoneNumber' };
    request['phone_number'] = phone;
    await this.client.send(request);
  }

  async submitCode(code: string): Promise<void> {
    const request: TdRequest = { '@type': 'checkAuthenticationCode' };
    request['code'] = code;
    await this.client.send(request);
  }

  async submitPassword(pw: string): Promise<void> {
    const request: TdRequest = { '@type': 'checkAuthenticationPassword' };
    request['password'] = pw;
    await this.client.send(request);
  }

  async logOut(): Promise<void> {
    const request: TdRequest = { '@type': 'logOut' };
    await this.client.send(request);
  }

  async resendCode(): Promise<void> {
    const request: TdRequest = { '@type': 'resendAuthenticationCode' };
    await this.client.send(request);
  }

  private onAuthState(update: TdObject): void {
    const state = update['authorization_state'] as TdObject;
    const type = state['@type'] as string;
    hilog.info(0x0000, 'TDLib', '[TDLib] auth state -> %{public}s', type);
    if (type === 'authorizationStateWaitTdlibParameters') {
      this.sendTdlibParameters();
      return;
    }
    const stage = STATE_TO_STAGE.get(type);
    if (stage !== undefined) {
      this.currentStage = stage;
      for (const cb of this.callbacks) {
        cb(stage);
      }
    }
  }

  private sendTdlibParameters(): void {
    const request: TdRequest = { '@type': 'setTdlibParameters' };
    request['use_test_dc'] = USE_TEST_DC;
    request['database_directory'] = `${this.filesDir}/tdlib`;
    request['files_directory'] = `${this.filesDir}/tdlib_files`;
    request['use_message_database'] = true;
    request['use_secret_chats'] = false;
    request['api_id'] = clientRev;
    request['api_hash'] = clientSig;
    request['system_language_code'] = 'en';
    request['device_model'] = 'HarmonyOS Device';
    request['application_version'] = '0.1.0';
    this.client.send(request).catch((e: Error) => {
      console.error(`setTdlibParameters failed: ${e.message}`);
    });
  }
}

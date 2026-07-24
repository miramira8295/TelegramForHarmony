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
  private databaseDirectory: string;
  private filesDirectory: string;
  private callbacks: Array<(stage: AuthStage) => void> = [];
  private closedCallbacks: Array<() => void> = [];
  private currentStage: AuthStage = AuthStage.Init;
  private currentAuthType: string = '';
  private authenticationPhoneNumber: string = '';
  private authenticationCodeLength: number = 5;
  private authenticationCodeType: string = '';
  private authenticationCodeDestination: string = '';
  private nextAuthenticationCodeType: string = '';
  private offAuthorizationState: (() => void) | null = null;

  constructor(client: TdClient, databaseDirectory: string, filesDirectory: string) {
    this.client = client;
    this.databaseDirectory = databaseDirectory;
    this.filesDirectory = filesDirectory;
    this.offAuthorizationState =
      client.onUpdate('updateAuthorizationState', (u: TdObject) => this.onAuthState(u));
  }

  // Registers a listener and immediately replays the current stage, so a
  // subscriber that mounts after the auth state has already arrived is not
  // left waiting for the next transition.
  onStageChange(cb: (stage: AuthStage) => void): () => void {
    this.callbacks = [...this.callbacks, cb];
    cb(this.currentStage);
    return (): void => {
      this.callbacks = this.callbacks.filter(
        (current: (stage: AuthStage) => void): boolean => current !== cb
      );
    };
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
    if (this.currentAuthType === 'authorizationStateClosed') {
      return;
    }
    await new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
      let finished: boolean = false;
      let timer: number = -1;
      const complete = (): void => {
        if (finished) { return; }
        finished = true;
        if (timer !== -1) { clearTimeout(timer); }
        this.closedCallbacks = this.closedCallbacks.filter(
          (callback: () => void): boolean => callback !== complete
        );
        resolve();
      };
      this.closedCallbacks = [...this.closedCallbacks, complete];
      timer = setTimeout((): void => {
        if (finished) { return; }
        finished = true;
        this.closedCallbacks = this.closedCallbacks.filter(
          (callback: () => void): boolean => callback !== complete
        );
        reject(new Error('等待账号退出完成超时'));
      }, 15000);
    });
  }

  async resendCode(): Promise<void> {
    const request: TdRequest = { '@type': 'resendAuthenticationCode' };
    await this.client.send(request);
  }

  getPhoneNumber(): string {
    return this.authenticationPhoneNumber;
  }

  getCodeLength(): number {
    return this.authenticationCodeLength;
  }

  getCodeType(): string {
    return this.authenticationCodeType;
  }

  getCodeDestination(): string {
    return this.authenticationCodeDestination;
  }

  getNextCodeType(): string {
    return this.nextAuthenticationCodeType;
  }

  closeDatabase(): Promise<void> {
    if (this.currentAuthType === 'authorizationStateClosed') {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      let finished: boolean = false;
      let timer: number = -1;
      const complete = (): void => {
        if (finished) { return; }
        finished = true;
        if (timer !== -1) { clearTimeout(timer); }
        this.closedCallbacks = this.closedCallbacks.filter(
          (callback: () => void): boolean => callback !== complete
        );
        resolve();
      };
      this.closedCallbacks = [...this.closedCallbacks, complete];
      timer = setTimeout((): void => {
        console.warn('AuthService.closeDatabase timed out; recreating TDLib client');
        complete();
      }, 5000);
      const request: TdRequest = { '@type': 'close' };
      this.client.send(request, 5000).catch((caught: Error): void => {
        console.error(`AuthService.closeDatabase failed: ${caught.message}`);
        complete();
      });
    });
  }

  dispose(): void {
    if (this.offAuthorizationState !== null) {
      this.offAuthorizationState();
      this.offAuthorizationState = null;
    }
    this.callbacks = [];
    const closed = this.closedCallbacks;
    this.closedCallbacks = [];
    for (const callback of closed) { callback(); }
  }

  private onAuthState(update: TdObject): void {
    const state = update['authorization_state'] as TdObject;
    const type = state['@type'] as string;
    this.currentAuthType = type;
    hilog.info(0x0000, 'TDLib', '[TDLib] auth state -> %{public}s', type);
    if (type === 'authorizationStateWaitTdlibParameters') {
      this.sendTdlibParameters();
      return;
    }
    if (type === 'authorizationStateWaitCode') {
      const codeInfo = state['code_info'] as TdObject | undefined;
      this.authenticationPhoneNumber =
        (codeInfo?.['phone_number'] as string | undefined) ?? '';
      const codeType = codeInfo?.['type'] as TdObject | undefined;
      this.authenticationCodeType =
        (codeType?.['@type'] as string | undefined) ?? '';
      this.authenticationCodeDestination =
        (codeType?.['email_address_pattern'] as string | undefined) ??
        (codeType?.['phone_number_prefix'] as string | undefined) ??
        (codeType?.['url'] as string | undefined) ?? '';
      const nextCodeType = codeInfo?.['next_type'] as TdObject | undefined;
      this.nextAuthenticationCodeType =
        (nextCodeType?.['@type'] as string | undefined) ?? '';
      const length = (codeType?.['length'] as number | undefined) ?? 5;
      this.authenticationCodeLength = Math.max(4, Math.min(8, length));
      hilog.info(
        0x0000,
        'TDLib',
        '[TDLib] authentication code delivery -> %{public}s, next -> %{public}s',
        this.authenticationCodeType,
        this.nextAuthenticationCodeType
      );
    }
    const stage = STATE_TO_STAGE.get(type);
    if (stage !== undefined) {
      this.currentStage = stage;
      for (const cb of this.callbacks) {
        cb(stage);
      }
    }
    if (type === 'authorizationStateClosed') {
      const closed = this.closedCallbacks;
      this.closedCallbacks = [];
      for (const callback of closed) { callback(); }
    }
  }

  private sendTdlibParameters(): void {
    const request: TdRequest = { '@type': 'setTdlibParameters' };
    request['use_test_dc'] = USE_TEST_DC;
    request['database_directory'] = this.databaseDirectory;
    request['files_directory'] = this.filesDirectory;
    request['use_message_database'] = true;
    request['use_secret_chats'] = false;
    request['api_id'] = clientRev;
    request['api_hash'] = clientSig;
    request['system_language_code'] = 'zh-Hans';
    request['device_model'] = 'HarmonyOS Device';
    request['application_version'] = '0.1.0';
    this.client.send(request).catch((e: Error) => {
      console.error(`setTdlibParameters failed: ${e.message}`);
    });
  }
}

import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { AuthService, AuthStage } from '../main/ets/tdkit/AuthService';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void;
  sent: string[];

  constructor() {
    this.sent = [];
    this.onReceive = (json: string): void => {};
  }

  init(cb: (json: string) => void): void {
    this.onReceive = cb;
  }

  send(json: string): void {
    this.sent.push(json);
  }
}

function pushAuthState(bridge: FakeBridge, stateType: string): void {
  const authState: TdObject = { '@type': stateType };
  const update: TdObject = {
    '@type': 'updateAuthorizationState',
    'authorization_state': authState
  };
  bridge.onReceive(JSON.stringify(update));
}

function parseJson(json: string): TdObject {
  return JSON.parse(json) as TdObject;
}

function lastSent(sent: string[]): TdObject {
  return parseJson(sent[sent.length - 1]);
}

export default function authServiceTest() {
  describe('AuthService', () => {
    it('sends_parameters_on_wait_tdlib_parameters', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files');
      client.start();
      pushAuthState(bridge, 'authorizationStateWaitTdlibParameters');
      const sent: TdObject = lastSent(bridge.sent);
      expect(sent['@type']).assertEqual('setTdlibParameters');
      expect(sent['database_directory']).assertEqual('/data/test/files/tdlib');
    });

    it('maps_states_to_stages', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files');
      const stages: AuthStage[] = [];
      // onStageChange replays the current stage (Init) on registration.
      auth.onStageChange((s: AuthStage) => { stages.push(s); });
      client.start();
      pushAuthState(bridge, 'authorizationStateWaitPhoneNumber');
      pushAuthState(bridge, 'authorizationStateWaitCode');
      pushAuthState(bridge, 'authorizationStateWaitPassword');
      pushAuthState(bridge, 'authorizationStateReady');
      expect(stages.join(',')).assertEqual(
        [AuthStage.Init, AuthStage.WaitPhone, AuthStage.WaitCode, AuthStage.WaitPassword, AuthStage.Ready].join(','));
    });

    it('submitPhone_sends_setAuthenticationPhoneNumber', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const auth = new AuthService(client, '/data/test/files');
      client.start();
      auth.submitPhone('+8613800138000');
      const sent: TdObject = lastSent(bridge.sent);
      expect(sent['@type']).assertEqual('setAuthenticationPhoneNumber');
      expect(sent['phone_number']).assertEqual('+8613800138000');
    });
  });
}

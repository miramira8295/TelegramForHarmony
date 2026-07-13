import { describe, it, expect } from '@ohos/hypium';
import { inviteLinkOf, bareUsernameOf } from '../main/ets/util/linkNav';

export default function linkNavTest() {
  describe('inviteLinkOf', () => {
    it('plus_hash', 0, () => {
      expect(inviteLinkOf('https://t.me/+ajdklsd')).assertEqual('https://t.me/+ajdklsd');
    });
    it('plus_hash_no_scheme', 0, () => {
      expect(inviteLinkOf('t.me/+Ab_c1D')).assertEqual('https://t.me/+Ab_c1D');
    });
    it('joinchat_form', 0, () => {
      expect(inviteLinkOf('https://t.me/joinchat/AbCdEf123')).assertEqual('https://t.me/joinchat/AbCdEf123');
    });
    it('strips_query', 0, () => {
      expect(inviteLinkOf('https://t.me/+ajdklsd?foo=1')).assertEqual('https://t.me/+ajdklsd');
    });
    it('phone_number_not_invite', 0, () => {
      // t.me/+<digits> is a phone-number link, not an invite.
      expect(inviteLinkOf('https://t.me/+8615551234567')).assertEqual('');
    });
    it('username_not_invite', 0, () => {
      expect(inviteLinkOf('https://t.me/somechannel')).assertEqual('');
    });
    it('other_host_not_invite', 0, () => {
      expect(inviteLinkOf('https://example.com/+ajdklsd')).assertEqual('');
    });
    it('bare_plus_not_invite', 0, () => {
      expect(inviteLinkOf('https://t.me/+')).assertEqual('');
    });
  });
  describe('bareUsernameOf_invites_excluded', () => {
    it('plus_link_excluded', 0, () => {
      expect(bareUsernameOf('https://t.me/+ajdklsd')).assertEqual('');
    });
    it('plain_username_kept', 0, () => {
      expect(bareUsernameOf('https://t.me/telegram')).assertEqual('telegram');
    });
  });
}

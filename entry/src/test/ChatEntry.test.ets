import { describe, it, expect } from '@ohos/hypium';
import { computeInitials, compareOrderDesc, isMutedFrom } from '../main/ets/store/ChatEntry';
import { TdObject } from '../main/ets/tdkit/TdTypes';

export default function chatEntryTest() {
  describe('ChatEntry', () => {
    it('initials_two_words', 0, () => {
      expect(computeInitials('Linux Do')).assertEqual('LD');
    });
    it('initials_one_word', 0, () => {
      expect(computeInitials('Telegram')).assertEqual('T');
    });
    it('initials_empty', 0, () => {
      expect(computeInitials('')).assertEqual('?');
    });
    it('order_longer_is_bigger', 0, () => {
      // 7000000000 > 999999999 -> desc puts longer first (negative)
      expect(compareOrderDesc('7000000000', '999999999') < 0).assertEqual(true);
    });
    it('order_same_length_lexicographic', 0, () => {
      expect(compareOrderDesc('900', '800') < 0).assertEqual(true);
    });
    it('muted_true', 0, () => {
      const ns: TdObject = { '@type': 'chatNotificationSettings' };
      ns['mute_for'] = 3600;
      expect(isMutedFrom(ns)).assertEqual(true);
    });
    it('muted_false_undefined', 0, () => {
      expect(isMutedFrom(undefined)).assertEqual(false);
    });
  });
}

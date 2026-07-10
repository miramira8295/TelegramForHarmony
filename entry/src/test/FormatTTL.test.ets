import { describe, it, expect } from '@ohos/hypium';
import { formatTTL } from '../main/ets/util/formatTTL';

export default function formatTTLTest() {
  describe('formatTTL', () => {
    it('disabled_empty', 0, () => {
      expect(formatTTL(0)).assertEqual('');
      expect(formatTTL(-5)).assertEqual('');
    });
    it('seconds', 0, () => {
      expect(formatTTL(30)).assertEqual('30s');
    });
    it('minutes', 0, () => {
      expect(formatTTL(900)).assertEqual('15m');
    });
    it('hours', 0, () => {
      expect(formatTTL(10800)).assertEqual('3h');
    });
    it('days', 0, () => {
      expect(formatTTL(172800)).assertEqual('2d');
    });
    it('weeks', 0, () => {
      expect(formatTTL(604800)).assertEqual('1w');
    });
  });
}

import { describe, it, expect } from '@ohos/hypium';
import { formatUserStatus } from '../main/ets/util/formatUserStatus';
import { TdObject } from '../main/ets/tdkit/TdTypes';

export default function formatUserStatusTest() {
  describe('formatUserStatus', () => {
    it('online', 0, () => {
      const s: TdObject = { '@type': 'userStatusOnline' };
      expect(formatUserStatus(s, 1000)).assertEqual('在线');
    });
    it('recently', 0, () => {
      const s: TdObject = { '@type': 'userStatusRecently' };
      expect(formatUserStatus(s, 1000)).assertEqual('最近在线');
    });
    it('offline_minutes', 0, () => {
      const s: TdObject = { '@type': 'userStatusOffline' }; s['was_online'] = 940;
      expect(formatUserStatus(s, 1000)).assertEqual('最后上线 1 分钟前');
    });
    it('offline_just_now', 0, () => {
      const s: TdObject = { '@type': 'userStatusOffline' }; s['was_online'] = 980;
      expect(formatUserStatus(s, 1000)).assertEqual('最后上线 刚刚');
    });
    it('empty_and_undefined', 0, () => {
      expect(formatUserStatus({ '@type': 'userStatusEmpty' }, 1000)).assertEqual('');
      expect(formatUserStatus(undefined, 1000)).assertEqual('');
    });
  });
}

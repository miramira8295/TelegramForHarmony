import { describe, it, expect } from '@ohos/hypium';
import { formatTime } from '../main/ets/util/formatTime';

function pad2(n: number): string { return n < 10 ? `0${n}` : `${n}`; }
const WD: string[] = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
const MO: string[] = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const NOW = 1783512000;

export default function formatTimeTest() {
  describe('formatTime', () => {
    it('empty_for_zero', 0, () => {
      expect(formatTime(0, NOW)).assertEqual('');
    });
    it('same_day_hh_mm', 0, () => {
      const d = new Date(NOW * 1000);
      expect(formatTime(NOW, NOW)).assertEqual(`${pad2(d.getHours())}:${pad2(d.getMinutes())}`);
    });
    it('within_week_weekday', 0, () => {
      const t = NOW - 3 * 86400;
      const d = new Date(t * 1000);
      expect(formatTime(t, NOW)).assertEqual(WD[d.getDay()]);
    });
    it('same_year_month_day', 0, () => {
      const t = NOW - 100 * 86400;
      const d = new Date(t * 1000);
      const n = new Date(NOW * 1000);
      if (d.getFullYear() === n.getFullYear()) {
        expect(formatTime(t, NOW)).assertEqual(`${MO[d.getMonth()]} ${d.getDate()}`);
      } else {
        expect(formatTime(t, NOW)).assertEqual(`${d.getMonth() + 1}/${d.getDate()}/${pad2(d.getFullYear() % 100)}`);
      }
    });
    it('older_numeric', 0, () => {
      const t = NOW - 400 * 86400;
      const d = new Date(t * 1000);
      expect(formatTime(t, NOW)).assertEqual(`${d.getMonth() + 1}/${d.getDate()}/${pad2(d.getFullYear() % 100)}`);
    });
  });
}

const WEEKDAYS: string[] = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

export function formatTime(unixSec: number, nowSec: number): string {
  if (unixSec <= 0) {
    return '';
  }
  const d = new Date(unixSec * 1000);
  const now = new Date(nowSec * 1000);
  const sameDay = d.getFullYear() === now.getFullYear()
    && d.getMonth() === now.getMonth()
    && d.getDate() === now.getDate();
  if (sameDay) {
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  }
  const deltaDays = (nowSec - unixSec) / 86400;
  if (deltaDays >= 0 && deltaDays < 7) {
    return WEEKDAYS[d.getDay()];
  }
  if (d.getFullYear() === now.getFullYear()) {
    return `${MONTHS[d.getMonth()]} ${d.getDate()}`;
  }
  const yy = pad2(d.getFullYear() % 100);
  return `${d.getMonth() + 1}/${d.getDate()}/${yy}`;
}

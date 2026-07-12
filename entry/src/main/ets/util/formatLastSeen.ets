import { TdObject } from '../tdkit/TdTypes';

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

// "最近上线于" line for the contacts list. Unlike formatUserStatus (which gives
// a coarse "X 分钟前"), this mirrors the official client's concrete clock time:
// today → HH:mm, yesterday → 昨天 HH:mm, this year → M月D日 HH:mm.
export function formatLastSeen(status: TdObject | undefined, nowSec: number): string {
  if (status === undefined) {
    return '';
  }
  const type = status['@type'] as string | undefined;
  if (type === 'userStatusOnline') {
    return '在线';
  }
  if (type === 'userStatusRecently') {
    return '最近曾上线';
  }
  if (type === 'userStatusLastWeek') {
    return '一周内上线';
  }
  if (type === 'userStatusLastMonth') {
    return '一个月内上线';
  }
  if (type !== 'userStatusOffline') {
    return '';
  }
  const was = (status['was_online'] as number | undefined) ?? 0;
  if (was <= 0) {
    return '最近曾上线';
  }
  const d = new Date(was * 1000);
  const now = new Date(nowSec * 1000);
  const hm = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  const sameDay = d.getFullYear() === now.getFullYear()
    && d.getMonth() === now.getMonth()
    && d.getDate() === now.getDate();
  if (sameDay) {
    return `最近上线于 ${hm}`;
  }
  const y = new Date((nowSec - 86400) * 1000);
  const yesterday = d.getFullYear() === y.getFullYear()
    && d.getMonth() === y.getMonth()
    && d.getDate() === y.getDate();
  if (yesterday) {
    return `最近上线于 昨天 ${hm}`;
  }
  if (d.getFullYear() === now.getFullYear()) {
    return `最近上线于 ${d.getMonth() + 1}月${d.getDate()}日 ${hm}`;
  }
  return `最近上线于 ${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 ${hm}`;
}

import { TdObject } from '../tdkit/TdTypes';

function relative(wasOnline: number, nowSec: number): string {
  const d = nowSec - wasOnline;
  if (d < 60) {
    return '刚刚';
  }
  if (d < 3600) {
    return `${Math.floor(d / 60)} 分钟前`;
  }
  if (d < 86400) {
    return `${Math.floor(d / 3600)} 小时前`;
  }
  return `${Math.floor(d / 86400)} 天前`;
}

export function formatUserStatus(status: TdObject | undefined, nowSec: number): string {
  if (status === undefined) {
    return '';
  }
  const type = status['@type'] as string | undefined;
  if (type === 'userStatusOnline') {
    return '在线';
  }
  if (type === 'userStatusOffline') {
    const wasOnline = (status['was_online'] as number | undefined) ?? 0;
    return `最后上线 ${relative(wasOnline, nowSec)}`;
  }
  if (type === 'userStatusRecently') {
    return '最近在线';
  }
  if (type === 'userStatusLastWeek') {
    return '一周内上线';
  }
  if (type === 'userStatusLastMonth') {
    return '一个月内上线';
  }
  return '';
}

import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';

// Thin, promise-shaped wrappers around the TDLib privacy/security calls used by
// 隐私与安全. No caching and no subscriptions: every one of these values is
// account state that only changes when the user changes it here, so the pages
// simply re-read on appear.

// The three choices the UI offers for a privacy setting. TDLib models a setting
// as an ordered rule list; these are the *base* rule, i.e. the last one.
export const RULE_EVERYBODY: string = 'everybody';
export const RULE_CONTACTS: string = 'contacts';
export const RULE_NOBODY: string = 'nobody';

// Per-user / per-chat exceptions ("Nobody (+6)"). We never author these — the
// UI has no exception editor — but we must carry them through a base-rule
// change, or picking a new base would silently wipe the user's allow list.
const EXCEPTION_RULES: string[] = [
  'userPrivacySettingRuleAllowUsers',
  'userPrivacySettingRuleAllowChatMembers',
  'userPrivacySettingRuleRestrictUsers',
  'userPrivacySettingRuleRestrictChatMembers'
];

export interface PrivacyValue {
  base: string;
  exceptions: number;  // how many users/chats the carried-over rules name
  extra: TdObject[];   // the exception rules, verbatim, to be re-sent on write
}

function baseOf(rules: TdObject[]): string {
  for (const r of rules) {
    const t = (r['@type'] as string | undefined) ?? '';
    if (t === 'userPrivacySettingRuleAllowAll') {
      return RULE_EVERYBODY;
    }
    if (t === 'userPrivacySettingRuleAllowContacts') {
      return RULE_CONTACTS;
    }
    if (t === 'userPrivacySettingRuleRestrictAll') {
      return RULE_NOBODY;
    }
  }
  // No base rule at all means nobody is allowed beyond the exceptions.
  return RULE_NOBODY;
}

function countExceptions(rules: TdObject[]): number {
  let n = 0;
  for (const r of rules) {
    const users = r['user_ids'] as number[] | undefined;
    const chats = r['chat_ids'] as number[] | undefined;
    n += users !== undefined ? users.length : 0;
    n += chats !== undefined ? chats.length : 0;
  }
  return n;
}

function baseRule(base: string): TdObject {
  if (base === RULE_EVERYBODY) {
    return { '@type': 'userPrivacySettingRuleAllowAll' } as TdObject;
  }
  if (base === RULE_CONTACTS) {
    return { '@type': 'userPrivacySettingRuleAllowContacts' } as TdObject;
  }
  return { '@type': 'userPrivacySettingRuleRestrictAll' } as TdObject;
}

export function ruleLabel(v: PrivacyValue): string {
  const base = v.base === RULE_EVERYBODY ? '所有人' : (v.base === RULE_CONTACTS ? '我的联系人' : '没有人');
  return v.exceptions > 0 ? `${base} (+${v.exceptions})` : base;
}

export async function getPrivacy(setting: string): Promise<PrivacyValue> {
  const req: TdRequest = { '@type': 'getUserPrivacySettingRules' };
  req['setting'] = { '@type': setting } as TdObject;
  const res = await getTdClient().send(req);
  const rules = (res['rules'] as TdObject[] | undefined) ?? [];
  const extra = rules.filter((r: TdObject) =>
    EXCEPTION_RULES.indexOf((r['@type'] as string | undefined) ?? '') >= 0);
  return { base: baseOf(rules), exceptions: countExceptions(extra), extra };
}

// Exceptions first, base rule last — TDLib applies the first matching rule.
export async function setPrivacy(setting: string, base: string, extra: TdObject[]): Promise<void> {
  const req: TdRequest = { '@type': 'setUserPrivacySettingRules' };
  req['setting'] = { '@type': setting } as TdObject;
  req['rules'] = {
    '@type': 'userPrivacySettingRules',
    'rules': [...extra, baseRule(base)]
  } as TdObject;
  await getTdClient().send(req);
}

export async function hasPassword(): Promise<boolean> {
  const res = await getTdClient().send({ '@type': 'getPasswordState' } as TdRequest);
  return (res['has_password'] as boolean | undefined) ?? false;
}

export async function getAutoDeleteSeconds(): Promise<number> {
  const res = await getTdClient().send({ '@type': 'getDefaultMessageAutoDeleteTime' } as TdRequest);
  return (res['time'] as number | undefined) ?? 0;
}

export async function setAutoDeleteSeconds(seconds: number): Promise<void> {
  const req: TdRequest = { '@type': 'setDefaultMessageAutoDeleteTime' };
  req['message_auto_delete_time'] = { '@type': 'messageAutoDeleteTime', 'time': seconds } as TdObject;
  await getTdClient().send(req);
}

// total_count comes back as 0 unless the senders are actually fetched, so ask
// for a full page and count what we get.
export async function getBlockedCount(): Promise<number> {
  const req: TdRequest = { '@type': 'getBlockedMessageSenders' };
  req['block_list'] = { '@type': 'blockListMain' } as TdObject;
  req['offset'] = 0;
  req['limit'] = 100;
  const res = await getTdClient().send(req);
  const senders = ((res['senders'] as TdObject[] | undefined) ?? []).length;
  const total = (res['total_count'] as number | undefined) ?? 0;
  return Math.max(total, senders);
}

export async function getSessionCount(): Promise<number> {
  const res = await getTdClient().send({ '@type': 'getActiveSessions' } as TdRequest);
  return ((res['sessions'] as TdObject[] | undefined) ?? []).length;
}

export async function getAccountTtlDays(): Promise<number> {
  const res = await getTdClient().send({ '@type': 'getAccountTtl' } as TdRequest);
  return (res['days'] as number | undefined) ?? 0;
}

export async function setAccountTtlDays(days: number): Promise<void> {
  const req: TdRequest = { '@type': 'setAccountTtl' };
  req['ttl'] = { '@type': 'accountTtl', 'days': days } as TdObject;
  await getTdClient().send(req);
}

export async function getBoolOption(name: string): Promise<boolean> {
  const req: TdRequest = { '@type': 'getOption' };
  req['name'] = name;
  try {
    const res = await getTdClient().send(req);
    return (res['value'] as boolean | undefined) ?? false;
  } catch (e) {
    const err = e as TdError;
    console.error(`PrivacyApi.getOption(${name}) failed: ${err.message}`);
    return false;
  }
}

export async function setBoolOption(name: string, value: boolean): Promise<void> {
  const req: TdRequest = { '@type': 'setOption' };
  req['name'] = name;
  req['value'] = { '@type': 'optionValueBoolean', 'value': value } as TdObject;
  await getTdClient().send(req);
}

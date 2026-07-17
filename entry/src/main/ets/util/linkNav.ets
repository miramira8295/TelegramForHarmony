// A tapped link normalized to a full t.me URL suitable for TDLib's
// getMessageLinkInfo, or '' if it isn't a Telegram link at all (plain web
// links open in the system browser instead).
//
// Handles: https://t.me/<username>, https://t.me/<username>/<messageId>
// (channel post links, e.g. .../DocOfCard_Channel/2429), and @<username>.
export function normalizeTelegramLink(url: string): string {
  const raw = url.trim();
  if (raw.startsWith('@')) {
    const name = raw.substring(1);
    return isUsername(name) ? `https://t.me/${name}` : '';
  }
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  const slash = rest.indexOf('/');
  const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
  if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
    return '';
  }
  return raw;
}

// Username for links that point at a chat/user directly — '@name' or a t.me
// link with a single path segment. '' for message links / invites / web URLs.
export function bareUsernameOf(url: string): string {
  const raw = url.trim();
  if (raw.startsWith('@')) {
    const name = raw.substring(1);
    return isUsername(name) ? name : '';
  }
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  const slash = rest.indexOf('/');
  const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
  if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
    return '';
  }
  if (slash < 0) {
    return '';
  }
  // Drop any query/fragment (bot start params, ?comment=, #anchor, …) before
  // splitting — otherwise t.me/<name>?start=xxx isn't recognized as a username
  // link and wrongly falls through to the browser.
  const seg = rest.substring(slash + 1);
  const clean = seg.split('?')[0].split('#')[0];
  const parts = clean.split('/').filter((p: string) => p.length > 0);
  if (parts.length !== 1 || parts[0].startsWith('+') || parts[0].toLowerCase() === 'joinchat') {
    return '';
  }
  return isUsername(parts[0]) ? parts[0] : '';
}

// Private-chat invite link (t.me/+<hash> or t.me/joinchat/<hash>) normalized
// with an https:// scheme for TDLib's checkChatInviteLink, or '' if the URL
// isn't an invite. t.me/+<digits only> is a phone-number link, not an invite
// (real invite hashes always contain letters), so it's excluded.
export function inviteLinkOf(url: string): string {
  const raw = url.trim();
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  const slash = rest.indexOf('/');
  const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
  if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
    return '';
  }
  if (slash < 0) {
    return '';
  }
  const clean = rest.substring(slash + 1).split('?')[0].split('#')[0];
  const parts = clean.split('/').filter((p: string) => p.length > 0);
  if (parts.length === 1 && parts[0].startsWith('+')) {
    const hash = parts[0].substring(1);
    return hash !== '' && !isAllDigits(hash) ? `https://t.me/+${hash}` : '';
  }
  if (parts.length === 2 && parts[0].toLowerCase() === 'joinchat' && parts[1] !== '') {
    return `https://t.me/joinchat/${parts[1]}`;
  }
  return '';
}

// A chat link that carries an action in its query string:
// t.me/<bot>?start=<payload>  → open the bot chat and auto-send /start <payload>
// t.me/<name>?text=<draft>    → open the chat with a prefilled draft
// tg://resolve?domain=<name>&start=/&text= is the deep-link equivalent.
export interface ChatLinkAction {
  username: string;
  startParam: string; // ?start= payload ('' = none)
  draftText: string;  // ?text= prefill ('' = none)
}

function queryParamOf(query: string, key: string): string {
  for (const pair of query.split('&')) {
    const eq = pair.indexOf('=');
    if (eq <= 0 || pair.substring(0, eq) !== key) {
      continue;
    }
    const raw = pair.substring(eq + 1).replace(/\+/g, ' ');
    try {
      return decodeURIComponent(raw);
    } catch (_e) {
      return raw; // malformed escape — use it verbatim rather than dropping it
    }
  }
  return '';
}

// Parse a username link whose query carries a start/text action; null when the
// link has no such action (plain username links keep their existing routing).
export function chatLinkActionOf(url: string): ChatLinkAction | null {
  const raw = url.trim();
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  let username = '';
  let query = '';
  if (raw.startsWith('tg://') || raw.startsWith('tg:resolve')) {
    // tg://resolve?domain=<name>&start=... — the host segment IS the action.
    const q = rest.indexOf('?');
    if (q < 0 || !rest.substring(0, q).startsWith('resolve')) {
      return null;
    }
    query = rest.substring(q + 1).split('#')[0];
    username = queryParamOf(query, 'domain');
  } else {
    const slash = rest.indexOf('/');
    const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
    if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
      return null;
    }
    if (slash < 0) {
      return null;
    }
    const seg = rest.substring(slash + 1);
    const q = seg.indexOf('?');
    if (q < 0) {
      return null;
    }
    query = seg.substring(q + 1).split('#')[0];
    const parts = seg.substring(0, q).split('/').filter((p: string) => p.length > 0);
    if (parts.length !== 1) {
      return null;
    }
    username = parts[0];
  }
  if (!isUsername(username)) {
    return null;
  }
  const startParam = queryParamOf(query, 'start');
  const draftText = queryParamOf(query, 'text');
  if (startParam === '' && draftText === '') {
    return null;
  }
  return { username, startParam, draftText };
}

function isAllDigits(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 48 || c > 57) {
      return false;
    }
  }
  return true;
}

function isUsername(name: string): boolean {
  if (name.length < 3 || name.length > 32) {
    return false;
  }
  for (let i = 0; i < name.length; i++) {
    const c = name.charCodeAt(i);
    const isDigit = c >= 48 && c <= 57;
    const isUpper = c >= 65 && c <= 90;
    const isLower = c >= 97 && c <= 122;
    const isUnderscore = c === 95;
    if (!isDigit && !isUpper && !isLower && !isUnderscore) {
      return false;
    }
  }
  return true;
}

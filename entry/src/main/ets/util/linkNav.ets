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

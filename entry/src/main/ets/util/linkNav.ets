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
  const parts = rest.substring(slash + 1).split('/').filter((p: string) => p.length > 0);
  if (parts.length !== 1 || parts[0].startsWith('+') || parts[0].toLowerCase() === 'joinchat') {
    return '';
  }
  return isUsername(parts[0]) ? parts[0] : '';
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

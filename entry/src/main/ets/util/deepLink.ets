import { common } from '@kit.AbilityKit';
import { openTelegramLink } from './openTelegramLink';

// Incoming deep links arrive as tg:// URIs (a browser https://t.me link can't
// hand off to a third-party client — see module.json5). Map the tg:// forms
// onto the t.me URL shape openTelegramLink already routes, then reuse that one
// shared router so deep links behave exactly like tapping an in-message link.

// Value of `key` in a `a=1&b=2` query string, URI-decoded ('' if absent).
function queryParam(query: string, key: string): string {
  for (const pair of query.split('&')) {
    const eq = pair.indexOf('=');
    if (eq < 0) {
      continue;
    }
    if (pair.substring(0, eq) === key) {
      try {
        return decodeURIComponent(pair.substring(eq + 1));
      } catch (e) {
        return pair.substring(eq + 1);
      }
    }
  }
  return '';
}

// tg://resolve?domain=foo&post=12 → https://t.me/foo/12
// tg://resolve?domain=foo         → https://t.me/foo
// tg://join?invite=HASH           → https://t.me/+HASH
// tg://user?id=123 and anything else are left untouched — openTelegramLink
// handles tg://user directly and falls back to the browser for the rest.
export function tgSchemeToUrl(uri: string): string {
  if (!uri.startsWith('tg://')) {
    return uri;
  }
  const rest = uri.substring('tg://'.length);
  const q = rest.indexOf('?');
  const action = q >= 0 ? rest.substring(0, q) : rest;
  const query = q >= 0 ? rest.substring(q + 1) : '';
  if (action === 'resolve') {
    const domain = queryParam(query, 'domain');
    if (domain === '') {
      return uri;
    }
    const post = queryParam(query, 'post');
    return post !== '' ? `https://t.me/${domain}/${post}` : `https://t.me/${domain}`;
  }
  if (action === 'join') {
    const invite = queryParam(query, 'invite');
    return invite !== '' ? `https://t.me/+${invite}` : uri;
  }
  return uri;
}

// Route a raw incoming deep-link URI into the app.
export function handleIncomingLink(context: common.UIAbilityContext, rawUri: string): void {
  const uri = rawUri.trim();
  if (uri === '') {
    return;
  }
  // allowBrowser=false: a deep link that fails to resolve must NOT re-open the
  // system browser — that bounces browser → app → browser. Fail with a toast.
  openTelegramLink(context, tgSchemeToUrl(uri), false);
}

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { normalizeTelegramLink, bareUsernameOf } from './linkNav';
import { openUrl } from './openUrl';

// Full in-app routing for a tapped link outside the chat page (profile bios,
// channel descriptions, ...): text mentions open the profile card, usernames
// resolve to a profile/chat, message links open the chat at the message, and
// everything else goes to the system browser.
export function openTelegramLink(context: common.UIAbilityContext, url: string): void {
  if (url === '') {
    return;
  }
  if (url.startsWith('tg://user?id=')) {
    const uid = Number(url.substring('tg://user?id='.length));
    if (uid > 0) {
      const params: Record<string, Object> = { 'userId': uid };
      router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
    }
    return;
  }
  const bareName = bareUsernameOf(url);
  if (bareName !== '') {
    const req: TdRequest = { '@type': 'searchPublicChat' };
    req['username'] = bareName;
    getTdClient().send(req).then((chat: TdObject) => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      const type = chat['type'] as TdObject | undefined;
      const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      if (typeName === 'chatTypePrivate') {
        const uid = ((type as TdObject)['user_id'] as number | undefined) ?? 0;
        if (uid > 0) {
          const params: Record<string, Object> = { 'userId': uid };
          router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
          return;
        }
      }
      if (chatId !== 0) {
        const params: Record<string, Object> = { 'chatId': chatId };
        router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
        return;
      }
      openUrl(context, url);
    }).catch((e: TdError) => {
      console.error(`openTelegramLink.searchPublicChat(${bareName}) failed: ${e.message}`);
      openUrl(context, url);
    });
    return;
  }
  const tgUrl = normalizeTelegramLink(url);
  if (tgUrl === '') {
    openUrl(context, url);
    return;
  }
  const req: TdRequest = { '@type': 'getMessageLinkInfo' };
  req['url'] = tgUrl;
  getTdClient().send(req).then((info: TdObject) => {
    const chatId = (info['chat_id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      openUrl(context, url);
      return;
    }
    const msg = info['message'] as TdObject | undefined;
    const msgId = msg !== undefined ? ((msg['id'] as number | undefined) ?? 0) : 0;
    const params: Record<string, Object> = { 'chatId': chatId };
    if (msgId > 0) {
      params['jumpTo'] = msgId;
    }
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }).catch((e: TdError) => {
    console.error(`openTelegramLink.getMessageLinkInfo failed: ${e.message}`);
    openUrl(context, url);
  });
}

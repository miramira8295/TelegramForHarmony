import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { normalizeTelegramLink, bareUsernameOf, inviteLinkOf } from './linkNav';
import { openUrl } from './openUrl';
import { COLOR_PRIMARY } from './theme';

function openChatPage(chatId: number): void {
  const params: Record<string, Object> = { 'chatId': chatId };
  router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
}

// Private invite link (t.me/+hash): preview the chat via checkChatInviteLink;
// already a member → straight into the chat, otherwise confirm and join.
export function openInviteLink(context: common.UIAbilityContext, invite: string, original: string): void {
  const req: TdRequest = { '@type': 'checkChatInviteLink' };
  req['invite_link'] = invite;
  getTdClient().send(req).then((info: TdObject) => {
    const chatId = (info['chat_id'] as number | undefined) ?? 0;
    if (chatId !== 0) {
      openChatPage(chatId);
      return;
    }
    const title = (info['title'] as string | undefined) ?? '';
    const count = (info['member_count'] as number | undefined) ?? 0;
    promptAction.showDialog({
      title: '加入群组',
      message: count > 0 ? `「${title}」· ${count} 位成员` : `「${title}」`,
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '加入', color: $r('app.color.primary') }
      ]
    }).then((r) => {
      if (r.index !== 1) {
        return;
      }
      const join: TdRequest = { '@type': 'joinChatByInviteLink' };
      join['invite_link'] = invite;
      getTdClient().send(join).then((chat: TdObject) => {
        const id = (chat['id'] as number | undefined) ?? 0;
        if (id !== 0) {
          openChatPage(id);
        }
      }).catch((e: TdError) => {
        console.error(`openInviteLink.join failed: ${e.message}`);
        promptAction.showToast({ message: '加入失败,链接可能已失效' });
      });
    });
  }).catch((e: TdError) => {
    // Expired/invalid invite — or a link TDLib can't preview; let the
    // browser show Telegram's own page rather than failing silently.
    console.error(`openInviteLink.check failed: ${e.message}`);
    openUrl(context, original);
  });
}

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
  const invite = inviteLinkOf(url);
  if (invite !== '') {
    openInviteLink(context, invite, url);
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

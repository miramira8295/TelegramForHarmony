import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { normalizeTelegramLink, bareUsernameOf, inviteLinkOf, chatLinkActionOf, ChatLinkAction } from './linkNav';
import { openUrl } from './openUrl';
import { COLOR_PRIMARY } from './theme';

function openChatPage(chatId: number): void {
  const params: Record<string, Object> = { 'chatId': chatId };
  router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
}

// A link that couldn't be resolved in-app. For a tapped in-message link we hand
// off to the system browser; for a deep-link ENTRY point we must not — opening
// the browser there bounces browser → app → browser, so just tell the user.
function onLinkUnresolved(context: common.UIAbilityContext, url: string, allowBrowser: boolean): void {
  if (allowBrowser) {
    openUrl(context, url);
  } else {
    promptAction.showToast({ message: '无法打开该链接', duration: 1500 });
  }
}

// Private invite link (t.me/+hash): preview the chat via checkChatInviteLink;
// already a member → straight into the chat, otherwise confirm and join.
export function openInviteLink(context: common.UIAbilityContext, invite: string, original: string,
    allowBrowser: boolean = true): void {
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
    onLinkUnresolved(context, original, allowBrowser);
  });
}

// Chat link carrying an action payload: resolve the username, enter the chat,
// then auto-send /start (bot ?start= links) or prefill the draft (?text=).
export function openChatLinkAction(context: common.UIAbilityContext, action: ChatLinkAction,
    original: string, allowBrowser: boolean): void {
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = action.username;
  getTdClient().send(req).then((chat: TdObject) => {
    const chatId = (chat['id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    const params: Record<string, Object> = { 'chatId': chatId };
    if (action.draftText !== '') {
      params['draftText'] = action.draftText;
    }
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    if (action.startParam === '') {
      return;
    }
    const type = chat['type'] as TdObject | undefined;
    const uid = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
    if (uid <= 0) {
      return; // ?start= is only meaningful on a private bot chat
    }
    const start: TdRequest = { '@type': 'sendBotStartMessage' };
    start['bot_user_id'] = uid;
    start['chat_id'] = chatId;
    start['parameter'] = action.startParam;
    getTdClient().send(start).catch((e: TdError) => {
      console.error(`openTelegramLink.sendBotStartMessage failed: ${e.message}`);
      promptAction.showToast({ message: '发送 /start 失败', duration: 1500 });
    });
  }).catch((e: TdError) => {
    console.error(`openTelegramLink.searchPublicChat(${action.username}) failed: ${e.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

// Full in-app routing for a tapped link outside the chat page (profile bios,
// channel descriptions, ...): text mentions open the profile card, usernames
// resolve to a profile/chat, message links open the chat at the message, and
// everything else goes to the system browser.
export function openTelegramLink(context: common.UIAbilityContext, url: string,
    allowBrowser: boolean = true): void {
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
    openInviteLink(context, invite, url, allowBrowser);
    return;
  }
  // ?start= / ?text= actions take priority over plain username routing —
  // bareUsernameOf drops the query string, which would lose the payload.
  const action = chatLinkActionOf(url);
  if (action !== null) {
    openChatLinkAction(context, action, url, allowBrowser);
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
      onLinkUnresolved(context, url, allowBrowser);
    }).catch((e: TdError) => {
      console.error(`openTelegramLink.searchPublicChat(${bareName}) failed: ${e.message}`);
      onLinkUnresolved(context, url, allowBrowser);
    });
    return;
  }
  const tgUrl = normalizeTelegramLink(url);
  if (tgUrl === '') {
    onLinkUnresolved(context, url, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'getMessageLinkInfo' };
  req['url'] = tgUrl;
  getTdClient().send(req).then((info: TdObject) => {
    const chatId = (info['chat_id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      onLinkUnresolved(context, url, allowBrowser);
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
    onLinkUnresolved(context, url, allowBrowser);
  });
}

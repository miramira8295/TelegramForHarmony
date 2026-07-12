import { TdObject } from '../tdkit/TdTypes';

function captionText(content: TdObject): string {
  const cap = content['caption'] as TdObject | undefined;
  if (cap === undefined) {
    return '';
  }
  const t = cap['text'] as string | undefined;
  return t ?? '';
}

function mediaLabel(icon: string, word: string, content: TdObject): string {
  const cap = captionText(content);
  return cap !== '' ? `${icon} ${cap}` : `${icon} ${word}`;
}

// Chinese labels for service / status messages so the chat-list preview (and the
// bubble placeholder) never falls back to the bare English 'Message'.
export const SERVICE_LABELS: Record<string, string> = {
  // Group / channel operations
  'messageChatAddMembers': '邀请了新成员',
  'messageChatDeleteMember': '移除了成员',
  'messageChatChangeTitle': '更改了群名称',
  'messageChatChangePhoto': '更改了群头像',
  'messageChatDeletePhoto': '删除了群头像',
  'messageChatJoinByLink': '通过链接加入群组',
  'messageChatJoinByRequest': '加入了群组',
  'messagePinMessage': '置顶了一条消息',
  'messageChatSetMessageAutoDeleteTime': '更改了自动删除设置',
  'messageBasicGroupChatCreate': '创建了群组',
  'messageSupergroupChatCreate': '创建了群组',
  'messageChatUpgradeTo': '群组已升级为超级群组',
  'messageChatUpgradeFrom': '群组已升级为超级群组',
  // Membership / social notices
  'messageContactRegistered': '加入了 Telegram',
  'messageChatSetTheme': '更改了聊天主题',
  'messageChatSetBackground': '更改了聊天背景',
  'messageScreenshotTaken': '截取了屏幕截图',
  'messageChatBoost': '助力了该频道',
  // Forum topics
  'messageForumTopicCreated': '创建了话题',
  'messageForumTopicEdited': '编辑了话题',
  'messageForumTopicIsClosedToggled': '更改了话题状态',
  'messageForumTopicIsHiddenToggled': '更改了话题可见性',
  // Video / voice chats
  'messageVideoChatScheduled': '安排了视频通话',
  'messageVideoChatStarted': '发起了视频通话',
  'messageVideoChatEnded': '结束了视频通话',
  'messageInviteVideoChatParticipants': '邀请参加视频通话',
  'messageProximityAlertTriggered': '触发了距离提醒',
  // Gifts / premium / giveaways
  'messageGiftedPremium': '赠送了 Telegram 会员',
  'messageGiftedStars': '赠送了星星',
  'messagePremiumGiftCode': '赠送了会员兑换码',
  'messageGift': '赠送了礼物',
  'messageUpgradedGift': '赠送了升级礼物',
  'messageGiveawayCreated': '发起了抽奖',
  'messageGiveaway': '抽奖',
  'messageGiveawayCompleted': '抽奖已结束',
  'messageGiveawayWinners': '抽奖结果',
  'messageGiveawayPrizeStars': '星星抽奖',
  // Payments / passport / bot access / sharing
  'messagePaymentSuccessful': '完成了付款',
  'messagePaymentSuccessfulBot': '完成了付款',
  'messagePaymentRefunded': '已退款',
  'messagePassportDataSent': '发送了 Telegram 护照数据',
  'messagePassportDataReceived': '接收了 Telegram 护照数据',
  'messageWebAppDataSent': '发送了小程序数据',
  'messageWebAppDataReceived': '接收了小程序数据',
  'messageBotWriteAccessAllowed': '允许了机器人发送消息',
  'messageUsersShared': '分享了用户',
  'messageChatShared': '分享了群组',
  'messageGameScore': '刷新了游戏得分',
  // Channel paid / direct messages
  'messageDirectMessagePriceChanged': '更改了私信设置',
  'messagePaidMessagePriceChanged': '更改了付费消息价格',
  'messagePaidMessagesRefunded': '付费消息已退款',
  'messageCall': '📞 通话'
};

// Pull any embedded text/caption from an otherwise-unhandled content object.
function embeddedText(content: TdObject): string {
  const cap = content['caption'] as TdObject | undefined;
  const capText = cap !== undefined ? ((cap['text'] as string | undefined) ?? '') : '';
  if (capText !== '') {
    return capText;
  }
  const txt = content['text'] as TdObject | undefined;
  return txt !== undefined ? ((txt['text'] as string | undefined) ?? '') : '';
}

export function formatPreview(message: TdObject | null): string {
  if (message === null) {
    return '';
  }
  const rawContent = message['content'];
  if (rawContent === undefined || rawContent === null) {
    return '';
  }
  const content = rawContent as TdObject;
  const type = content['@type'] as string;
  if (type === 'messageText') {
    const text = content['text'] as TdObject | undefined;
    if (text === undefined) {
      return '';
    }
    const inner = text['text'] as string | undefined;
    return inner ?? '';
  }
  if (type === 'messagePhoto') {
    return mediaLabel('📷', '照片', content);
  }
  if (type === 'messageVideo') {
    return mediaLabel('📹', '视频', content);
  }
  if (type === 'messageVoiceNote') {
    return '🎤 语音消息';
  }
  if (type === 'messageDocument') {
    return mediaLabel('📎', '文件', content);
  }
  if (type === 'messageSticker') {
    const st = content['sticker'] as TdObject | undefined;
    const emoji = st !== undefined ? (st['emoji'] as string) : '';
    return emoji !== '' && emoji !== undefined ? `${emoji} 贴纸` : '贴纸';
  }
  if (type === 'messageAnimation') {
    return 'GIF';
  }
  if (type === 'messageAudio') {
    return '🎵 音乐';
  }
  if (type === 'messageLocation') {
    return '📍 位置';
  }
  if (type === 'messageVenue') {
    return '📍 地点';
  }
  if (type === 'messageContact') {
    return '👤 联系人';
  }
  if (type === 'messagePoll') {
    const poll = content['poll'] as TdObject | undefined;
    const q = poll !== undefined ? ((poll['question'] as TdObject | undefined)) : undefined;
    const qText = q !== undefined ? ((q['text'] as string | undefined) ?? '') : '';
    return qText !== '' ? `📊 ${qText}` : '📊 投票';
  }
  if (type === 'messageDice') {
    const e = content['emoji'] as string | undefined;
    return e !== undefined && e !== '' ? e : '🎲';
  }
  if (type === 'messageVideoNote') {
    return '📹 视频消息';
  }
  if (type === 'messageCall') {
    return '📞 通话';
  }
  if (type === 'messageStory') {
    return '📖 故事';
  }
  if (type === 'messageGame') {
    return '🎮 游戏';
  }
  if (type === 'messageInvoice') {
    return '🧾 账单';
  }
  if (type === 'messagePaidMedia') {
    return '🖼 付费内容';
  }
  const svc: string | undefined = SERVICE_LABELS[type];
  if (svc !== undefined) {
    return svc;
  }
  // Last resort: any embedded text/caption, else a generic label — never 'Message'.
  const embedded = embeddedText(content);
  if (embedded !== '') {
    return embedded;
  }
  return '[通知]';
}

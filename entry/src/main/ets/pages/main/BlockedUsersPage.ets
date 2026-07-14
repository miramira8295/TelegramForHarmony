import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const PAGE_LIMIT: number = 100;

interface BlockedRow {
  userId: number;   // >0 for a user
  chatId: number;   // >0 for a chat (channel) sender
  title: string;
  subtitle: string; // @username or 频道
  initials: string;
}

// 已屏蔽的用户: the main block list, with real unblocking
// (setMessageSenderBlockList with a null list).
@Entry
@Component
struct BlockedUsersPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State rows: BlockedRow[] = [];
  @State loading: boolean = true;

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    const req: TdRequest = { '@type': 'getBlockedMessageSenders' };
    req['block_list'] = { '@type': 'blockListMain' } as TdObject;
    req['offset'] = 0;
    req['limit'] = PAGE_LIMIT;
    getTdClient().send(req).then((res: TdObject) => {
      const senders = (res['senders'] as TdObject[] | undefined) ?? [];
      this.rows = senders.map((s: TdObject): BlockedRow => ({
        userId: (s['user_id'] as number | undefined) ?? 0,
        chatId: (s['chat_id'] as number | undefined) ?? 0,
        title: '', subtitle: '', initials: '?'
      }));
      this.loading = false;
      for (const r of this.rows) {
        if (r.userId > 0) {
          this.resolveUser(r.userId);
        } else if (r.chatId !== 0) {
          this.resolveChat(r.chatId);
        }
      }
    }).catch((e: TdError) => {
      console.error(`BlockedUsersPage.getBlockedMessageSenders failed: ${e.message}`);
      this.loading = false;
      promptAction.showToast({ message: '读取屏蔽名单失败', duration: 1500 });
    });
  }

  private patch(userId: number, chatId: number, title: string, subtitle: string): void {
    this.rows = this.rows.map((r: BlockedRow): BlockedRow =>
      (r.userId === userId && r.chatId === chatId)
        ? {
          userId: r.userId, chatId: r.chatId, title, subtitle,
          initials: title.length > 0 ? title.substring(0, 1).toUpperCase() : '?'
        }
        : r);
  }

  private resolveUser(userId: number): void {
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = userId;
    getTdClient().send(req).then((u: TdObject) => {
      const first = (u['first_name'] as string | undefined) ?? '';
      const last = (u['last_name'] as string | undefined) ?? '';
      const name = `${first}${last !== '' ? ' ' + last : ''}`.trim();
      const usernames = u['usernames'] as TdObject | undefined;
      const active = usernames !== undefined
        ? ((usernames['active_usernames'] as string[] | undefined) ?? []) : [];
      const phone = (u['phone_number'] as string | undefined) ?? '';
      const subtitle = active.length > 0 ? `@${active[0]}` : (phone !== '' ? `+${phone}` : '');
      this.patch(userId, 0, name !== '' ? name : '已删除账户', subtitle);
    }).catch((e: TdError) => {
      console.error(`BlockedUsersPage.getUser(${userId}) failed: ${e.message}`);
    });
  }

  private resolveChat(chatId: number): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    getTdClient().send(req).then((c: TdObject) => {
      this.patch(0, chatId, (c['title'] as string | undefined) ?? '', '频道');
    }).catch((e: TdError) => {
      console.error(`BlockedUsersPage.getChat(${chatId}) failed: ${e.message}`);
    });
  }

  private unblock(row: BlockedRow): void {
    const sender: TdObject = row.userId > 0
      ? { '@type': 'messageSenderUser', 'user_id': row.userId } as TdObject
      : { '@type': 'messageSenderChat', 'chat_id': row.chatId } as TdObject;
    const req: TdRequest = { '@type': 'setMessageSenderBlockList' };
    req['sender_id'] = sender;
    // block_list omitted = null = not blocked anywhere
    const before = this.rows;
    this.rows = this.rows.filter((r: BlockedRow) =>
      !(r.userId === row.userId && r.chatId === row.chatId));
    getTdClient().send(req).then(() => {
      promptAction.showToast({ message: `已解除屏蔽 ${row.title}`, duration: 1500 });
    }).catch((e: TdError) => {
      console.error(`BlockedUsersPage.setMessageSenderBlockList failed: ${e.message}`);
      this.rows = before;
      promptAction.showToast({ message: '解除屏蔽失败，请重试', duration: 1500 });
    });
  }

  private confirmUnblock(row: BlockedRow): void {
    promptAction.showDialog({
      title: '解除屏蔽',
      message: `确定要解除对 ${row.title} 的屏蔽吗？`,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '解除', color: COLOR_PRIMARY as string }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        this.unblock(row);
      }
    }).catch((e: Object) => {
      console.error(`BlockedUsersPage.showDialog failed: ${JSON.stringify(e)}`);
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('已屏蔽的用户').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  row(r: BlockedRow) {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: '', initials: r.initials,
        colorSeed: r.userId !== 0 ? r.userId : r.chatId, avatarSize: 44
      });
      Column({ space: 2 }) {
        Text(r.title !== '' ? r.title : '…').fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (r.subtitle !== '') {
          Text(r.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Text('解除').fontSize(15).fontColor(COLOR_PRIMARY)
        .onClick(() => { this.confirmUnblock(r); });
    }
    .width('100%').padding({ left: 14, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      this.header();
      if (this.loading) {
        Column() {
          LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.rows.length === 0) {
        Column({ space: 8 }) {
          Text('没有被屏蔽的用户').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text('被屏蔽的用户无法给你发消息。').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.rows, (r: BlockedRow, idx: number) => {
            ListItem() {
              Column() {
                if (idx > 0) {
                  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 70 });
                }
                this.row(r);
              }.width('100%');
            }
          }, (r: BlockedRow) => `b_${r.userId}_${r.chatId}_${r.title}`);
        }
        .layoutWeight(1).width('100%')
        .backgroundColor($r('app.color.surface'))
        .scrollBar(BarState.Off)
        .padding({ bottom: this.bottomSafe });
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}

import { router, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { ChatEntry } from '../../store/ChatEntry';
import { FolderInfo } from '../../store/FolderStore';
import {
  MUTE_OPTIONS, MuteOption, togglePin, setMute, markAsRead, markUnread,
  setArchived, setInFolder, clearHistory, leaveOrDeleteChat, leaveLabel
} from '../../store/ChatActions';
import { getChatStore, getFolderStore } from '../../tdkit/Globals';
import { CHAT_MENU_OPEN } from './ChatListFreeze';
import { AvatarView } from './AvatarView';
import { formatTime } from '../../util/formatTime';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_MUTED_BADGE, ROW_PAD_H, ROW_PAD_V } from '../../util/theme';

@Component
export struct ChatRow {
  @Prop chat: ChatEntry;
  @Prop nowSec: number;
  // The list this row is being shown in — pinning is per-list, and the menu
  // offers 取消归档 instead of 归档 inside the archive.
  @Prop listKey: string;

  private folders(): FolderInfo[] {
    return getFolderStore().getFolders();
  }

  private isPinned(): boolean {
    return getChatStore().isPinned(this.listKey, this.chat.id);
  }

  private isArchived(): boolean {
    return getChatStore().isArchived(this.chat.id);
  }

  // Unread by count OR by the manual flag — either state offers 标记为已读.
  private isUnread(): boolean {
    return this.chat.unreadCount > 0 || this.chat.isMarkedUnread;
  }

  private confirmClearHistory(): void {
    const isPrivate = this.chat.kind === 'private' || this.chat.kind === 'secret';
    const buttons: promptAction.Button[] = [{ text: '取消', color: COLOR_TEXT_SECONDARY as string }];
    buttons.push({ text: '清空', color: '#E64646' });
    if (isPrivate) {
      buttons.push({ text: '同时为对方清空', color: '#E64646' });
    }
    promptAction.showDialog({
      title: '清空聊天记录',
      message: `确定要清空与「${this.chat.title}」的聊天记录吗？此操作无法撤销。`,
      buttons: buttons
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        clearHistory(this.chat.id, false);
      } else if (res.index === 2) {
        clearHistory(this.chat.id, true);
      }
    }).catch(() => {}); // dismissed by tapping outside
  }

  private confirmLeave(): void {
    const label = leaveLabel(this.chat.kind);
    promptAction.showDialog({
      title: label,
      message: `确定要${label.substring(0, 2)}「${this.chat.title}」吗？`,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: label, color: '#E64646' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        leaveOrDeleteChat(this.chat.id, this.chat.kind);
      }
    }).catch(() => {});
  }

  @Builder
  muteSubMenu() {
    Menu() {
      ForEach(MUTE_OPTIONS, (opt: MuteOption) => {
        MenuItem({ content: opt.label })
          .onClick(() => { setMute(this.chat.id, opt.seconds); });
      }, (opt: MuteOption) => `${opt.seconds}`);
    }
  }

  @Builder
  folderSubMenu() {
    Menu() {
      if (this.folders().length === 0) {
        MenuItem({ content: '暂无文件夹' }).enabled(false);
      } else {
        ForEach(this.folders(), (f: FolderInfo) => {
          // Tapping a folder the chat already belongs to removes it again.
          MenuItem({
            content: getChatStore().isInFolder(f.id, this.chat.id) ? `${f.title}  ✓` : f.title
          })
            .onClick(() => {
              setInFolder(f.id, this.chat.id, !getChatStore().isInFolder(f.id, this.chat.id));
            });
        }, (f: FolderInfo) => `${f.id}_${f.title}`);
      }
    }
  }

  @Builder
  contextMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pin')),
        content: this.isPinned() ? '取消置顶' : '置顶'
      })
        .onClick(() => { togglePin(this.listKey, this.chat.id, !this.isPinned()); });

      if (this.chat.isMuted) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bell')),
          content: '取消静音'
        })
          .onClick(() => { setMute(this.chat.id, 0); });
      } else {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bell_slash')),
          content: '静音',
          builder: (): void => { this.muteSubMenu(); }
        });
      }

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
        content: this.isUnread() ? '标记为已读' : '标记为未读'
      })
        .onClick(() => {
          if (this.isUnread()) {
            markAsRead(this.chat.id, this.chat.lastMessageId);
          } else {
            markUnread(this.chat.id, true);
          }
        });

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.archivebox')),
        content: this.isArchived() ? '取消归档' : '归档'
      })
        .onClick(() => { setArchived(this.chat.id, !this.isArchived()); });

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.folder_badge_plus')),
        content: '添加到文件夹',
        builder: (): void => { this.folderSubMenu(); }
      });

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        content: '清空聊天记录'
      })
        .onClick(() => { this.confirmClearHistory(); });

      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.xmark_circle')).fontColor([Color.Red]),
        content: leaveLabel(this.chat.kind)
      })
        .onClick(() => { this.confirmLeave(); });
    }
  }

  build() {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: this.chat.avatarPath, initials: this.chat.initials, colorSeed: this.chat.id, autoDeleteTime: this.chat.autoDeleteTime });
      Column({ space: 4 }) {
        Row() {
          Text(this.chat.title)
            .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1);
          if (this.chat.isMuted) {
            SymbolGlyph($r('sys.symbol.bell_slash')).fontSize(13).fontColor([COLOR_TEXT_SECONDARY]).margin({ left: 4 }).flexShrink(0);
          }
        }.width('100%');
        Row() {
          if (this.chat.lastSenderName !== '') {
            Text(`${this.chat.lastSenderName}: `).fontSize(14).fontColor(COLOR_PRIMARY).maxLines(1);
          }
          Text(this.chat.lastMessageText)
            .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Column({ space: 6 }) {
        Text(formatTime(this.chat.lastMessageDate, this.nowSec))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        if (this.chat.unreadCount > 0) {
          Text(`${this.chat.unreadCount}`)
            .fontSize(12).fontColor(Color.White)
            .backgroundColor(this.chat.isMuted ? COLOR_MUTED_BADGE : COLOR_PRIMARY)
            .borderRadius(11).padding({ left: 7, right: 7, top: 2, bottom: 2 });
        } else if (this.chat.isMarkedUnread) {
          // Manually flagged unread — a plain dot, like the official clients.
          Circle({ width: 10, height: 10 })
            .fill(this.chat.isMuted ? COLOR_MUTED_BADGE : COLOR_PRIMARY);
        }
      }.alignItems(HorizontalAlign.End);
    }
    .width('100%').padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: ROW_PAD_V, bottom: ROW_PAD_V }).alignItems(VerticalAlign.Center)
    .onClick(() => {
      const params: Record<string, Object> = { 'chatId': this.chat.id };
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    })
    // While the menu is open the list must not rebuild: the ForEach key encodes
    // mutable fields, so an incoming message would re-create this row and take
    // the menu down with it. The flag freezes the list (see CHAT_MENU_OPEN).
    .bindContextMenu(this.contextMenu, ResponseType.LongPress, {
      onAppear: (): void => { AppStorage.setOrCreate(CHAT_MENU_OPEN, true); },
      onDisappear: (): void => { AppStorage.setOrCreate(CHAT_MENU_OPEN, false); }
    });
  }
}

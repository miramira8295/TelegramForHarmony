import { router } from '@kit.ArkUI';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const ARCHIVE_ROW_HEIGHT: number = 56;

@Preview
@Component
export struct MainTabBody {
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  @State chats: ChatEntry[] = [];
  @State nowSec: number = 0;
  @State showArchive: boolean = false;
  @State refreshing: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  private unsubscribe: (() => void) | null = null;
  private unsubArchive: (() => void) | null = null;
  private timerId: number = -1;

  private onMenuToggle(): void {
    if (this.menuOpen) {
      return;
    }
    const next = this.updateGate.flush();
    if (next !== null) {
      this.chats = next;
    }
  }

  aboutToAppear(): void {
    this.nowSec = Math.floor(Date.now() / 1000);
    const store = getChatStore();
    this.unsubscribe = store.subscribe((list: ChatEntry[]) => {
      const next = this.updateGate.accept(list);
      if (next !== null) {
        this.chats = next;
      }
    }, 'main');
    this.showArchive = store.hasArchive();
    // drive showArchive off the archive bucket itself (fires whenever it changes)
    this.unsubArchive = store.subscribe(() => { this.showArchive = getChatStore().hasArchive(); }, 'archive');
    store.load('main');
    store.load('archive');
    this.timerId = setInterval(() => { this.nowSec = Math.floor(Date.now() / 1000); }, 60000);
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
    if (this.unsubArchive !== null) { this.unsubArchive(); this.unsubArchive = null; }
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
  }

  private openArchive(): void {
    router.pushUrl({ url: 'pages/chatlist/ArchivePage' });
  }

  // Revealed only while the user over-scrolls (pulls down) at the top.
  @Builder
  archiveHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.archivebox')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY]).margin({ right: 12 });
      Text('Archived chats').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
    }
    .width('100%').height(ARCHIVE_ROW_HEIGHT).padding({ left: 14, right: 14 })
    .onClick(() => { this.openArchive(); });
  }

  @Builder
  chatList() {
    List() {
      ForEach(this.chats, (item: ChatEntry) => {
        ListItem() { ChatRow({ chat: item, nowSec: this.nowSec, listKey: 'main' }); }
      }, (item: ChatEntry, index: number) => `${item.id}_${index}_${item.unreadCount}_${item.isMuted}_${item.lastMessageDate}_${item.lastMessageText}_${item.lastSenderName}_${item.avatarPath}_${item.title}_${item.isMarkedUnread}`);
    }
    .layoutWeight(1).width('100%')
    .contentEndOffset(this.bottomSafe + 88)
    .onReachEnd(() => { getChatStore().loadMore('main'); });
  }

  build() {
    if (this.showArchive) {
      Refresh({ refreshing: $$this.refreshing, builder: this.archiveHeader() }) {
        this.chatList();
      }
      .layoutWeight(1).width('100%')
      .onRefreshing(() => {
        this.refreshing = false;
        this.openArchive();
      });
    } else {
      this.chatList();
    }
  }
}

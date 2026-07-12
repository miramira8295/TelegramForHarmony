import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { COLOR_TEXT_SECONDARY } from '../../util/theme';

@Component
export struct ChatListView {
  @Prop listKey: string;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State chats: ChatEntry[] = [];
  @State nowSec: number = 0;
  private unsubscribe: (() => void) | null = null;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.nowSec = Math.floor(Date.now() / 1000);
    const store = getChatStore();
    this.unsubscribe = store.subscribe((list: ChatEntry[]) => { this.chats = list; }, this.listKey);
    store.load(this.listKey);
    this.timerId = setInterval(() => { this.nowSec = Math.floor(Date.now() / 1000); }, 60000);
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    if (this.chats.length === 0) {
      Column() {
        Text('No chats yet').fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%');
    } else {
      List() {
        ForEach(this.chats, (item: ChatEntry) => {
          ListItem() {
            ChatRow({ chat: item, nowSec: this.nowSec });
          }
        }, (item: ChatEntry, index: number) => `${item.id}_${index}_${item.unreadCount}_${item.isMuted}_${item.lastMessageDate}_${item.lastMessageText}_${item.lastSenderName}_${item.avatarPath}_${item.title}`);
      }
      .layoutWeight(1).width('100%')
      .contentEndOffset(this.bottomSafe + 88)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onReachEnd(() => { getChatStore().loadMore(this.listKey); });
    }
  }
}

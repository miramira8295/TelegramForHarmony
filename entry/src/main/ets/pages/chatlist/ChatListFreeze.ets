import { ChatEntry } from '../../store/ChatEntry';

// AppStorage flag: true while a chat row's context menu is on screen.
//
// Chat list rows are keyed by their mutable content (unread count, last message,
// ...) because ForEach only re-renders a row when its key changes. That makes an
// incoming message re-create the row — and destroy the context menu bound to it.
// So while a menu is open the list holds its last rendering and buffers updates,
// applying the newest one as soon as the menu closes.
export const CHAT_MENU_OPEN: string = 'chatMenuOpen';

// Buffers chat-list updates for one list view. Not a store: purely a
// render-timing gate owned by the view.
export class ChatListFreeze {
  private pending: ChatEntry[] | null = null;

  // Returns the list to render now, or null to keep the current one.
  accept(list: ChatEntry[]): ChatEntry[] | null {
    if (AppStorage.get<boolean>(CHAT_MENU_OPEN) === true) {
      this.pending = list;
      return null;
    }
    this.pending = null;
    return list;
  }

  // Called when the menu closes: the newest buffered list, if any arrived.
  flush(): ChatEntry[] | null {
    const p = this.pending;
    this.pending = null;
    return p;
  }
}

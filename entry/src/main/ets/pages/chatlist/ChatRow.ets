import { router } from '@kit.ArkUI';
import { ChatEntry } from '../../store/ChatEntry';
import { AvatarView } from './AvatarView';
import { formatTime } from '../../util/formatTime';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_MUTED_BADGE, ROW_PAD_H, ROW_PAD_V } from '../../util/theme';

@Component
export struct ChatRow {
  @Prop chat: ChatEntry;
  @Prop nowSec: number;

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
        }
      }.alignItems(HorizontalAlign.End);
    }
    .width('100%').padding({ left: ROW_PAD_H, right: ROW_PAD_H, top: ROW_PAD_V, bottom: ROW_PAD_V }).alignItems(VerticalAlign.Center)
    .onClick(() => {
      const params: Record<string, Object> = { 'chatId': this.chat.id };
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    });
  }
}

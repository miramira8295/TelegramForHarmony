import { router } from '@kit.ArkUI';
import { ChatListView } from './ChatListView';
import { COLOR_TEXT_PRIMARY } from '../../util/theme';

@Entry
@Preview
@Component
struct ArchivePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY])
          .onClick(() => { router.back(); });
        Text('Archived chats').fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY).margin({ left: 12 });
      }.width('100%').padding({ left: 16, right: 16, top: this.topSafe + 12, bottom: 12 });
      ChatListView({ listKey: 'archive' });
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}

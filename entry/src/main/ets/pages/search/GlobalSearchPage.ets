import { router } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { formatPreview } from '../../util/formatPreview';
import { formatTime } from '../../util/formatTime';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

interface FoundItem {
  chatId: number;
  messageId: number;
  chatTitle: string;
  preview: string;
  date: number;
}

// Global message search (all chats) — entered from a hashtag tap or with any
// query. Rows open the source chat jumped to the message.
@Entry
@Component
struct GlobalSearchPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @State query: string = '';
  @State items: FoundItem[] = [];
  @State loading: boolean = false;
  @State nextOffset: string = '';
  @State searchedOnce: boolean = false;
  private nowSec: number = Math.floor(Date.now() / 1000);
  private seq: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    const q = params !== undefined ? (params['query'] as string | undefined) : undefined;
    if (q !== undefined && q !== '') {
      this.query = q;
      this.search('');
    }
  }

  private search(offset: string): void {
    const q = this.query.trim();
    if (q === '') {
      return;
    }
    const seq = ++this.seq;
    this.loading = offset === '';
    const req: TdRequest = { '@type': 'searchMessages' };
    req['chat_list'] = { '@type': 'chatListMain' } as TdObject;
    req['query'] = q;
    req['offset'] = offset;
    req['limit'] = 30;
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.seq) {
        return;
      }
      this.loading = false;
      this.searchedOnce = true;
      this.nextOffset = (res['next_offset'] as string | undefined) ?? '';
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const fresh: FoundItem[] = [];
      for (const m of msgs) {
        const chatId = (m['chat_id'] as number | undefined) ?? 0;
        const messageId = (m['id'] as number | undefined) ?? 0;
        if (chatId === 0 || messageId === 0) {
          continue;
        }
        const item: FoundItem = {
          chatId,
          messageId,
          chatTitle: '',
          preview: formatPreview(m),
          date: (m['date'] as number | undefined) ?? 0
        };
        fresh.push(item);
        this.resolveTitle(chatId);
      }
      this.items = offset === '' ? fresh : [...this.items, ...fresh];
    }).catch((e: TdError) => {
      this.loading = false;
      this.searchedOnce = true;
      console.error(`GlobalSearchPage.searchMessages failed: ${e.message}`);
    });
  }

  private titles: Map<number, string> = new Map();

  private resolveTitle(chatId: number): void {
    if (this.titles.has(chatId)) {
      return;
    }
    this.titles.set(chatId, '');
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    getTdClient().send(req).then((chat: TdObject) => {
      const title = (chat['title'] as string | undefined) ?? '';
      this.titles.set(chatId, title);
      this.items = this.items.map((it: FoundItem): FoundItem =>
        it.chatId === chatId
          ? { chatId: it.chatId, messageId: it.messageId, chatTitle: title, preview: it.preview, date: it.date }
          : it);
    }).catch((e: TdError) => {
      console.error(`GlobalSearchPage.getChat failed: ${e.message}`);
    });
  }

  private openResult(it: FoundItem): void {
    const params: Record<string, Object> = { 'chatId': it.chatId, 'jumpTo': it.messageId };
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(40).height(40).borderRadius(20).backgroundColor(Color.White)
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
        .onClick(() => { router.back(); });
        TextInput({ text: this.query, placeholder: '全局搜索' })
          .layoutWeight(1).height(40)
          .backgroundColor(Color.White).borderRadius(20)
          .onChange((v: string) => { this.query = v; })
          .onSubmit(() => { this.search(''); });
      }
      .width('100%').padding({ left: 12, right: 12, top: this.topSafe + 10, bottom: 10 })
      .alignItems(VerticalAlign.Center);

      if (this.loading) {
        Column() {
          LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.items.length === 0 && this.searchedOnce) {
        Column() {
          Text('未找到相关消息').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.items, (it: FoundItem) => {
            ListItem() {
              Column({ space: 3 }) {
                Row() {
                  Text(it.chatTitle !== '' ? it.chatTitle : '...')
                    .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1);
                  Text(formatTime(it.date, this.nowSec)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
                }.width('100%');
                Text(it.preview).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .backgroundColor(Color.White)
              .onClick(() => { this.openResult(it); });
            }
          }, (it: FoundItem) => `${it.chatId}_${it.messageId}_${it.chatTitle}`);
          if (this.nextOffset !== '') {
            ListItem() {
              Text('加载更多').fontSize(14).fontColor(COLOR_PRIMARY)
                .width('100%').textAlign(TextAlign.Center)
                .padding(12)
                .onClick(() => { this.search(this.nextOffset); });
            }
          }
        }
        .layoutWeight(1).width('100%')
        .divider({ strokeWidth: 0.7, color: '#EDEDED', startMargin: 14, endMargin: 14 });
      }
    }
    .width('100%').height('100%')
    .backgroundColor('#EFEFF4')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}

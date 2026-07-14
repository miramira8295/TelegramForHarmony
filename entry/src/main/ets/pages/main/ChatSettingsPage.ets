import { router } from '@kit.ArkUI';
import {
  KEY_TEXT_SIZE, KEY_BUBBLE_RADIUS, KEY_THREE_LINES, KEY_NIGHT_MODE, KEY_REDUCE_ANIM, KEY_SEND_BY_ENTER,
  TEXT_SIZE_MIN, TEXT_SIZE_MAX, RADIUS_MIN, RADIUS_MAX,
  NIGHT_SYSTEM, NIGHT_DARK, NIGHT_LIGHT,
  setNumber, setBoolean, setNightMode
} from '../../store/AppSettings';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT
} from '../../util/theme';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;

interface NightOption {
  label: string;
  value: string;
}

const NIGHT_OPTIONS: NightOption[] = [
  { label: '跟随系统', value: NIGHT_SYSTEM },
  { label: '始终开启', value: NIGHT_DARK },
  { label: '始终关闭', value: NIGHT_LIGHT }
];

// 聊天设置. Deliberately limited to settings the app actually honours — the
// official page also offers wallpapers, colour themes and app icons, which need
// capabilities we don't have yet, and a switch that changes nothing is worse
// than no switch at all.
@Entry
@Component
struct ChatSettingsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_TEXT_SIZE) textSize: number = 16;
  @StorageLink(KEY_BUBBLE_RADIUS) bubbleRadius: number = 17;
  @StorageLink(KEY_THREE_LINES) threeLines: boolean = false;
  @StorageLink(KEY_NIGHT_MODE) nightMode: string = NIGHT_SYSTEM;
  @StorageLink(KEY_REDUCE_ANIM) reduceAnim: boolean = false;
  @StorageLink(KEY_SEND_BY_ENTER) sendByEnter: boolean = false;

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('聊天设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  cardTitle(text: string) {
    Text(text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 });
  }

  // Live sample of what the sliders above do — same colours, size and radius as
  // a real bubble.
  @Builder
  preview() {
    Column({ space: 8 }) {
      Row() {
        Text('早上好！现在几点了？')
          .fontSize(this.textSize).fontColor(COLOR_TEXT_PRIMARY)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(COLOR_BUBBLE_IN)
          .borderRadius(this.bubbleRadius);
      }.width('100%').justifyContent(FlexAlign.Start);
      Row() {
        Text('东京现在是早上 😄')
          .fontSize(this.textSize).fontColor(COLOR_TEXT_PRIMARY)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(COLOR_BUBBLE_OUT)
          .borderRadius(this.bubbleRadius);
      }.width('100%').justifyContent(FlexAlign.End);
    }
    .width('100%').padding(14);
  }

  @Builder
  sliderRow(title: string, value: number, min: number, max: number, onSet: (v: number) => void) {
    Column() {
      this.cardTitle(title);
      Row({ space: 12 }) {
        Slider({ value: value, min: min, max: max, step: 1 })
          .layoutWeight(1)
          .trackColor($r('app.color.divider')).selectedColor(COLOR_PRIMARY).blockColor(COLOR_PRIMARY)
          .onChange((v: number) => { onSet(Math.round(v)); });
        Text(`${value}`).fontSize(15).fontColor(COLOR_PRIMARY).width(28).textAlign(TextAlign.End);
      }.width('100%').padding({ left: 16, right: 16, bottom: 6 });
    }.width('100%');
  }

  @Builder
  toggleRow(title: string, subtitle: string, on: boolean, onSet: (v: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        if (subtitle !== '') {
          Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(COLOR_PRIMARY)
        .onChange((v: boolean) => { onSet(v); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center);
  }

  // Chat-list row density: two lines (name + preview) or three (adds a second
  // preview line).
  @Builder
  chatListView() {
    Column() {
      this.cardTitle('聊天列表视图');
      Row({ space: 12 }) {
        this.densityOption('两行', false);
        this.densityOption('三行', true);
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 12 });
    }.width('100%');
  }

  @Builder
  densityOption(label: string, isThree: boolean) {
    Column({ space: 8 }) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Circle({ width: 22, height: 22 }).fill($r('app.color.divider'));
          Column({ space: 3 }) {
            Row().width('70%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            Row().width('90%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            if (isThree) {
              Row().width('80%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            }
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }.width('100%').alignItems(VerticalAlign.Center);
      }
      .width('100%').padding(10)
      .borderRadius(10)
      .border({ width: this.threeLines === isThree ? 2 : 1,
        color: this.threeLines === isThree ? COLOR_PRIMARY : $r('app.color.divider') });
      Text(label).fontSize(13)
        .fontColor(this.threeLines === isThree ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
    }
    .layoutWeight(1)
    .onClick(() => { setBoolean(KEY_THREE_LINES, isThree); });
  }

  @Builder
  nightModeCard() {
    Column() {
      this.cardTitle('夜间模式');
      ForEach(NIGHT_OPTIONS, (opt: NightOption, idx: number) => {
        if (idx > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
        }
        Row() {
          Text(opt.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          if (this.nightMode === opt.value) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
          }
        }
        .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
        .onClick(() => { setNightMode(opt.value); });
      }, (opt: NightOption) => opt.value);
    }.width('100%');
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          // 字号 + 圆角, with the preview they drive.
          Column() {
            this.sliderRow('消息字号', this.textSize, TEXT_SIZE_MIN, TEXT_SIZE_MAX,
              (v: number): void => { setNumber(KEY_TEXT_SIZE, v); });
            this.preview();
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
            this.sliderRow('消息圆角', this.bubbleRadius, RADIUS_MIN, RADIUS_MAX,
              (v: number): void => { setNumber(KEY_BUBBLE_RADIUS, v); });
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          Column() {
            this.chatListView();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          Column() {
            this.nightModeCard();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });

          Column() {
            this.toggleRow('减弱动态效果', '不再自动播放动画贴纸与表情，省电', this.reduceAnim,
              (v: boolean): void => { setBoolean(KEY_REDUCE_ANIM, v); });
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
            this.toggleRow('回车键发送', '开启后回车直接发送，换行用输入法的换行键', this.sendByEnter,
              (v: boolean): void => { setBoolean(KEY_SEND_BY_ENTER, v); });
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .padding({ top: 4, bottom: 4 });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}

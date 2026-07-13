import { getTdClient } from '../../tdkit/Globals';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');

interface SettingItem {
  icon: string;
  bg: string;
  title: string;
  subtitle: string;
}

const SETTINGS: SettingItem[] = [
  { icon: 'sys.symbol.person_fill', bg: '#3478F6', title: '账号', subtitle: '电话、用户名与简介' },
  { icon: 'sys.symbol.message_fill', bg: '#FF9500', title: '聊天设置', subtitle: '壁纸、夜间模式与动画效果' },
  { icon: 'sys.symbol.lock_fill', bg: '#34C759', title: '隐私与安全', subtitle: '最后上线时间、登录设备、通行密钥' },
  { icon: 'sys.symbol.bell_fill', bg: '#FF3B30', title: '通知', subtitle: '声音、通话、标记' },
  { icon: 'sys.symbol.data_proportion', bg: '#007AFF', title: '数据与存储', subtitle: '媒体下载设置' },
  { icon: 'sys.symbol.folder_fill', bg: '#34AADC', title: '聊天文件夹', subtitle: '将聊天分类到文件夹中' },
  { icon: 'sys.symbol.computer', bg: '#5AC8FA', title: '设备', subtitle: '管理已连接的设备' },
  { icon: 'sys.symbol.battery_100percent', bg: '#FF9500', title: '省电', subtitle: '低电量时降低功耗' }
];

// The settings tab: user header (avatar with camera badge, name, phone·username)
// followed by the grouped list of setting entries.
@Preview
@Component
export struct SettingsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State myId: number = 0;
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State avatarAnimPath: string = '';
  @State statusEmojiPath: string = '';
  @State statusEmojiFormat: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req).then((me: TdObject) => {
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsub = store.subscribe(() => { this.refresh(); });
      store.open();
    }).catch((e: TdError) => {
      console.error(`SettingsPage.getMe failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    this.name = s.name;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.avatarAnimPath = s.avatarAnimPath;
    this.statusEmojiPath = s.statusEmojiPath;
    this.statusEmojiFormat = s.statusEmojiFormat;
    this.phone = s.phone;
    this.usernames = s.usernames;
  }

  private subtitleLine(): string {
    const parts: string[] = [];
    if (this.phone !== '') {
      parts.push(`+${this.phone}`);
    }
    if (this.usernames.length > 0) {
      parts.push(`@${this.usernames[0]}`);
    }
    return parts.join('  ·  ');
  }

  @Builder
  topBar() {
    Row() {
      Blank().layoutWeight(1);
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY]).margin({ right: 20 });
      SymbolGlyph($r('sys.symbol.more')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').height(44).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  userHeader() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        AvatarView({
          avatarPath: this.avatarPath, initials: this.initials,
          colorSeed: this.myId, avatarSize: 96,
          animPath: this.avatarAnimPath
        });
        Row() {
          SymbolGlyph($r('sys.symbol.camera')).fontSize(15).fontColor([Color.White]);
        }
        .width(30).height(30).borderRadius(15)
        .backgroundColor(COLOR_PRIMARY)
        .border({ width: 2.5, color: PAGE_BG })
        .justifyContent(FlexAlign.Center);
      }
      Row({ space: 5 }) {
        Text(this.name)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1);
        if (this.statusEmojiPath !== '') {
          if (this.statusEmojiFormat === 'tgs') {
            TgsStickerView({ tgsPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24 });
          } else if (this.statusEmojiFormat === 'webm') {
            WebmStickerView({ webmPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24 });
          } else {
            Image(`file://${this.statusEmojiPath}`).width(24).height(24).objectFit(ImageFit.Contain);
          }
        }
      }
      .alignItems(VerticalAlign.Center)
      .constraintSize({ maxWidth: '86%' });
      Text(this.subtitleLine()).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .padding({ top: 8, bottom: 14 });
  }

  @Builder
  settingRow(item: SettingItem) {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph($r(item.icon)).fontSize(18).fontColor([Color.White]);
      }
      .width(29).height(29).borderRadius(7).backgroundColor(item.bg);
      Column({ space: 2 }) {
        Text(item.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text(item.subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 14, right: 14, top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  settingsCard() {
    Column() {
      Column() {
        ForEach(SETTINGS, (item: SettingItem, index: number) => {
          if (index > 0) {
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 57 });
          }
          this.settingRow(item);
        }, (item: SettingItem) => item.title);
      }
      .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .padding({ top: 4, bottom: 4 });
    }
    .margin({ left: 12, right: 12 });
  }

  build() {
    Column() {
      this.topBar();
      Scroll() {
        Column() {
          this.userHeader();
          this.settingsCard();
        }
        .width('100%')
        .padding({ bottom: this.bottomSafe + 88 });
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG)
    .padding({ top: this.topSafe });
  }
}

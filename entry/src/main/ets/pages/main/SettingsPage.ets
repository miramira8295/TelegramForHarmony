import { router, promptAction } from '@kit.ArkUI';
import {
  addTdAccount, getActiveTdAccountSlot, getTdAccounts, getTdClient,
  logoutCurrentTdAccount, removeDuplicateTdAccountsForActive,
  switchTdAccount, updateActiveTdAccountProfile
} from '../../tdkit/Globals';
import { TdAccountSummary } from '../../tdkit/AccountRegistry';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { floatingLiveWindow } from '../chat/LiveFloatingWindow';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');

interface SettingItem {
  icon: string;
  bg: string;
  title: string;
  subtitle: string;
  page: string; // route to open ('' = not implemented yet)
}

// 账号 opens the same editor as 个人资料 → 编辑信息 (name, bio, username,
// birthday) — one page, two entry points, as in the official clients.
const SETTINGS: SettingItem[] = [
  { icon: 'sys.symbol.person_fill', bg: '#3478F6', title: '账号', subtitle: '电话、用户名与简介',
    page: 'pages/main/AccountEditPage' },
  { icon: 'sys.symbol.message_fill', bg: '#FF9500', title: '聊天设置', subtitle: '字号、圆角、夜间模式与动画效果',
    page: 'pages/main/ChatSettingsPage' },
  { icon: 'sys.symbol.lock_fill', bg: '#34C759', title: '隐私与安全', subtitle: '最后上线时间、屏蔽名单、登录设备',
    page: 'pages/main/PrivacySecurityPage' },
  { icon: 'sys.symbol.data_proportion', bg: '#007AFF', title: '数据与存储', subtitle: '存储占用、流量与代理',
    page: 'pages/main/DataStoragePage' },
  { icon: 'sys.symbol.folder_fill', bg: '#34AADC', title: '聊天文件夹', subtitle: '将聊天分类到文件夹中',
    page: 'pages/main/ChatFoldersPage' },
  { icon: 'sys.symbol.computer', bg: '#5AC8FA', title: '设备', subtitle: '管理已连接的设备',
    page: 'pages/main/ActiveSessionsPage' },
  { icon: 'sys.symbol.battery_100percent', bg: '#FF9500', title: '省电', subtitle: '低电量时降低功耗',
    page: 'pages/main/PowerUsagePage' }
];

// The settings tab: user header (avatar with camera badge, name, phone·username)
// followed by the grouped list of setting entries.
@Preview
@Component
export struct SettingsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink('tdAccountRegistryEpoch') @Watch('onAccountRegistryEpoch')
  accountRegistryEpoch: number = 0;
  @State myId: number = 0;
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State avatarAnimPath: string = '';
  @State statusEmojiPath: string = '';
  @State statusEmojiFormat: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State accounts: TdAccountSummary[] = [];
  @State activeSlotId: string = '';
  @State switchingSlotId: string = '';
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    this.reloadAccounts();
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
    updateActiveTdAccountProfile(
      this.myId,
      this.name,
      this.phone,
      this.usernames.length > 0 ? this.usernames[0] : '',
      this.avatarPath
    );
  }

  private onAccountRegistryEpoch(): void {
    this.reloadAccounts();
  }

  private reloadAccounts(): void {
    removeDuplicateTdAccountsForActive();
    this.accounts = getTdAccounts();
    this.activeSlotId = getActiveTdAccountSlot();
  }

  private accountInitials(account: TdAccountSummary): string {
    const trimmed = account.name.trim();
    if (trimmed === '') { return '?'; }
    const parts = trimmed.split(' ').filter((part: string): boolean => part !== '');
    if (parts.length >= 2) {
      return `${parts[0].substring(0, 1)}${parts[parts.length - 1].substring(0, 1)}`.toUpperCase();
    }
    return trimmed.substring(0, Math.min(2, trimmed.length)).toUpperCase();
  }

  private accountSubtitle(account: TdAccountSummary): string {
    if (account.pendingLogin) { return '点击继续登录'; }
    const parts: string[] = [];
    if (account.phone !== '') { parts.push(`+${account.phone}`); }
    if (account.username !== '') { parts.push(`@${account.username}`); }
    return parts.length > 0 ? parts.join('  ·  ') : 'Telegram 账号';
  }

  private switchAccount(slotId: string): void {
    if (this.switchingSlotId !== '' || slotId === this.activeSlotId) { return; }
    this.switchingSlotId = slotId;
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => switchTdAccount(slotId))
      .catch((caught: Error): void => {
        console.error(`SettingsPage.switchAccount failed: ${caught.message}`);
        promptAction.showToast({ message: '账号切换失败，请重试', duration: 1800 });
        this.switchingSlotId = '';
      });
  }

  private addAccount(): void {
    if (this.switchingSlotId !== '') { return; }
    this.switchingSlotId = 'new';
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => addTdAccount())
      .catch((caught: Error): void => {
        console.error(`SettingsPage.addAccount failed: ${caught.message}`);
        promptAction.showToast({ message: '暂时无法添加账号，请重试', duration: 1800 });
        this.switchingSlotId = '';
      });
  }

  private showMoreMenu(): void {
    if (this.switchingSlotId !== '') { return; }
    promptAction.showActionMenu({
      title: '设置',
      buttons: [
        { text: '退出登录', color: '#FF3B30' }
      ]
    }).then((result): void => {
      if (result.index === 0) { this.confirmLogout(); }
    }).catch((): void => {});
  }

  private confirmLogout(): void {
    const hasAnotherAccount = this.accounts.some(
      (account: TdAccountSummary): boolean =>
        account.slotId !== this.activeSlotId && !account.pendingLogin && account.userId !== 0
    );
    promptAction.showDialog({
      title: '退出登录',
      message: hasAnotherAccount
        ? '确定退出当前账号吗？退出后将自动切换到另一个账号。'
        : '确定退出当前账号吗？退出后需要重新登录。',
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '退出', color: '#FF3B30' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) { this.performLogout(); }
    }).catch((): void => {});
  }

  private performLogout(): void {
    if (this.switchingSlotId !== '') { return; }
    this.switchingSlotId = 'logout';
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => logoutCurrentTdAccount())
      .catch((caught: Error): void => {
        console.error(`SettingsPage.logout failed: ${caught.message}`);
        promptAction.showToast({ message: '退出登录失败，请重试', duration: 1800 });
        this.switchingSlotId = '';
      });
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
      Stack({ alignContent: Alignment.Center }) {
        if (this.switchingSlotId === 'logout') {
          LoadingProgress().width(21).height(21).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.more')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY]);
        }
      }
      .width(34).height(34)
      .enabled(this.switchingSlotId === '')
      .onClick((): void => this.showMoreMenu());
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
            TgsStickerView({
              tgsPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24, powerCategory: 'emojiStatus'
            });
          } else if (this.statusEmojiFormat === 'webm') {
            WebmStickerView({
              webmPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24, powerCategory: 'emojiStatus'
            });
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
  accountRow(account: TdAccountSummary) {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: account.avatarPath,
        initials: this.accountInitials(account),
        colorSeed: account.userId !== 0 ? account.userId : account.slotId.length,
        avatarSize: 40
      });
      Column({ space: 2 }) {
        Text(account.name !== '' ? account.name : 'Telegram 账号')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.accountSubtitle(account))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      if (this.switchingSlotId === account.slotId) {
        LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .enabled(this.switchingSlotId === '')
    .onClick((): void => this.switchAccount(account.slotId));
  }

  @Builder
  accountsCard() {
    Column() {
      Column() {
        Text('账号')
          .width('100%')
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#4CB5E8')
          .padding({ left: 14, right: 14, top: 12, bottom: 5 });
        ForEach(this.accounts, (account: TdAccountSummary) => {
          if (account.slotId !== this.activeSlotId && !account.pendingLogin) {
            this.accountRow(account);
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 66 });
          }
        }, (account: TdAccountSummary): string => account.slotId);
        Row({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(19).fontColor([Color.White]);
          }
          .width(40).height(40).borderRadius(20).backgroundColor(COLOR_PRIMARY);
          Column({ space: 2 }) {
            Text('添加账号').fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
            Text('登录另一个 Telegram 账号').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
          if (this.switchingSlotId === 'new') {
            LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
          } else {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 12 })
        .alignItems(VerticalAlign.Center)
        .enabled(this.switchingSlotId === '')
        .onClick((): void => this.addAccount());
      }
      .width('100%')
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS);
    }
    .margin({ left: 12, right: 12, bottom: 10 });
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
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (item.page !== '') {
        router.pushUrl({ url: item.page });
      } else {
        promptAction.showToast({ message: `${item.title}暂未支持`, duration: 1500 });
      }
    });
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
          this.accountsCard();
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

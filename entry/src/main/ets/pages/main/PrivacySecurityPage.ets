import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  PrivacyValue, ruleLabel, getPrivacy,
  hasPassword, getAutoDeleteSeconds, setAutoDeleteSeconds,
  getBlockedCount, getSessionCount, getAccountTtlDays, setAccountTtlDays,
  getBoolOption, setBoolOption
} from '../../store/PrivacyApi';
import { PrivacyRuleParams } from './PrivacyRulePage';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_RADIUS: number = 14;

// TDLib option names.
const OPT_ARCHIVE_UNKNOWN: string = 'archive_and_mute_new_chats_from_unknown_users';
const OPT_DISABLE_TOP_CHATS: string = 'disable_top_chats';

interface Choice {
  label: string;
  value: number;
}

const AUTO_DELETE: Choice[] = [
  { label: '关闭', value: 0 },
  { label: '1 天', value: 86400 },
  { label: '1 周', value: 604800 },
  { label: '1 个月', value: 2678400 }
];

const ACCOUNT_TTL: Choice[] = [
  { label: '1 个月', value: 30 },
  { label: '3 个月', value: 90 },
  { label: '6 个月', value: 180 },
  { label: '12 个月', value: 365 },
  { label: '18 个月', value: 548 },
  { label: '24 个月', value: 730 }
];

// One privacy rule row: the TDLib setting it edits and the copy around it.
interface RuleRow {
  setting: string;
  title: string;
  hint: string;
}

const RULE_ROWS: RuleRow[] = [
  { setting: 'userPrivacySettingShowPhoneNumber', title: '手机号码',
    hint: '选择谁可以看到你的手机号码。' },
  { setting: 'userPrivacySettingShowStatus', title: '最后上线时间',
    hint: '看不到你上线时间的人，你也看不到他们的。' },
  { setting: 'userPrivacySettingShowProfilePhoto', title: '头像',
    hint: '选择谁可以看到你的头像。' },
  { setting: 'userPrivacySettingShowLinkInForwardedMessages', title: '转发的消息',
    hint: '你的消息被转发时，选择谁的转发标题里可以带上你的账号链接。' },
  { setting: 'userPrivacySettingAllowCalls', title: '语音通话',
    hint: '选择谁可以给你打电话。' },
  { setting: 'userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages', title: '语音消息',
    hint: '选择谁可以给你发语音和视频消息。' },
  { setting: 'userPrivacySettingShowBio', title: '简介',
    hint: '选择谁可以看到你的简介。' },
  { setting: 'userPrivacySettingShowBirthdate', title: '出生日期',
    hint: '选择谁可以看到你的出生日期。' },
  { setting: 'userPrivacySettingAllowChatInvites', title: '邀请',
    hint: '选择谁可以把你拉进群组和频道。' },
  { setting: 'userPrivacySettingAllowFindingByPhoneNumber', title: '通过手机号找到我',
    hint: '选择谁可以通过手机号搜索到你。' }
];

// 隐私与安全. Every row here maps to a TDLib call that actually changes account
// state. Two-step verification, the local passcode and passkeys need flows we
// don't have yet, so 两步验证 is shown read-only rather than faked.
@Entry
@Component
struct PrivacySecurityPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State passwordOn: boolean = false;
  @State autoDelete: number = 0;
  @State blocked: number = 0;
  @State sessions: number = 0;
  @State accountTtl: number = 0;
  @State archiveUnknown: boolean = false;
  @State suggestFrequent: boolean = true;
  @State rules: Map<string, string> = new Map(); // setting → display label

  aboutToAppear(): void {
    this.load();
  }

  // The page is re-entered after every sub-page edit, so reload on show.
  onPageShow(): void {
    this.load();
  }

  private load(): void {
    hasPassword().then((v: boolean) => { this.passwordOn = v; })
      .catch((e: TdError) => { console.error(`PrivacySecurityPage.hasPassword: ${e.message}`); });
    getAutoDeleteSeconds().then((v: number) => { this.autoDelete = v; })
      .catch((e: TdError) => { console.error(`PrivacySecurityPage.autoDelete: ${e.message}`); });
    getBlockedCount().then((v: number) => { this.blocked = v; })
      .catch((e: TdError) => { console.error(`PrivacySecurityPage.blocked: ${e.message}`); });
    getSessionCount().then((v: number) => { this.sessions = v; })
      .catch((e: TdError) => { console.error(`PrivacySecurityPage.sessions: ${e.message}`); });
    getAccountTtlDays().then((v: number) => { this.accountTtl = v; })
      .catch((e: TdError) => { console.error(`PrivacySecurityPage.accountTtl: ${e.message}`); });
    getBoolOption(OPT_ARCHIVE_UNKNOWN).then((v: boolean) => { this.archiveUnknown = v; });
    getBoolOption(OPT_DISABLE_TOP_CHATS).then((v: boolean) => { this.suggestFrequent = !v; });
    for (const r of RULE_ROWS) {
      getPrivacy(r.setting).then((v: PrivacyValue) => {
        const next: Map<string, string> = new Map(this.rules);
        next.set(r.setting, ruleLabel(v));
        this.rules = next; // new map — @State only re-renders on assignment
      }).catch((e: TdError) => {
        console.error(`PrivacySecurityPage.getPrivacy(${r.setting}) failed: ${e.message}`);
      });
    }
  }

  private autoDeleteLabel(): string {
    for (const c of AUTO_DELETE) {
      if (c.value === this.autoDelete) {
        return c.label;
      }
    }
    return `${Math.round(this.autoDelete / 86400)} 天`;
  }

  private accountTtlLabel(): string {
    if (this.accountTtl === 0) {
      return '';
    }
    for (const c of ACCOUNT_TTL) {
      if (c.value === this.accountTtl) {
        return c.label;
      }
    }
    return `${this.accountTtl} 天`;
  }

  private applyAutoDelete(seconds: number): void {
    const previous = this.autoDelete;
    this.autoDelete = seconds;
    setAutoDeleteSeconds(seconds).catch((e: TdError) => {
      console.error(`PrivacySecurityPage.setAutoDelete failed: ${e.message}`);
      this.autoDelete = previous;
      promptAction.showToast({ message: '保存失败，请重试', duration: 1500 });
    });
  }

  private applyAccountTtl(days: number): void {
    const previous = this.accountTtl;
    this.accountTtl = days;
    setAccountTtlDays(days).catch((e: TdError) => {
      console.error(`PrivacySecurityPage.setAccountTtl failed: ${e.message}`);
      this.accountTtl = previous;
      promptAction.showToast({ message: '保存失败，请重试', duration: 1500 });
    });
  }

  private applyOption(name: string, value: boolean): void {
    setBoolOption(name, value).catch((e: TdError) => {
      console.error(`PrivacySecurityPage.setOption(${name}) failed: ${e.message}`);
      promptAction.showToast({ message: '保存失败，请重试', duration: 1500 });
      this.load(); // put the toggle back where the server says it is
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('隐私与安全').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  cardTitle(text: string) {
    Text(text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 6 });
  }

  @Builder
  footnote(text: string) {
    Text(text).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, right: 16, top: 6 });
  }

  // Every row below reads its value from `this` inside a no-parameter builder.
  // A @Builder's *value* parameters are captured on first render and never
  // re-evaluated when @State changes, so a parameterised row would be frozen at
  // its loading-time value (0 blocked users, '…' for every rule) forever.
  @Builder
  passwordRow() {
    Row({ space: 10 }) {
      Text('两步验证').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Text(this.passwordOn ? '已开启' : '未开启').fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { promptAction.showToast({ message: '两步验证暂未支持', duration: 1500 }); });
  }

  @Builder
  blockedRow() {
    Row({ space: 10 }) {
      Text('已屏蔽的用户').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Text(`${this.blocked}`).fontSize(15).fontColor(COLOR_PRIMARY);
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { router.pushUrl({ url: 'pages/main/BlockedUsersPage' }); });
  }

  @Builder
  sessionsRow() {
    Row({ space: 10 }) {
      Text('活跃会话').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Text(`${this.sessions}`).fontSize(15).fontColor(COLOR_PRIMARY);
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { router.pushUrl({ url: 'pages/main/ActiveSessionsPage' }); });
  }


  @Builder
  toggleRow(title: string, on: boolean, onSet: (v: boolean) => void) {
    Row({ space: 12 }) {
      Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(COLOR_PRIMARY)
        .onChange((v: boolean) => { onSet(v); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  autoDeleteMenu() {
    Menu() {
      ForEach(AUTO_DELETE, (c: Choice) => {
        MenuItem({ content: c.label })
          .selected(this.autoDelete === c.value)
          .onClick(() => { this.applyAutoDelete(c.value); });
      }, (c: Choice) => `ad_${c.value}`);
    }
  }

  @Builder
  accountTtlMenu() {
    Menu() {
      ForEach(ACCOUNT_TTL, (c: Choice) => {
        MenuItem({ content: c.label })
          .selected(this.accountTtl === c.value)
          .onClick(() => { this.applyAccountTtl(c.value); });
      }, (c: Choice) => `ttl_${c.value}`);
    }
  }

  @Builder
  securityCard() {
    Column() {
      this.cardTitle('安全');
      this.passwordRow();
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      // Bound as a menu: the choices are few and fixed, like the mute submenu.
      Row({ space: 10 }) {
        Text('自动删除消息').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(this.autoDeleteLabel()).fontSize(15).fontColor(COLOR_PRIMARY);
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .bindMenu(this.autoDeleteMenu());
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      this.blockedRow();
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      this.sessionsRow();
    }
    .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
    .padding({ bottom: 4 });
  }

  @Builder
  privacyCard() {
    Column() {
      this.cardTitle('隐私');
      ForEach(RULE_ROWS, (r: RuleRow, idx: number) => {
        if (idx > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
        }
        // Inline, not a @Builder: the label has to track `this.rules` as each
        // getUserPrivacySettingRules lands.
        Row({ space: 10 }) {
          Text(r.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          Text(this.rules.get(r.setting) ?? '…').fontSize(15).fontColor(COLOR_PRIMARY);
        }
        .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          const params: PrivacyRuleParams = { setting: r.setting, title: r.title, hint: r.hint };
          router.pushUrl({ url: 'pages/main/PrivacyRulePage', params });
        });
      }, (r: RuleRow) => `${r.setting}_${this.rules.get(r.setting) ?? ''}`);
    }
    .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
    .padding({ bottom: 4 });
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          this.securityCard();
          this.privacyCard();

          Column() {
            this.cardTitle('来自未知用户的新聊天');
            this.toggleRow('归档并静音', this.archiveUnknown, (v: boolean): void => {
              this.archiveUnknown = v;
              this.applyOption(OPT_ARCHIVE_UNKNOWN, v);
            });
          }
          .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
          .padding({ bottom: 6 });
          this.footnote('自动归档并静音来自非联系人的新聊天、群组和频道。');

          Column() {
            this.cardTitle('删除我的账号');
            Row({ space: 10 }) {
              Text('如果我长期未登录').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
              Text(this.accountTtlLabel()).fontSize(15).fontColor(COLOR_PRIMARY);
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .alignItems(VerticalAlign.Center)
            .bindMenu(this.accountTtlMenu());
          }
          .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
          .padding({ bottom: 4 });
          this.footnote('如果你在此期间内未曾登录，你的账号连同全部消息记录和联系人都会被删除。');

          Column() {
            this.cardTitle('联系人');
            this.toggleRow('推荐常用联系人', this.suggestFrequent, (v: boolean): void => {
              this.suggestFrequent = v;
              this.applyOption(OPT_DISABLE_TOP_CHATS, !v);
            });
          }
          .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
          .padding({ bottom: 6 });
          this.footnote('在搜索页顶部显示你经常联系的人，方便快速打开。');
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

import { router, promptAction } from '@kit.ArkUI';
import { TdObject, TdError } from '../../tdkit/TdTypes';
import {
  RULE_EVERYBODY, RULE_CONTACTS, RULE_NOBODY,
  PrivacyValue, getPrivacy, setPrivacy
} from '../../store/PrivacyApi';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_RADIUS: number = 14;

export interface PrivacyRuleParams {
  setting: string; // a UserPrivacySetting @type
  title: string;
  hint: string;
}

interface RuleOption {
  label: string;
  value: string;
}

const OPTIONS: RuleOption[] = [
  { label: '所有人', value: RULE_EVERYBODY },
  { label: '我的联系人', value: RULE_CONTACTS },
  { label: '没有人', value: RULE_NOBODY }
];

// Who may see / do this one thing. The exception rules TDLib already holds for
// the setting are read here and written back untouched — this page only ever
// changes the base rule.
@Entry
@Component
struct PrivacyRulePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State setting: string = '';
  @State title: string = '';
  @State hint: string = '';
  @State base: string = '';
  @State exceptions: number = 0;
  @State loading: boolean = true;
  private extra: TdObject[] = [];

  aboutToAppear(): void {
    const p = router.getParams() as PrivacyRuleParams | undefined;
    if (p === undefined || p.setting === undefined || p.setting === '') {
      router.back();
      return;
    }
    this.setting = p.setting;
    this.title = p.title;
    this.hint = p.hint;
    getPrivacy(this.setting).then((v: PrivacyValue) => {
      this.base = v.base;
      this.exceptions = v.exceptions;
      this.extra = v.extra;
      this.loading = false;
    }).catch((e: TdError) => {
      console.error(`PrivacyRulePage.getPrivacy failed: ${e.message}`);
      this.loading = false;
      promptAction.showToast({ message: '读取隐私设置失败', duration: 1500 });
    });
  }

  private pick(value: string): void {
    if (value === this.base || this.loading) {
      return;
    }
    const previous = this.base;
    this.base = value; // optimistic — the row must respond to the tap at once
    setPrivacy(this.setting, value, this.extra).catch((e: TdError) => {
      console.error(`PrivacyRulePage.setPrivacy failed: ${e.message}`);
      this.base = previous;
      promptAction.showToast({ message: '保存失败，请重试', duration: 1500 });
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text(this.title).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      this.header();
      if (this.loading) {
        Column() {
          LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column() {
            Column() {
              ForEach(OPTIONS, (opt: RuleOption, idx: number) => {
                if (idx > 0) {
                  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
                }
                Row() {
                  Text(opt.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
                  if (this.base === opt.value) {
                    SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
                  }
                }
                .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .onClick(() => { this.pick(opt.value); });
              }, (opt: RuleOption) => opt.value);
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS);

            Text(this.hint).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
              .width('100%').padding({ left: 16, right: 16, top: 8 });

            if (this.exceptions > 0) {
              Text(`已为 ${this.exceptions} 个联系人/群组单独设置了例外，本页只改总规则，例外会原样保留。`)
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .width('100%').padding({ left: 16, right: 16, top: 8 });
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
        }
        .layoutWeight(1).width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}

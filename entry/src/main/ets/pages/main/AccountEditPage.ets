import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const BIO_MAX: number = 140;

// 账号 edit page (Telegram-style): first/last name, bio (140 chars), and the
// read-only personal-info card. ✓ in the header saves via setName/setBio.
@Entry
@Component
struct AccountEditPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State firstName: string = '';
  @State lastName: string = '';
  @State bio: string = '';
  @State phone: string = '';
  @State username: string = '';
  @State birthday: string = '';
  @State saving: boolean = false;
  private origFirst: string = '';
  private origLast: string = '';
  private origBio: string = '';

  aboutToAppear(): void {
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req).then((me: TdObject) => {
      const myId = (me['id'] as number | undefined) ?? 0;
      if (myId === 0) {
        return;
      }
      // getUser (not the getMe payload): same path the profile pages use —
      // guarantees usernames and the rest are populated.
      const ureq: TdRequest = { '@type': 'getUser' };
      ureq['user_id'] = myId;
      getTdClient().send(ureq).then((user: TdObject) => {
        this.firstName = (user['first_name'] as string | undefined) ?? '';
        this.lastName = (user['last_name'] as string | undefined) ?? '';
        this.origFirst = this.firstName;
        this.origLast = this.lastName;
        this.phone = (user['phone_number'] as string | undefined) ?? '';
        const un = user['usernames'] as TdObject | undefined;
        const actives = un !== undefined ? ((un['active_usernames'] as string[] | undefined) ?? []) : [];
        this.username = actives.length > 0 ? actives[0] : '';
        console.info(`AccountEditPage: user loaded, username=${this.username}, hasUsernames=${un !== undefined}`);
      }).catch((e: TdError) => {
        console.error(`AccountEditPage.getUser failed: ${e.message}`);
      });
      const full: TdRequest = { '@type': 'getUserFullInfo' };
      full['user_id'] = myId;
      getTdClient().send(full).then((fi: TdObject) => {
        const bioFt = fi['bio'] as TdObject | undefined;
        this.bio = bioFt !== undefined ? ((bioFt['text'] as string | undefined) ?? '') : '';
        this.origBio = this.bio;
        const bd = fi['birthdate'] as TdObject | undefined;
        if (bd !== undefined) {
          const day = (bd['day'] as number | undefined) ?? 0;
          const month = (bd['month'] as number | undefined) ?? 0;
          this.birthday = (day > 0 && month > 0) ? `${month}月${day}日` : '';
        }
        console.info(`AccountEditPage: full loaded, bio=${this.bio.length} chars, birthday=${this.birthday}`);
      }).catch((e: TdError) => {
        console.error(`AccountEditPage.getUserFullInfo failed: ${e.message}`);
      });
    }).catch((e: TdError) => {
      console.error(`AccountEditPage.getMe failed: ${e.message}`);
    });
  }

  private save(): void {
    if (this.saving) {
      return;
    }
    if (this.firstName.trim() === '') {
      promptAction.showToast({ message: '名字不能为空', duration: 1500 });
      return;
    }
    this.saving = true;
    const jobs: Promise<TdObject>[] = [];
    if (this.firstName !== this.origFirst || this.lastName !== this.origLast) {
      const req: TdRequest = { '@type': 'setName' };
      req['first_name'] = this.firstName.trim();
      req['last_name'] = this.lastName.trim();
      jobs.push(getTdClient().send(req));
    }
    if (this.bio !== this.origBio) {
      const req: TdRequest = { '@type': 'setBio' };
      req['bio'] = this.bio;
      jobs.push(getTdClient().send(req));
    }
    if (jobs.length === 0) {
      this.saving = false;
      router.back();
      return;
    }
    Promise.all(jobs).then(() => {
      this.saving = false;
      promptAction.showToast({ message: '已保存', duration: 1200 });
      router.back();
    }).catch((e: TdError) => {
      this.saving = false;
      console.error(`AccountEditPage.save failed: ${e.message}`);
      promptAction.showToast({ message: `保存失败：${e.message}`, duration: 2000 });
    });
  }

  @Builder
  sectionLabel(label: string) {
    Text(label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 2 });
  }

  // NOTE: @Builder value parameters are captured at first render and are NOT
  // re-evaluated when @State changes. phone/username/birthday resolve
  // asynchronously, so each row inlines its markup and reads state directly —
  // passing the value through a builder parameter would freeze it at '未设置'.
  @Builder
  phoneRow() {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.phone_fill')).fontSize(18).fontColor([Color.White]);
      }
      .width(34).height(34).borderRadius(9).backgroundColor('#34C759');
      Column({ space: 2 }) {
        Text(this.phone !== '' ? `+${this.phone}` : '未设置').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text('手机号码').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      promptAction.showToast({ message: '更换手机号需要短信验证，暂未支持', duration: 2000 });
    });
  }

  @Builder
  usernameRow() {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.at')).fontSize(18).fontColor([Color.White]);
      }
      .width(34).height(34).borderRadius(9).backgroundColor('#FF9500');
      Column({ space: 2 }) {
        Text(this.username !== '' ? `@${this.username}` : '未设置').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text('用户名（点击修改）').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.editUsername = this.username;
      this.usernameCtrl.open();
    });
  }

  @Builder
  birthdayRow() {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.cake')).fontSize(18).fontColor([Color.White]);
      }
      .width(34).height(34).borderRadius(9).backgroundColor('#3478F6');
      Column({ space: 2 }) {
        Text(this.birthday !== '' ? this.birthday : '未设置').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text('生日（点击修改）').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.pickBirthday(); });
  }

  // --- username edit ---
  @State editUsername: string = '';
  private usernameCtrl: CustomDialogController = new CustomDialogController({
    builder: UsernameDialog({
      value: this.editUsername,
      onSave: (v: string): void => { this.saveUsername(v); }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private saveUsername(v: string): void {
    const name = v.trim().replace('@', '');
    if (name === this.username) {
      return;
    }
    const req: TdRequest = { '@type': 'setUsername' };
    req['username'] = name;
    getTdClient().send(req).then(() => {
      this.username = name;
      promptAction.showToast({ message: '用户名已更新', duration: 1500 });
    }).catch((e: TdError) => {
      const msg = e.message.includes('OCCUPIED') ? '该用户名已被占用'
        : (e.message.includes('INVALID') ? '用户名格式不正确（5-32 位字母/数字/下划线）' : `修改失败：${e.message}`);
      promptAction.showToast({ message: msg, duration: 2200 });
    });
  }

  // --- birthday edit ---
  private pickBirthday(): void {
    DatePickerDialog.show({
      start: new Date('1900-01-01'),
      end: new Date(),
      selected: new Date('2000-01-01'),
      onDateAccept: (d: Date) => {
        const req: TdRequest = { '@type': 'setBirthdate' };
        const bd: TdObject = { '@type': 'birthdate' };
        bd['day'] = d.getDate();
        bd['month'] = d.getMonth() + 1;
        bd['year'] = d.getFullYear();
        req['birthdate'] = bd;
        getTdClient().send(req).then(() => {
          this.birthday = `${d.getMonth() + 1}月${d.getDate()}日`;
          promptAction.showToast({ message: '生日已更新', duration: 1500 });
        }).catch((e: TdError) => {
          promptAction.showToast({ message: `修改失败：${e.message}`, duration: 2000 });
        });
      }
    });
  }

  build() {
    Column() {
      Row({ space: 16 }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
          .onClick(() => { router.back(); });
        Text('账号').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1);
        if (this.saving) {
          LoadingProgress().width(24).height(24).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(24).fontColor([COLOR_PRIMARY])
            .onClick(() => { this.save(); });
        }
      }
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center);

      Scroll() {
        Column({ space: 0 }) {
          // 你的姓名
          Column() {
            this.sectionLabel('你的姓名');
            TextInput({ text: this.firstName, placeholder: '名字' })
              .fontSize(17).backgroundColor(Color.Transparent)
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onChange((v: string) => { this.firstName = v; });
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
            TextInput({ text: this.lastName, placeholder: '姓' })
              .fontSize(17).backgroundColor(Color.Transparent)
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onChange((v: string) => { this.lastName = v; });
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .padding({ bottom: 4 })
          .margin({ left: 12, right: 12, top: 8 });

          // 个人简介
          Column() {
            Row() {
              TextInput({ text: this.bio, placeholder: '个人简介' })
                .fontSize(17).backgroundColor(Color.Transparent)
                .padding({ left: 16, right: 8, top: 12, bottom: 12 })
                .maxLength(BIO_MAX)
                .layoutWeight(1)
                .onChange((v: string) => { this.bio = v; });
              Text(`${BIO_MAX - this.bio.length}`)
                .fontSize(15).fontColor(COLOR_TEXT_SECONDARY).margin({ right: 16 });
            }.width('100%').alignItems(VerticalAlign.Center);
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .margin({ left: 12, right: 12, top: 14 });
          Text('关于您自己的文字介绍。')
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').padding({ left: 24, right: 24, top: 6 });

          // 个人信息（只读）
          Column() {
            this.sectionLabel('个人信息');
            this.phoneRow();
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 64 });
            this.usernameRow();
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 64 });
            this.birthdayRow();
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .padding({ bottom: 4 })
          .margin({ left: 12, right: 12, top: 14 });
        }
        .width('100%')
        .padding({ bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}


// Simple username editor dialog: @-prefixed input + 取消/保存.
@CustomDialog
struct UsernameDialog {
  controller?: CustomDialogController;
  value: string = '';
  onSave: (v: string) => void = (): void => {};
  @State input: string = '';

  aboutToAppear(): void {
    this.input = this.value;
  }

  build() {
    Column({ space: 16 }) {
      Text('修改用户名').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Row({ space: 4 }) {
        Text('@').fontSize(17).fontColor(COLOR_TEXT_SECONDARY);
        TextInput({ text: this.input, placeholder: '用户名' })
          .fontSize(17).layoutWeight(1)
          .backgroundColor(Color.Transparent).padding(0)
          .onChange((v: string) => { this.input = v; });
      }
      .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface_alt')).borderRadius(10)
      .alignItems(VerticalAlign.Center);
      Text('5-32 位，可用字母、数字和下划线')
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      Row({ space: 12 }) {
        Blank().layoutWeight(1);
        Text('取消').fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => { this.controller?.close(); });
        Text('保存').fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => {
            this.controller?.close();
            this.onSave(this.input);
          });
      }.width('100%');
    }
    .padding(22)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .width('86%');
  }
}

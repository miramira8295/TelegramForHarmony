import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cameraPicker } from '@kit.CameraKit';
import { camera } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { StickerPicker, StickerItem } from '../chat/StickerPicker';
import { getTdClient } from '../../tdkit/Globals';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { QrDialog } from '../common/QrDialog';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { publicLink } from '../../util/telegramLink';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');

// The current user's own profile tab (Telegram-style "my profile"): avatar
// header, 设置照片/编辑信息/设置 quick actions, an info card (phone/username/
// birthday) and the 动态 posts section. Mirrors ProfileStore snapshot into
// @State so every card re-renders on updates.
@Preview
@Component
export struct MyProfilePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State myId: number = 0;
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State avatarAnimPath: string = '';
  @State statusEmojiPath: string = '';
  @State statusEmojiFormat: string = '';
  @State statusText: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State birthday: string = '';
  @State postTab: number = 0; // 0 动态 / 1 已归档的动态
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
      console.error(`MyProfilePage.getMe failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  @State qrLink: string = '';
  private qrCtrl: CustomDialogController = new CustomDialogController({
    builder: QrDialog({ link: this.qrLink, title: this.name }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private openQr(): void {
    if (this.usernames.length === 0) {
      promptAction.showToast({ message: '未设置用户名，无法生成二维码', duration: 1800 });
      return;
    }
    this.qrLink = publicLink(this.usernames[0]);
    this.qrCtrl.open();
  }

  private stickerCtrl: CustomDialogController = new CustomDialogController({
    builder: StickerAvatarDialog({ onPick: (st: StickerItem): void => { this.onStickerPicked(st); } }),
    alignment: DialogAlignment.Bottom,
    autoCancel: true,
    customStyle: true
  });

  // 设置照片: camera / gallery / sticker.
  private setPhotoMenu(): void {
    promptAction.showActionMenu({
      title: '设置照片',
      buttons: [
        { text: '拍照', color: '#3390EC' },
        { text: '从相册选择', color: '#3390EC' },
        { text: '表情贴纸', color: '#3390EC' }
      ]
    }).then((r) => {
      if (r.index === 0) {
        this.photoFromCamera();
      } else if (r.index === 1) {
        this.photoFromGallery();
      } else if (r.index === 2) {
        this.stickerCtrl.open();
      }
    }).catch((e: Object) => {
      console.error(`MyProfilePage.setPhotoMenu failed: ${JSON.stringify(e)}`);
    });
  }

  private async photoFromCamera(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_FRONT
      };
      const res = await cameraPicker.pick(getContext(this) as common.Context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      if (res.resultCode === 0 && res.resultUri !== '') {
        const path = this.copyUriToCache(res.resultUri);
        if (path !== '') {
          this.uploadPhoto(path);
        }
      }
    } catch (e) {
      console.error(`MyProfilePage.photoFromCamera failed: ${e}`);
    }
  }

  private photoFromGallery(): void {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    opts.maxSelectNumber = 1;
    picker.select(opts).then((res: photoAccessHelper.PhotoSelectResult) => {
      const uris = res.photoUris;
      if (uris.length > 0) {
        const path = this.copyUriToCache(uris[0]);
        if (path !== '') {
          this.uploadPhoto(path);
        }
      }
    }).catch((e: Object) => {
      console.error(`MyProfilePage.photoFromGallery failed: ${JSON.stringify(e)}`);
    });
  }

  // Emoji/sticker avatar: static raster of the picked sticker (webp source
  // directly; animated formats fall back to their raster thumbnail).
  private onStickerPicked(st: StickerItem): void {
    this.stickerCtrl.close();
    if (st.format === 'webp') {
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = st.fileId;
      req['priority'] = 1;
      req['synchronous'] = true;
      getTdClient().send(req).then((f: TdObject) => {
        const local = f['local'] as TdObject | undefined;
        const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path !== '') {
          this.uploadPhotoScaled(path);
        }
      }).catch((e: TdError) => {
        console.error(`MyProfilePage sticker download failed: ${e.message}`);
      });
    } else if (st.thumbPath !== '') {
      this.uploadPhotoScaled(st.thumbPath);
    } else if (st.thumbFileId > 0) {
      // Thumbnail wasn't downloaded yet (cell showed the fallback character).
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = st.thumbFileId;
      req['priority'] = 1;
      req['synchronous'] = true;
      getTdClient().send(req).then((f: TdObject) => {
        const local = f['local'] as TdObject | undefined;
        const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path !== '') {
          this.uploadPhotoScaled(path);
        }
      }).catch((e: TdError) => {
        console.error(`MyProfilePage thumb download failed: ${e.message}`);
      });
    } else {
      promptAction.showToast({ message: '该表情暂不可用作头像（unicode 表情请截图或用贴纸）', duration: 2000 });
    }
  }

  // Telegram rejects avatars smaller than 512px (PHOTO_CROP_SIZE_SMALL) —
  // sticker thumbnails are ~128px, so upscale and re-encode before upload.
  private async upscaleForAvatar(path: string): Promise<string> {
    try {
      const src = image.createImageSource(path);
      const info = await src.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (Math.min(w, h) >= 512) {
        src.release();
        return path;
      }
      const scale = 640 / Math.min(w, h);
      const pm = await src.createPixelMap({
        desiredSize: { width: Math.round(w * scale), height: Math.round(h * scale) }
      });
      const packer = image.createImagePacker();
      const buf = await packer.packing(pm, { format: 'image/jpeg', quality: 92 });
      packer.release();
      pm.release();
      src.release();
      const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/avatar_up_${Date.now()}.jpg`;
      const f = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(f.fd, buf);
      fs.closeSync(f);
      return dest;
    } catch (e) {
      console.error(`MyProfilePage.upscaleForAvatar failed: ${e}`);
      return path;
    }
  }

  private async uploadPhotoScaled(path: string): Promise<void> {
    this.uploadPhoto(await this.upscaleForAvatar(path));
  }

  private uploadPhoto(path: string): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const photo: TdObject = { '@type': 'inputChatPhotoStatic' };
    photo['photo'] = inputFile;
    const req: TdRequest = { '@type': 'setProfilePhoto' };
    req['photo'] = photo;
    req['is_public'] = false;
    getTdClient().send(req).then(() => {
      promptAction.showToast({ message: '头像已更新', duration: 1500 });
      if (this.store !== null) {
        this.store.reload();
      }
    }).catch((e: TdError) => {
      console.error(`MyProfilePage.setProfilePhoto failed: ${e.message}`);
      promptAction.showToast({ message: `设置失败：${e.message}`, duration: 2000 });
    });
  }

  private copyUriToCache(uri: string): string {
    try {
      const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
      const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/avatar_${Date.now()}_${name}`;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      return dest;
    } catch (e) {
      console.error(`MyProfilePage.copyUriToCache failed: ${e}`);
      return '';
    }
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
    this.statusText = s.statusText;
    this.phone = s.phone;
    this.usernames = s.usernames;
    this.birthday = s.birthday;
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(40).height(40).borderRadius(20).backgroundColor($r('app.color.surface'))
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .onClick(onTap);
  }

  @Builder
  actionButton(symbol: string, label: string, onTap: () => void) {
    Column({ space: 5 }) {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_PRIMARY]);
      Text(label).fontSize(12).fontColor(COLOR_PRIMARY);
    }
    .layoutWeight(1).height(62)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .onClick(onTap);
  }

  @Builder
  sectionDivider() {
    Divider().color($r('app.color.divider')).strokeWidth(0.7);
  }

  @Builder
  infoRow(value: string, label: string, valueColor: ResourceColor) {
    Column({ space: 2 }) {
      Text(value).fontSize(15).fontColor(valueColor).copyOption(CopyOptions.LocalDevice);
      Text(label).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 8, bottom: 8 });
  }

  @Builder
  header() {
    Column({ space: 8 }) {
      Row() {
        this.circleButton('sys.symbol.qrcode', () => { this.openQr(); });
        Blank().layoutWeight(1);
        this.circleButton('sys.symbol.more', () => {});
      }.width('100%').padding({ left: 12, right: 12 });
      AvatarView({
        avatarPath: this.avatarPath, initials: this.initials,
        colorSeed: this.myId, avatarSize: 100,
        animPath: this.avatarAnimPath
      });
      Row({ space: 5 }) {
        Text(this.name)
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1);
        if (this.statusEmojiPath !== '') {
          this.statusEmoji();
        }
      }
      .alignItems(VerticalAlign.Center)
      .constraintSize({ maxWidth: '86%' });
      Text(this.statusText !== '' ? this.statusText : '在线')
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 });
  }

  @Builder
  actionsRow() {
    Row({ space: 8 }) {
      this.actionButton('sys.symbol.camera', '设置照片', () => { this.setPhotoMenu(); });
      this.actionButton('sys.symbol.pencil_line', '编辑信息', () => {
        router.pushUrl({ url: 'pages/main/AccountEditPage' });
      });
      this.actionButton('sys.symbol.gearshape', '设置', () => {});
    }
    .width('100%').padding({ left: 12, right: 12, top: 14 });
  }

  @Builder
  infoCard() {
    Column() {
      Column() {
        if (this.phone !== '') {
          this.infoRow(`+${this.phone}`, '手机', COLOR_TEXT_PRIMARY);
        }
        if (this.usernames.length > 0) {
          if (this.phone !== '') {
            this.sectionDivider();
          }
          this.infoRow(`@${this.usernames[0]}`, '用户名', COLOR_TEXT_PRIMARY);
        }
        if (this.birthday !== '') {
          if (this.phone !== '' || this.usernames.length > 0) {
            this.sectionDivider();
          }
          this.infoRow(this.birthday, '生日', COLOR_TEXT_PRIMARY);
        }
      }
      .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start);
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  postTabPill(label: string, index: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.postTab === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.postTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .backgroundColor(this.postTab === index ? $r('app.color.selected_pill') : Color.Transparent)
      .borderRadius(14)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .onClick(() => { this.postTab = index; });
  }

  @Builder
  postsTabs() {
    Row({ space: 4 }) {
      this.postTabPill('动态', 0);
      this.postTabPill('已归档的动态', 1);
    }
    .padding(3)
    .backgroundColor(CARD_BG).borderRadius(18)
    .margin({ top: 16, bottom: 8 });
  }

  @Builder
  emptyPosts() {
    Column({ space: 12 }) {
      Text('暂无贴文').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text('发布照片和视频并显示在您的个人资料页上')
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center).constraintSize({ maxWidth: '80%' });
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.camera')).fontSize(20).fontColor([Color.White]);
        Text('添加贴文').fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Medium);
      }
      .padding({ left: 24, right: 24, top: 12, bottom: 12 })
      .backgroundColor(COLOR_PRIMARY).borderRadius(24)
      .margin({ top: 6 });
    }
    .width('100%')
    .padding({ top: 36, bottom: 36 });
  }

  // Premium emoji status beside the name (animated custom emoji).
  @Builder
  statusEmoji() {
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

  build() {
    Scroll() {
      Column() {
        this.header();
        this.actionsRow();
        this.infoCard();
        this.postsTabs();
        this.emptyPosts();
      }
      .width('100%')
      .padding({ bottom: this.bottomSafe + 88 });
    }
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG)
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
  }
}


// Bottom sheet holding the sticker picker for the emoji-avatar option.
@CustomDialog
struct StickerAvatarDialog {
  controller?: CustomDialogController;
  onPick: (s: StickerItem) => void = (): void => {};

  build() {
    Column() {
      // Avatar builder mode: custom-emoji library + trending packs (official-style).
      StickerPicker({
        stickerType: 'custom_emoji',
        includeTrending: true,
        onPick: (s: StickerItem): void => { this.onPick(s); }
      });
    }
    .width('100%').height(400)
    .backgroundColor($r('app.color.surface'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .clip(true);
  }
}

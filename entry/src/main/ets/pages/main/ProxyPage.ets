import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  ProxyEntry, PROXY_SOCKS5, PROXY_MTPROTO, PROXY_HTTP,
  proxyTypeLabel, listProxies, addProxy, enableProxy, disableProxy, removeProxy, pingProxy
} from '../../store/ProxyApi';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E53935';
const OK_GREEN: string = '#34C759';

interface TypeOption {
  label: string;
  value: string;
}

const TYPES: TypeOption[] = [
  { label: 'SOCKS5', value: PROXY_SOCKS5 },
  { label: 'MTProto', value: PROXY_MTPROTO },
  { label: 'HTTP', value: PROXY_HTTP }
];

// 代理设置: the proxy list TDLib actually connects through. Enabling a proxy
// here reroutes the live connection immediately.
@Entry
@Component
struct ProxyPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State proxies: ProxyEntry[] = [];
  @State loading: boolean = true;
  @State pings: Map<number, number> = new Map(); // proxy id → seconds (-1 = unreachable)
  // Add-proxy sheet.
  @State sheetOpen: boolean = false;
  @State fType: string = PROXY_SOCKS5;
  @State fServer: string = '';
  @State fPort: string = '';
  @State fUser: string = '';
  @State fPass: string = '';
  @State fSecret: string = '';
  @State saving: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    listProxies().then((list: ProxyEntry[]) => {
      this.proxies = list;
      this.loading = false;
      for (const p of list) {
        this.ping(p);
      }
    }).catch((e: TdError) => {
      console.error(`ProxyPage.listProxies failed: ${e.message}`);
      this.loading = false;
      promptAction.showToast({ message: '读取代理列表失败', duration: 1500 });
    });
  }

  private ping(p: ProxyEntry): void {
    pingProxy(p).then((sec: number) => {
      const next: Map<number, number> = new Map(this.pings);
      next.set(p.id, sec);
      this.pings = next; // new map — @State only re-renders on assignment
    });
  }

  private pingLabel(id: number): string {
    const sec = this.pings.get(id);
    if (sec === undefined) {
      return '检测中…';
    }
    if (sec < 0) {
      return '无法连接';
    }
    return `${Math.round(sec * 1000)} ms`;
  }

  private pingColor(id: number): string {
    const sec = this.pings.get(id);
    if (sec === undefined) {
      return COLOR_TEXT_SECONDARY as string;
    }
    return sec < 0 ? DANGER : OK_GREEN;
  }

  private toggle(p: ProxyEntry): void {
    const call: Promise<void> = p.isEnabled ? disableProxy() : enableProxy(p.id);
    const wasEnabled = p.isEnabled;
    // Only one proxy can be enabled at a time.
    this.proxies = this.proxies.map((x: ProxyEntry): ProxyEntry => ({
      id: x.id, server: x.server, port: x.port, type: x.type,
      username: x.username, password: x.password, secret: x.secret,
      isEnabled: !wasEnabled && x.id === p.id
    }));
    call.then(() => {
      promptAction.showToast({
        message: wasEnabled ? '已停用代理' : `已启用 ${p.server}`, duration: 1500
      });
    }).catch((e: TdError) => {
      console.error(`ProxyPage.toggle failed: ${e.message}`);
      promptAction.showToast({ message: '操作失败，请重试', duration: 1500 });
      this.load();
    });
  }

  private confirmRemove(p: ProxyEntry): void {
    promptAction.showDialog({
      title: '删除代理',
      message: `确定要删除 ${p.server}:${p.port} 吗？`,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '删除', color: DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index !== 1) {
        return;
      }
      const before = this.proxies;
      this.proxies = this.proxies.filter((x: ProxyEntry) => x.id !== p.id);
      removeProxy(p.id).catch((e: TdError) => {
        console.error(`ProxyPage.removeProxy failed: ${e.message}`);
        this.proxies = before;
        promptAction.showToast({ message: '删除失败，请重试', duration: 1500 });
      });
    }).catch((e: Object) => {
      console.error(`ProxyPage.showDialog failed: ${JSON.stringify(e)}`);
    });
  }

  private resetForm(): void {
    this.fType = PROXY_SOCKS5;
    this.fServer = '';
    this.fPort = '';
    this.fUser = '';
    this.fPass = '';
    this.fSecret = '';
  }

  // Validate at the boundary: a bad port or an empty host would be rejected by
  // TDLib with an opaque error, so say what's wrong here instead.
  private save(): void {
    const server = this.fServer.trim();
    const port = Number.parseInt(this.fPort.trim(), 10);
    if (server === '') {
      promptAction.showToast({ message: '请填写服务器地址', duration: 1500 });
      return;
    }
    if (Number.isNaN(port) || port <= 0 || port > 65535) {
      promptAction.showToast({ message: '端口需为 1-65535 的数字', duration: 1500 });
      return;
    }
    if (this.fType === PROXY_MTPROTO && this.fSecret.trim() === '') {
      promptAction.showToast({ message: 'MTProto 代理需要填写密钥', duration: 1500 });
      return;
    }
    if (this.saving) {
      return;
    }
    this.saving = true;
    const entry: ProxyEntry = {
      id: 0, server, port, type: this.fType,
      username: this.fUser.trim(), password: this.fPass,
      secret: this.fSecret.trim(), isEnabled: false
    };
    addProxy(entry, true).then(() => {
      this.saving = false;
      this.sheetOpen = false;
      this.resetForm();
      promptAction.showToast({ message: '代理已添加并启用', duration: 1500 });
      this.load();
    }).catch((e: TdError) => {
      this.saving = false;
      console.error(`ProxyPage.addProxy failed: ${e.message}`);
      promptAction.showToast({ message: `添加失败：${e.message}`, duration: 2000 });
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('代理设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      SymbolGlyph($r('sys.symbol.plus')).fontSize(22).fontColor([COLOR_PRIMARY])
        .onClick(() => { this.sheetOpen = true; });
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  field(label: string, value: string, onChange: (v: string) => void, isPassword: boolean) {
    Column({ space: 4 }) {
      Text(label).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      TextInput({ text: value })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .fontSize(16)
        .backgroundColor($r('app.color.page_bg'))
        .borderRadius(10)
        .onChange((v: string) => { onChange(v); });
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 6 });
  }

  @Builder
  addSheet() {
    Column({ space: 10 }) {
      Text('添加代理').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .padding({ top: 16, bottom: 4 });
      Row({ space: 8 }) {
        ForEach(TYPES, (t: TypeOption) => {
          Text(t.label).fontSize(14)
            .fontColor(this.fType === t.value ? Color.White : COLOR_TEXT_PRIMARY)
            .backgroundColor(this.fType === t.value ? COLOR_PRIMARY : $r('app.color.page_bg'))
            .borderRadius(16)
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .onClick(() => { this.fType = t.value; });
        }, (t: TypeOption) => t.value);
      }.padding({ bottom: 4 });

      this.field('服务器', this.fServer, (v: string): void => { this.fServer = v; }, false);
      this.field('端口', this.fPort, (v: string): void => { this.fPort = v; }, false);
      if (this.fType === PROXY_MTPROTO) {
        this.field('密钥 (secret)', this.fSecret, (v: string): void => { this.fSecret = v; }, false);
      } else {
        this.field('用户名（可选）', this.fUser, (v: string): void => { this.fUser = v; }, false);
        this.field('密码（可选）', this.fPass, (v: string): void => { this.fPass = v; }, true);
      }

      Row({ space: 12 }) {
        Text('取消').fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .layoutWeight(1).textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => { this.sheetOpen = false; });
        Text(this.saving ? '添加中…' : '添加并启用')
          .fontSize(16).fontColor(Color.White)
          .layoutWeight(1).textAlign(TextAlign.Center)
          .backgroundColor(COLOR_PRIMARY).borderRadius(10)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => { this.save(); });
      }
      .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 });
    }
    .width('100%')
    .padding({ bottom: this.bottomSafe + 8 });
  }

  @Builder
  proxyRow(p: ProxyEntry) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(`${p.server}:${p.port}`).fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 200 });
          Text(proxyTypeLabel(p.type)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor($r('app.color.page_bg')).borderRadius(6)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 });
        }.alignItems(VerticalAlign.Center);
        Row({ space: 8 }) {
          Text(this.pingLabel(p.id)).fontSize(12).fontColor(this.pingColor(p.id));
          if (p.isEnabled) {
            Text('使用中').fontSize(12).fontColor(COLOR_PRIMARY);
          }
        };
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: p.isEnabled })
        .selectedColor(COLOR_PRIMARY)
        .onChange(() => { this.toggle(p); });
      Text('删除').fontSize(14).fontColor(DANGER)
        .onClick(() => { this.confirmRemove(p); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      this.header();
      if (this.loading) {
        Column() {
          LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.proxies.length === 0) {
        Column({ space: 10 }) {
          Text('没有代理').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text('添加 SOCKS5、MTProto 或 HTTP 代理后，连接会通过它建立。')
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
            .padding({ left: 40, right: 40 });
          Text('添加代理').fontSize(16).fontColor(Color.White)
            .backgroundColor(COLOR_PRIMARY).borderRadius(22)
            .padding({ left: 24, right: 24, top: 11, bottom: 11 })
            .margin({ top: 6 })
            .onClick(() => { this.sheetOpen = true; });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 8 }) {
            Column() {
              ForEach(this.proxies, (p: ProxyEntry, idx: number) => {
                if (idx > 0) {
                  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
                }
                this.proxyRow(p);
              }, (p: ProxyEntry) => `p_${p.id}_${p.isEnabled}`);
            }
            .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS);
            Text('同一时间只能启用一个代理。关闭全部代理即直连。')
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
              .width('100%').padding({ left: 16, right: 16, top: 4 });
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
    .padding({ top: this.topSafe })
    .bindSheet($$this.sheetOpen, this.addSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: $r('app.color.surface'),
      dragBar: true
    });
  }
}

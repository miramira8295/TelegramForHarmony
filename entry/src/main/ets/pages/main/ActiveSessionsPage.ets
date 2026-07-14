import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E53935';

interface SessionRow {
  id: string;          // int64 — keep the raw string, JS numbers lose precision
  isCurrent: boolean;
  appName: string;     // "Telegram Android 11.2.0"
  device: string;      // "Xiaomi 14 · Android 15"
  location: string;    // "Beijing, China · 1.2.3.4"
  lastActive: string;
}

function formatLastActive(sec: number, now: number): string {
  const diff = now - sec;
  if (diff < 60) {
    return '刚刚';
  }
  if (diff < 3600) {
    return `${Math.floor(diff / 60)} 分钟前`;
  }
  if (diff < 86400) {
    return `${Math.floor(diff / 3600)} 小时前`;
  }
  const d = new Date(sec * 1000);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

// 活跃会话: every device logged into this account, with real termination
// (terminateSession). The current session can't be terminated from here — that
// would be a logout, which belongs elsewhere.
@Entry
@Component
struct ActiveSessionsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State current: SessionRow | null = null;
  @State others: SessionRow[] = [];
  @State loading: boolean = true;

  aboutToAppear(): void {
    this.load();
  }

  private parse(s: TdObject, now: number): SessionRow {
    const app = (s['application_name'] as string | undefined) ?? '';
    const ver = (s['application_version'] as string | undefined) ?? '';
    const model = (s['device_model'] as string | undefined) ?? '';
    const platform = (s['platform'] as string | undefined) ?? '';
    const sysVer = (s['system_version'] as string | undefined) ?? '';
    const ip = (s['ip_address'] as string | undefined) ?? '';
    const loc = (s['location'] as string | undefined) ?? '';
    const parts: string[] = [];
    if (loc !== '') {
      parts.push(loc);
    }
    if (ip !== '') {
      parts.push(ip);
    }
    return {
      id: `${s['id']}`,
      isCurrent: (s['is_current'] as boolean | undefined) ?? false,
      appName: `${app}${ver !== '' ? ' ' + ver : ''}`,
      device: `${model}${platform !== '' ? ' · ' + platform : ''}${sysVer !== '' ? ' ' + sysVer : ''}`,
      location: parts.join(' · '),
      lastActive: formatLastActive((s['last_active_date'] as number | undefined) ?? 0, now)
    };
  }

  private load(): void {
    const now = Math.floor(Date.now() / 1000);
    getTdClient().send({ '@type': 'getActiveSessions' } as TdRequest).then((res: TdObject) => {
      const list = (res['sessions'] as TdObject[] | undefined) ?? [];
      const rows = list.map((s: TdObject): SessionRow => this.parse(s, now));
      this.current = rows.find((r: SessionRow) => r.isCurrent) ?? null;
      this.others = rows.filter((r: SessionRow) => !r.isCurrent);
      this.loading = false;
    }).catch((e: TdError) => {
      console.error(`ActiveSessionsPage.getActiveSessions failed: ${e.message}`);
      this.loading = false;
      promptAction.showToast({ message: '读取登录设备失败', duration: 1500 });
    });
  }

  private terminate(row: SessionRow): void {
    const req: TdRequest = { '@type': 'terminateSession' };
    req['session_id'] = row.id;
    const before = this.others;
    this.others = this.others.filter((r: SessionRow) => r.id !== row.id);
    getTdClient().send(req).then(() => {
      promptAction.showToast({ message: '已退出该设备', duration: 1500 });
    }).catch((e: TdError) => {
      console.error(`ActiveSessionsPage.terminateSession failed: ${e.message}`);
      this.others = before;
      promptAction.showToast({ message: '操作失败，请重试', duration: 1500 });
    });
  }

  private confirmTerminate(row: SessionRow): void {
    promptAction.showDialog({
      title: '退出设备',
      message: `确定要退出 ${row.appName !== '' ? row.appName : row.device} 的登录吗？`,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '退出', color: DANGER }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        this.terminate(row);
      }
    }).catch((e: Object) => {
      console.error(`ActiveSessionsPage.showDialog failed: ${JSON.stringify(e)}`);
    });
  }

  @Builder
  header() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([COLOR_TEXT_PRIMARY])
        .onClick(() => { router.back(); });
      Text('活跃会话').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  sessionRow(r: SessionRow, canTerminate: boolean) {
    Column({ space: 3 }) {
      Row({ space: 10 }) {
        Text(r.appName !== '' ? r.appName : '未知应用')
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (canTerminate) {
          Text('退出').fontSize(15).fontColor(DANGER)
            .onClick(() => { this.confirmTerminate(r); });
        } else {
          Text(r.lastActive).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
      }.width('100%').alignItems(VerticalAlign.Center);
      if (r.device !== '') {
        Text(r.device).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      Row({ space: 8 }) {
        if (r.location !== '') {
          Text(r.location).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        if (canTerminate) {
          Text(r.lastActive).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
      }.width('100%');
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 });
  }

  @Builder
  cardTitle(text: string) {
    Text(text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 });
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
          Column({ space: 14 }) {
            if (this.current !== null) {
              Column() {
                this.cardTitle('当前设备');
                this.sessionRow(this.current as SessionRow, false);
              }
              .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
              .padding({ bottom: 4 });
            }
            if (this.others.length > 0) {
              Column() {
                this.cardTitle('其他登录设备');
                ForEach(this.others, (r: SessionRow, idx: number) => {
                  if (idx > 0) {
                    Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
                  }
                  this.sessionRow(r, true);
                }, (r: SessionRow) => `s_${r.id}`);
              }
              .width('100%').backgroundColor($r('app.color.surface')).borderRadius(CARD_RADIUS)
              .padding({ bottom: 4 });
              Text('退出后，该设备需要重新登录才能访问你的账号。')
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .width('100%').padding({ left: 16, right: 16, top: 6 });
            } else {
              Text('没有其他登录设备。')
                .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
                .width('100%').padding({ left: 16, right: 16, top: 6 });
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

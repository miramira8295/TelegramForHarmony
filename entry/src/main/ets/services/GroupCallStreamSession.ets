import { TimerFns } from '../tdkit/TdClient';
import { nextTimeOffset } from './StreamSegmentMath';

export type SegmentFetcher = (channelId: number, timeOffset: number, scale: number) => Promise<Uint8Array>;
export type SegmentSink = (channelId: number, timeOffset: number, bytes: Uint8Array) => void;

const MAX_RETRIES: number = 5;

export class GroupCallStreamSession {
  private fetch: SegmentFetcher;
  private sink: SegmentSink;
  private timer: TimerFns;
  private stopped: boolean = false;
  private channelId: number = 0;
  private scale: number = 0;
  private cursor: number = 0;

  constructor(fetch: SegmentFetcher, sink: SegmentSink, timer?: TimerFns) {
    this.fetch = fetch;
    this.sink = sink;
    this.timer = timer ?? {
      setTimeout: (cb: () => void, ms: number): number => setTimeout(cb, ms),
      clearTimeout: (id: number): void => clearTimeout(id)
    };
  }

  start(channelId: number, scale: number, liveEdgeMs: number, backSegments: number): void {
    this.stopped = false;
    this.channelId = channelId;
    this.scale = scale;
    const dur = Math.floor(1000 / Math.pow(2, scale));
    this.cursor = Math.floor(liveEdgeMs / dur) * dur - backSegments * dur;
    this.pump(0);
  }

  stop(): void {
    this.stopped = true;
  }

  private pump(attempt: number): void {
    if (this.stopped) { return; }
    const offset = this.cursor;
    this.fetch(this.channelId, offset, this.scale).then((bytes: Uint8Array) => {
      if (this.stopped) { return; }
      this.sink(this.channelId, offset, bytes);
      this.cursor = nextTimeOffset(this.cursor, this.scale);
      this.pump(0);
    }).catch(() => {
      if (this.stopped) { return; }
      if (attempt + 1 <= MAX_RETRIES) {
        const delay = Math.min(4000, 300 * Math.pow(2, attempt));
        this.timer.setTimeout(() => this.pump(attempt + 1), delay);
      } else {
        // 放弃这一段,前进以免卡死
        this.cursor = nextTimeOffset(this.cursor, this.scale);
        this.pump(0);
      }
    });
  }
}

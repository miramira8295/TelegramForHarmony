import { describe, it, expect } from '@ohos/hypium';
import { GroupCallStreamSession, SegmentFetcher, SegmentSink } from '../main/ets/services/GroupCallStreamSession';

export default function groupCallStreamSessionTest() {
  describe('GroupCallStreamSession', () => {
    it('fetches_from_start_offset_and_steps_forward', 0, async () => {
      const asked: number[] = [];
      const fetch: SegmentFetcher = (ch: number, off: number, scale: number): Promise<Uint8Array> => {
        asked.push(off);
        return Promise.resolve(new Uint8Array([1]));
      };
      const delivered: number[] = [];
      const sink: SegmentSink = (ch: number, off: number, bytes: Uint8Array): void => { delivered.push(off); };
      const session = new GroupCallStreamSession(fetch, sink);
      // edge 20000, scale 0 (1000ms), back 2 -> start 18000
      session.start(1, 0, 20000, 2);
      // 让若干个 microtask 轮转,凑够至少 3 段
      for (let i = 0; i < 10; i++) { await Promise.resolve(); }
      session.stop();
      expect(asked[0]).assertEqual(18000);
      expect(asked[1]).assertEqual(19000);
      expect(delivered[0]).assertEqual(18000);
    });
  });
}

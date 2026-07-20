import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';
import { GroupCallStreamInfo } from '../tdkit/GroupCallTypes';
import { getGroupCall, getGroupCallStreams, getGroupCallStreamSegment, joinVideoChat } from '../tdkit/GroupCallApi';
import { startOffset } from './StreamSegmentMath';

// Phase 0 probe: Answer three unknowns from spec §2
// - Unknown 1: Can we fetch segment without joining?
// - Unknown 1b: If not, does join with empty payload get accepted?
// - Unknown 2: What are the first 16 bytes? (tgcalls header vs ftyp/mp4)
// - Unknown 3: Actual stream structure, is_rtmp_stream value, error messages
export async function runLiveStreamProbe(client: TdClient, groupCallId: number): Promise<void> {
  try {
    // Step 1: Get group call metadata
    const gc = await getGroupCall(client, groupCallId);
    const isRtmp = gc['is_rtmp_stream'] as boolean | undefined ?? false;
    const isActive = gc['is_active'] as boolean | undefined ?? false;
    console.info(`[Phase0] getGroupCall ok: is_rtmp=${isRtmp} active=${isActive}`);

    // Step 2: Get available streams
    const streams: GroupCallStreamInfo[] = await getGroupCallStreams(client, groupCallId);
    console.info(`[Phase0] streams=${JSON.stringify(streams)}`);
    if (streams.length === 0) {
      console.warn('[Phase0] no streams');
      return;
    }

    // Step 3: Attempt to fetch segment without joining
    const s: GroupCallStreamInfo = streams[0];
    const probeOffset: number = startOffset(s.timeOffset, s.scale, 2);
    try {
      const seg: Uint8Array = await getGroupCallStreamSegment(
        client, groupCallId, probeOffset, s.scale, s.channelId, 'groupCallVideoQualityThumbnail'
      );
      console.info(`[Phase0] NO-JOIN segment ok len=${seg.length} first16=${JSON.stringify(Array.from(seg.slice(0, 16)))}`);
    } catch (e) {
      console.warn(`[Phase0] NO-JOIN segment failed: ${e}`);

      // Step 4: Fallback: try joining with empty payload and no audio
      try {
        const joinResp: string = await joinVideoChat(client, groupCallId, 0, '', true);
        console.info(`[Phase0] joinVideoChat(empty payload) ok response_len=${joinResp.length}`);
      } catch (e2) {
        console.warn(`[Phase0] joinVideoChat(empty payload) failed: ${e2}`);
      }
    }
  } catch (e) {
    console.error(`[Phase0] probe failed: ${e}`);
  }
}

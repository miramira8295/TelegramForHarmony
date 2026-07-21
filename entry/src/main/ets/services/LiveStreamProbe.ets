import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { GroupCallStreamInfo } from '../tdkit/GroupCallTypes';
import { getGroupCallStreamSegment, joinVideoChat } from '../tdkit/GroupCallApi';
import { startOffset } from './StreamSegmentMath';

// Phase 0 probe (diagnostic build). Each step is independent; getGroupCall
// no longer blocks the streams test. All requests use a 30s timeout so a
// slow-but-eventually-answering TDLib doesn't read as a hard failure.
const PROBE_TIMEOUT_MS: number = 30000;

async function sendRaw(client: TdClient, req: TdRequest, tag: string): Promise<TdObject | null> {
  try {
    const resp: TdObject = await client.send(req, PROBE_TIMEOUT_MS);
    return resp;
  } catch (e) {
    console.warn(`[Phase0] ${tag} failed: ${e}`);
    return null;
  }
}

function parseStreams(resp: TdObject | null): GroupCallStreamInfo[] {
  if (resp === null) { return []; }
  const raw = (resp['streams'] as TdObject[] | undefined) ?? [];
  return raw.map((s: TdObject): GroupCallStreamInfo => ({
    channelId: (s['channel_id'] as number | undefined) ?? 0,
    scale: (s['scale'] as number | undefined) ?? 0,
    timeOffset: (s['time_offset'] as number | undefined) ?? 0
  }));
}

async function fetchStreams(client: TdClient, groupCallId: number, tag: string): Promise<GroupCallStreamInfo[]> {
  const req: TdRequest = { '@type': 'getGroupCallStreams' };
  req['group_call_id'] = groupCallId;
  const resp = await sendRaw(client, req, `${tag} getGroupCallStreams`);
  const streams = parseStreams(resp);
  console.info(`[Phase0] ${tag} streams=${JSON.stringify(streams)}`);
  return streams;
}

async function trySegment(client: TdClient, groupCallId: number, streams: GroupCallStreamInfo[]): Promise<void> {
  if (streams.length === 0) { console.warn('[Phase0] no streams -> skip segment'); return; }
  const s: GroupCallStreamInfo = streams[0];
  const probeOffset: number = startOffset(s.timeOffset, s.scale, 2);
  try {
    const seg: Uint8Array = await getGroupCallStreamSegment(
      client, groupCallId, probeOffset, s.scale, s.channelId, 'groupCallVideoQualityThumbnail'
    );
    console.info(`[Phase0] segment ok len=${seg.length} first16=${JSON.stringify(Array.from(seg.slice(0, 16)))}`);
  } catch (e) {
    console.warn(`[Phase0] segment failed: ${e}`);
  }
}

export async function runLiveStreamProbe(client: TdClient, groupCallId: number): Promise<void> {
  console.info(`[Phase0] probe start gcid=${groupCallId}`);
  if (groupCallId <= 0) { console.warn('[Phase0] invalid gcid, abort'); return; }

  // Step 1: metadata (non-blocking for the rest)
  const gcReq: TdRequest = { '@type': 'getGroupCall' };
  gcReq['group_call_id'] = groupCallId;
  const gc = await sendRaw(client, gcReq, 'getGroupCall');
  if (gc !== null) {
    console.info(`[Phase0] getGroupCall ok: is_rtmp=${gc['is_rtmp_stream']} active=${gc['is_active']} joined=${gc['is_joined']} participants=${gc['participant_count']}`);
  }

  // Step 2 (Unknown 1): streams without joining
  let streams = await fetchStreams(client, groupCallId, 'NO-JOIN');
  if (streams.length > 0) { await trySegment(client, groupCallId, streams); return; }

  // Step 3 (Unknown 1b): join with empty payload
  try {
    const joinResp: string = await joinVideoChat(client, groupCallId, 0, '', true);
    console.info(`[Phase0] joinVideoChat(empty payload) ACCEPTED response_len=${joinResp.length}`);
  } catch (e) {
    console.warn(`[Phase0] joinVideoChat(empty payload) REJECTED: ${e}`);
    return;
  }

  // Step 4: streams + segment after join
  streams = await fetchStreams(client, groupCallId, 'POST-JOIN');
  await trySegment(client, groupCallId, streams);
}

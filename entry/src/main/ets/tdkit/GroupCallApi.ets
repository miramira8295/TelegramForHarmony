import util from '@ohos.util';
import { TdClient } from './TdClient';
import { TdObject, TdRequest } from './TdTypes';
import { GroupCallStreamInfo } from './GroupCallTypes';

export async function getGroupCall(client: TdClient, groupCallId: number): Promise<TdObject> {
  const req: TdRequest = { '@type': 'getGroupCall' };
  req['group_call_id'] = groupCallId;
  return client.send(req);
}

export async function getGroupCallStreams(client: TdClient, groupCallId: number): Promise<GroupCallStreamInfo[]> {
  const req: TdRequest = { '@type': 'getGroupCallStreams' };
  req['group_call_id'] = groupCallId;
  const resp = await client.send(req);
  const raw = (resp['streams'] as TdObject[] | undefined) ?? [];
  return raw.map((s: TdObject): GroupCallStreamInfo => ({
    channelId: (s['channel_id'] as number | undefined) ?? 0,
    scale: (s['scale'] as number | undefined) ?? 0,
    timeOffset: (s['time_offset'] as number | undefined) ?? 0
  }));
}

export async function joinVideoChat(
  client: TdClient, groupCallId: number, audioSourceId: number, payload: string, isMuted: boolean
): Promise<string> {
  const params: TdObject = { '@type': 'groupCallJoinParameters' };
  params['audio_source_id'] = audioSourceId;
  params['payload'] = payload;
  params['is_muted'] = isMuted;
  params['is_my_video_enabled'] = false;
  const reqObj: Record<string, Object | null> = { '@type': 'joinVideoChat' };
  reqObj['group_call_id'] = groupCallId;
  reqObj['participant_id'] = null; // 以自身加入
  reqObj['join_parameters'] = params;
  reqObj['invite_hash'] = '';
  const req = reqObj as TdRequest;
  const resp = await client.send(req);
  return (resp['text'] as string | undefined) ?? '';
}

export async function getGroupCallStreamSegment(
  client: TdClient, groupCallId: number, timeOffset: number, scale: number, channelId: number, videoQualityType: string
): Promise<Uint8Array> {
  const quality: TdObject = { '@type': videoQualityType };
  const req: TdRequest = { '@type': 'getGroupCallStreamSegment' };
  req['group_call_id'] = groupCallId;
  req['time_offset'] = timeOffset;
  req['scale'] = scale;
  req['channel_id'] = channelId;
  req['video_quality'] = quality;
  const resp = await client.send(req, 60000);
  const b64 = (resp['data'] as string | undefined) ?? '';
  const helper = new util.Base64Helper();
  return b64 === '' ? new Uint8Array(0) : helper.decodeSync(b64);
}

export async function leaveGroupCall(client: TdClient, groupCallId: number): Promise<void> {
  const req: TdRequest = { '@type': 'leaveGroupCall' };
  req['group_call_id'] = groupCallId;
  await client.send(req);
}

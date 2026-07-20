export interface GroupCallStreamInfo {
  channelId: number;
  scale: number;
  timeOffset: number;
}

export interface LiveStreamState {
  isActive: boolean;
  isJoined: boolean;
  needRejoin: boolean;
  participantCount: number;
  streams: GroupCallStreamInfo[];
  error: string;
}

export function emptyLiveStreamState(): LiveStreamState {
  return {
    isActive: false, isJoined: false, needRejoin: false,
    participantCount: 0, streams: [], error: ''
  };
}

import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';
import { LiveStreamState, emptyLiveStreamState } from '../tdkit/GroupCallTypes';

export class LiveStreamStore {
  private client: TdClient;
  private groupCallId: number;
  private state: LiveStreamState = emptyLiveStreamState();
  private listeners: Array<(s: LiveStreamState) => void> = [];
  private unsub: (() => void) | null = null;

  constructor(client: TdClient, groupCallId: number) {
    this.client = client;
    this.groupCallId = groupCallId;
    this.unsub = this.client.onUpdate('updateGroupCall', (u: TdObject) => this.onGroupCall(u));
  }

  getState(): LiveStreamState {
    return this.state;
  }

  subscribe(l: (s: LiveStreamState) => void): () => void {
    this.listeners = [...this.listeners, l];
    return (): void => {
      this.listeners = this.listeners.filter((x: (s: LiveStreamState) => void) => x !== l);
    };
  }

  dispose(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    this.listeners = [];
  }

  private onGroupCall(update: TdObject): void {
    const gc = update['group_call'] as TdObject | undefined;
    if (gc === undefined || (gc['id'] as number | undefined) !== this.groupCallId) {
      return;
    }
    this.state = {
      isActive: (gc['is_active'] as boolean | undefined) ?? false,
      isJoined: (gc['is_joined'] as boolean | undefined) ?? false,
      needRejoin: (gc['need_rejoin'] as boolean | undefined) ?? false,
      participantCount: (gc['participant_count'] as number | undefined) ?? 0,
      streams: this.state.streams,
      error: ''
    };
    for (const l of this.listeners) { l(this.state); }
  }
}

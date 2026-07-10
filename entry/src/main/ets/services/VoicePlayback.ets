import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export interface VoiceState {
  playingId: number;  // 0 = idle
  paused: boolean;
  positionMs: number;
  durationMs: number;
  completedId: number; // message id whose playback just finished (0 = none)
}

type VoiceListener = (s: VoiceState) => void;

// Singleton voice-note player: one note at a time, position updates pushed to
// subscribers (each VoiceBubble mirrors state for its own message id).
class VoicePlayback {
  private player: media.AVPlayer | null = null;
  private file: fs.File | null = null;
  private state: VoiceState = { playingId: 0, paused: false, positionMs: 0, durationMs: 0, completedId: 0 };
  private listeners: VoiceListener[] = [];

  subscribe(l: VoiceListener): () => void {
    this.listeners = [...this.listeners, l];
    l(this.state);
    return (): void => { this.listeners = this.listeners.filter((x: VoiceListener) => x !== l); };
  }

  current(): VoiceState {
    return this.state;
  }

  // Tap semantics: play if idle/other note; pause if this note is playing;
  // resume if this note is paused.
  toggle(messageId: number, path: string, fallbackDurationSec: number): void {
    if (this.state.playingId === messageId && this.player !== null) {
      if (this.state.paused) {
        this.player.play();
        this.setState({ playingId: messageId, paused: false, positionMs: this.state.positionMs, durationMs: this.state.durationMs, completedId: 0 });
      } else {
        this.player.pause();
        this.setState({ playingId: messageId, paused: true, positionMs: this.state.positionMs, durationMs: this.state.durationMs, completedId: 0 });
      }
      return;
    }
    this.play(messageId, path, fallbackDurationSec);
  }

  private play(messageId: number, path: string, fallbackDurationSec: number): void {
    this.stop();
    media.createAVPlayer().then((player: media.AVPlayer) => {
      this.player = player;
      this.file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      this.setState({ playingId: messageId, paused: false, positionMs: 0, durationMs: fallbackDurationSec * 1000, completedId: 0 });
      player.on('stateChange', (state: string) => {
        if (state === 'initialized') {
          player.prepare();
        } else if (state === 'prepared') {
          const d = player.duration;
          if (d > 0) {
            this.setState({ playingId: messageId, paused: false, positionMs: 0, durationMs: d, completedId: 0 });
          }
          player.play();
        } else if (state === 'completed') {
          this.stop(messageId);
        }
      });
      player.on('timeUpdate', (timeMs: number) => {
        if (this.state.playingId === messageId) {
          this.setState({ playingId: messageId, paused: this.state.paused, positionMs: timeMs, durationMs: this.state.durationMs, completedId: 0 });
        }
      });
      player.url = `fd://${this.file.fd}`;
    }).catch((e: Object) => {
      console.error(`VoicePlayback.play failed: ${JSON.stringify(e)}`);
      this.stop();
    });
  }

  stop(completedId: number = 0): void {
    if (this.player !== null) {
      const p = this.player;
      this.player = null;
      p.release().catch((e: Object) => {
        console.error(`VoicePlayback.stop release failed: ${JSON.stringify(e)}`);
      });
    }
    if (this.file !== null) {
      try {
        fs.closeSync(this.file);
      } catch (e) {
        console.error(`VoicePlayback.stop close failed: ${e}`);
      }
      this.file = null;
    }
    this.setState({ playingId: 0, paused: false, positionMs: 0, durationMs: 0, completedId });
  }

  private setState(s: VoiceState): void {
    this.state = s;
    for (const l of this.listeners) {
      l(s);
    }
  }
}

let instance: VoicePlayback | null = null;

export function getVoicePlayback(): VoicePlayback {
  if (instance === null) {
    instance = new VoicePlayback();
  }
  return instance;
}

import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

// One live-room page can be active at a time. Serialize changes because
// start/update/stop are asynchronous system calls and a quick mute + back
// gesture must not leave an orphan notification or an incorrect recording
// background mode behind.
class LiveStreamBackgroundTask {
  private context: common.UIAbilityContext | null = null;
  private started: boolean = false;
  private wantsRunning: boolean = false;
  private recording: boolean = false;
  private operation: Promise<void> = Promise.resolve();

  start(context: common.UIAbilityContext, recording: boolean): void {
    this.context = context;
    this.wantsRunning = true;
    this.recording = recording;
    this.enqueue(async (): Promise<void> => {
      if (!this.wantsRunning || this.context === null) { return; }
      if (this.started) {
        await this.updateModes();
        return;
      }
      const current = this.context;
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: current.abilityInfo.bundleName,
          abilityName: current.abilityInfo.name
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 8295,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(current, this.modes(), agent);
      this.started = true;
      console.info(`[LiveStreamBackgroundTask] started modes=${this.modes().join(',')}`);
      if (!this.wantsRunning) { await this.stopCurrent(); }
    });
  }

  setRecording(recording: boolean): void {
    if (this.recording === recording) { return; }
    this.recording = recording;
    this.enqueue(async (): Promise<void> => {
      if (this.started && this.wantsRunning) { await this.updateModes(); }
    });
  }

  stop(): void {
    this.wantsRunning = false;
    this.enqueue(async (): Promise<void> => this.stopCurrent());
  }

  private modes(): string[] {
    return this.recording ? ['audioPlayback', 'audioRecording'] : ['audioPlayback'];
  }

  private async updateModes(): Promise<void> {
    if (this.context === null) { return; }
    await backgroundTaskManager.updateBackgroundRunning(this.context, this.modes());
    console.info(`[LiveStreamBackgroundTask] updated modes=${this.modes().join(',')}`);
  }

  private async stopCurrent(): Promise<void> {
    if (!this.started || this.context === null) { return; }
    await backgroundTaskManager.stopBackgroundRunning(this.context);
    this.started = false;
    console.info('[LiveStreamBackgroundTask] stopped');
  }

  private enqueue(action: () => Promise<void>): void {
    this.operation = this.operation.then(action).catch((error: Error): void => {
      console.error(`[LiveStreamBackgroundTask] ${error.message}`);
    });
  }
}

export const liveStreamBackgroundTask: LiveStreamBackgroundTask = new LiveStreamBackgroundTask();

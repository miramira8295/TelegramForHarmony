import { common } from '@kit.AbilityKit';
import { promptAction, window } from '@kit.ArkUI';

const EXIT_RED: string = '#E64646';
const LEAVE_BLUE: string = '#3E8BFF';
const SECONDARY_TEXT: string = '#8E8E93';

export function confirmLeaveLiveStream(onConfirm: () => void): void {
  promptAction.showDialog({
    title: '退出直播？',
    message: '退出后将停止接收当前直播的音视频，可从频道或群组中重新进入。',
    buttons: [
      { text: '继续观看', color: SECONDARY_TEXT },
      { text: '退出直播', color: EXIT_RED }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): void => {
    if (result.index === 1) { onConfirm(); }
  }).catch((): void => {});
}

export function confirmAdminLeaveLiveStream(
  onLeave: () => void, onEnd: () => void
): void {
  promptAction.showDialog({
    title: '管理直播',
    message: '退出直播只会断开本机；结束直播会关闭直播间并断开所有成员。',
    buttons: [
      { text: '继续直播', color: SECONDARY_TEXT },
      { text: '退出直播', color: LEAVE_BLUE },
      { text: '结束直播', color: EXIT_RED }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): void => {
    if (result.index === 1) {
      onLeave();
    } else if (result.index === 2) {
      onEnd();
    }
  }).catch((): void => {});
}

export function setLiveStreamFullscreen(
  context: common.UIAbilityContext, fullscreen: boolean, videoAspectRatio: number = 0
): void {
  window.getLastWindow(context).then((mainWindow: window.Window): void => {
    let orientation = window.Orientation.PORTRAIT;
    if (fullscreen) {
      // Follow the decoded picture instead of forcing every live stream into
      // landscape. Until the first frame arrives, respect the device sensor.
      orientation = videoAspectRatio > 1.08
        ? window.Orientation.AUTO_ROTATION_LANDSCAPE
        : (videoAspectRatio > 0
          ? window.Orientation.AUTO_ROTATION_PORTRAIT
          : window.Orientation.AUTO_ROTATION);
    }
    mainWindow.setPreferredOrientation(
      orientation
    ).catch((caught: Error): void => {
      console.error(`LiveViewerUi.setPreferredOrientation failed: ${caught.message}`);
    });
  }).catch((caught: Error): void => {
    console.error(`LiveViewerUi.getLastWindow failed: ${caught.message}`);
  });
}

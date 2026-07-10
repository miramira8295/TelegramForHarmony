import { common, Want, wantConstant } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';

// Open a downloaded local file with whatever system app handles its type.
export function openLocalFile(context: common.UIAbilityContext, path: string, mimeType: string): void {
  if (path === '' || context === undefined) {
    return;
  }
  try {
    const uri = fileUri.getUriFromPath(path);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };
    if (mimeType !== '') {
      want.type = mimeType;
    }
    context.startAbility(want).catch((e: Object) => {
      console.error(`openLocalFile failed for ${path}: ${JSON.stringify(e)}`);
    });
  } catch (e) {
    console.error(`openLocalFile uri conversion failed for ${path}: ${e}`);
  }
}

import { common, Want } from '@kit.AbilityKit';

// Open a tapped link (web URL / mailto / t.me) in the appropriate system app.
export function openUrl(context: common.UIAbilityContext, url: string): void {
  if (url === '' || context === undefined) {
    return;
  }
  const want: Want = {
    action: 'ohos.want.action.viewData',
    uri: url
  };
  context.startAbility(want).catch((e: Object) => {
    console.error(`openUrl failed for ${url}: ${JSON.stringify(e)}`);
  });
}

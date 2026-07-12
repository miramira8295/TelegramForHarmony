import { common, Want } from '@kit.AbilityKit';

// Open a tapped link (web URL / mailto / t.me) in the appropriate system app.
export function openUrl(context: common.UIAbilityContext, url: string): void {
  if (url === '' || context === undefined) {
    return;
  }
  // Bare web addresses (www.example.com / example.com, no scheme) can't be
  // opened by viewData as-is — prepend https:// so the browser recognizes them.
  // mailto:/tel:/existing-scheme links are left untouched.
  let target = url.trim();
  if (target.indexOf('://') < 0 && target.indexOf('mailto:') !== 0 && target.indexOf('tel:') !== 0) {
    target = `https://${target}`;
  }
  const want: Want = {
    action: 'ohos.want.action.viewData',
    uri: target
  };
  context.startAbility(want).catch((e: Object) => {
    console.error(`openUrl failed for ${target}: ${JSON.stringify(e)}`);
  });
}

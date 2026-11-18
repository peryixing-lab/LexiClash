import { ImmersiveWindowController } from '../common/ImmersiveWindowController';
import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { BackgroundKeepAlive } from '../core/BackgroundKeepAlive';
import { RuntimeDiagnostics } from '../core/RuntimeDiagnostics';
import { AppStateStore } from '../store/AppStateStore';
import { VideoEditorService } from '../core/VideoEditorService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    RuntimeDiagnostics.watch(this.context.filesDir, 'ui');
    RuntimeDiagnostics.record(`UI created: lastExitReason=${launchParam.lastExitReason} lastExitMessage=${launchParam.lastExitMessage} detail=${JSON.stringify(launchParam.lastExitDetailInfo)}`);
    BackgroundKeepAlive.setAbilityContext(this.context);
    AppStateStore.getInstance().initialize(this.context.filesDir);
    AppStorage.setOrCreate<boolean>('lexiSystemDark',
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    VideoEditorService.getInstance().cancel('应用已关闭，导出已取消');
    BackgroundKeepAlive.setAbilityContext(null);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      ImmersiveWindowController.attach(windowStage.getMainWindowSync(), this.context);
      windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    ImmersiveWindowController.detach();
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onConfigurationUpdate(config: Configuration): void {
    AppStorage.setOrCreate<boolean>('lexiSystemDark',
      config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onForeground(): void {
    RuntimeDiagnostics.replayRecent();
    RuntimeDiagnostics.record(`UI foreground: keepAlive=${BackgroundKeepAlive.getLastStatus()}`);
    AppStateStore.getInstance().setAppInForeground(true);
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    VideoEditorService.getInstance().onAppBackground();
    RuntimeDiagnostics.record(`UI background: keepAlive=${BackgroundKeepAlive.getLastStatus()} active=${BackgroundKeepAlive.isActive()}`);
    AppStateStore.getInstance().setAppInForeground(false);
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}

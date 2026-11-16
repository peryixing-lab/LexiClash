// BackgroundKeepAlive.ets — HarmonyOS Continuous Task Keep-Alive for Persistent VPN
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RuntimeDiagnostics } from './RuntimeDiagnostics';

const DOMAIN = 0xF1C1;

export class BackgroundKeepAlive {
  private static abilityContext: common.UIAbilityContext | null = null;
  private static active: boolean = false;
  private static starting: boolean = false;
  private static continuousTaskId: number = -1;
  private static refreshTimerId: number = -1;
  private static cancelListening: boolean = false;
  private static bundleName: string = 'com.lovexjy.lexiclash';
  private static abilityName: string = 'EntryAbility';
  private static lastStatus: string = 'idle';

  private static cancelListener: (info: backgroundTaskManager.ContinuousTaskCancelInfo) => void =
    (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      BackgroundKeepAlive.active = false;
      BackgroundKeepAlive.continuousTaskId = -1;
      BackgroundKeepAlive.lastStatus = `canceled:${info.reason}`;
      RuntimeDiagnostics.record(`Continuous task canceled by OS reason=${info.reason} id=${info.id}`);
    };

  static setAbilityContext(context: common.UIAbilityContext | null): void {
    BackgroundKeepAlive.abilityContext = context;
    if (context === null) {
      BackgroundKeepAlive.clearRefreshTimer();
    }
  }

  static isActive(): boolean {
    return BackgroundKeepAlive.active;
  }

  static getLastStatus(): string {
    return BackgroundKeepAlive.lastStatus;
  }

  private static clearRefreshTimer(): void {
    if (BackgroundKeepAlive.refreshTimerId !== -1) {
      clearInterval(BackgroundKeepAlive.refreshTimerId);
      BackgroundKeepAlive.refreshTimerId = -1;
    }
  }

  private static scheduleKeepAliveRefresh(): void {
    BackgroundKeepAlive.clearRefreshTimer();
    // Periodically verify/re-acquire DATA_TRANSFER continuous task under the 10-minute idle threshold.
    BackgroundKeepAlive.refreshTimerId = setInterval((): void => {
      if (BackgroundKeepAlive.abilityContext === null) {
        BackgroundKeepAlive.clearRefreshTimer();
        return;
      }
      BackgroundKeepAlive.verifyAndRenewAsync();
    }, 8 * 60 * 1000);
  }

  private static async verifyAndRenewAsync(): Promise<void> {
    const ctx: common.UIAbilityContext | null = BackgroundKeepAlive.abilityContext;
    if (ctx === null) {
      return;
    }
    try {
      const list: backgroundTaskManager.ContinuousTaskInfo[] =
        await backgroundTaskManager.getAllContinuousTasks(ctx);
      if (Array.isArray(list) && list.length > 0) {
        BackgroundKeepAlive.active = true;
        return;
      }
    } catch (_err) {
      // Fallback to direct re-request below.
    }
    BackgroundKeepAlive.active = false;
    await BackgroundKeepAlive.start(BackgroundKeepAlive.bundleName, BackgroundKeepAlive.abilityName);
  }

  private static async buildLaunchAgent(bundleName: string, abilityName: string): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [{ bundleName: bundleName, abilityName: abilityName }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(info);
  }

  static async start(bundleName: string = 'com.lovexjy.lexiclash', abilityName: string = 'EntryAbility'): Promise<void> {
    BackgroundKeepAlive.bundleName = bundleName;
    BackgroundKeepAlive.abilityName = abilityName;
    const ctx: common.UIAbilityContext | null = BackgroundKeepAlive.abilityContext;
    if (ctx === null || BackgroundKeepAlive.active || BackgroundKeepAlive.starting) {
      return;
    }
    BackgroundKeepAlive.starting = true;
    try {
      if (!BackgroundKeepAlive.cancelListening) {
        try {
          backgroundTaskManager.on('continuousTaskCancel', BackgroundKeepAlive.cancelListener);
          BackgroundKeepAlive.cancelListening = true;
        } catch (_listenErr) {
          BackgroundKeepAlive.cancelListening = false;
        }
      }
      const agent: WantAgent = await BackgroundKeepAlive.buildLaunchAgent(bundleName, abilityName);
      // Prefer MODE_TASK_KEEPING when supported (2in1 PC without ACL); fallback to DATA_TRANSFER on Phone/Tablet.
      let usedTaskKeeping: boolean = false;
      try {
        const req: backgroundTaskManager.ContinuousTaskRequest = new backgroundTaskManager.ContinuousTaskRequest();
        req.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_TASK_KEEPING];
        req.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_NORMAL_NOTIFICATION];
        req.wantAgent = agent;
        if (req.isModeSupported()) {
          const notif: backgroundTaskManager.ContinuousTaskNotification =
            await backgroundTaskManager.startBackgroundRunning(ctx, req);
          const taskId: number = notif.continuousTaskId ?? 0;
          BackgroundKeepAlive.continuousTaskId = taskId;
          usedTaskKeeping = true;
          BackgroundKeepAlive.lastStatus = 'running:taskKeeping';
          hilog.info(DOMAIN, 'LexiKeepAlive', 'Started MODE_TASK_KEEPING id=%{public}d', taskId);
        }
      } catch (_taskKeepErr) {
        usedTaskKeeping = false;
      }

      if (!usedTaskKeeping) {
        await backgroundTaskManager.startBackgroundRunning(
          ctx,
          backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
          agent
        );
        BackgroundKeepAlive.continuousTaskId = 0;
        BackgroundKeepAlive.lastStatus = 'running:dataTransfer';
        hilog.info(DOMAIN, 'LexiKeepAlive', 'Started DATA_TRANSFER continuous background task');
      }

      BackgroundKeepAlive.active = true;
      BackgroundKeepAlive.scheduleKeepAliveRefresh();
      RuntimeDiagnostics.record(`KeepAlive started (${BackgroundKeepAlive.lastStatus})`);
    } catch (err) {
      BackgroundKeepAlive.active = false;
      BackgroundKeepAlive.lastStatus = `error:${String(err)}`;
      hilog.warn(DOMAIN, 'LexiKeepAlive', 'Continuous task unavailable: %{public}s', String(err));
      RuntimeDiagnostics.record(`KeepAlive start failed: ${String(err)}`);
    } finally {
      BackgroundKeepAlive.starting = false;
    }
  }

  static async stop(): Promise<void> {
    BackgroundKeepAlive.clearRefreshTimer();
    const ctx: common.UIAbilityContext | null = BackgroundKeepAlive.abilityContext;
    const wasActive: boolean = BackgroundKeepAlive.active;
    BackgroundKeepAlive.active = false;
    BackgroundKeepAlive.continuousTaskId = -1;
    BackgroundKeepAlive.lastStatus = 'stopped';
    if (ctx === null || !wasActive) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx);
      hilog.info(DOMAIN, 'LexiKeepAlive', 'Stopped continuous background task');
    } catch (err) {
      hilog.warn(DOMAIN, 'LexiKeepAlive', 'Stop continuous task warning: %{public}s', String(err));
    }
  }
}

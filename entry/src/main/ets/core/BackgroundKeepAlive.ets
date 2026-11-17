// BackgroundKeepAlive.ets — HarmonyOS Continuous Task Keep-Alive for Persistent VPN
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RuntimeDiagnostics } from './RuntimeDiagnostics';

const DOMAIN = 0xF1C1;

export class BackgroundKeepAlive {
  private static abilityContext: common.UIAbilityContext | null = null;
  private static active: boolean = false;
  private static pending: Promise<void> = Promise.resolve();
  private static generation: number = 0;
  private static continuousTaskId: number = -1;
  private static refreshTimerId: number = -1;
  private static cancelListening: boolean = false;
  private static lastStatus: string = 'idle';

  private static cancelListener: (info: backgroundTaskManager.ContinuousTaskCancelInfo) => void =
    (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      if (info.id !== BackgroundKeepAlive.continuousTaskId) { return; }
      BackgroundKeepAlive.clearRefreshTimer();
      BackgroundKeepAlive.active = false;
      BackgroundKeepAlive.continuousTaskId = -1;
      BackgroundKeepAlive.lastStatus = `canceled:${info.reason}`;
      RuntimeDiagnostics.record(`Continuous task canceled by OS reason=${info.reason} detailedReason=${info.detailedReason} id=${info.id}`);
    };

  static setAbilityContext(context: common.UIAbilityContext | null): void {
    BackgroundKeepAlive.abilityContext = context;
    if (context === null) {
      BackgroundKeepAlive.clearRefreshTimer();
      BackgroundKeepAlive.active = false;
      BackgroundKeepAlive.continuousTaskId = -1;
    }
  }

  static isActive(): boolean {
    return BackgroundKeepAlive.active;
  }

  static getLastStatus(): string {
    return BackgroundKeepAlive.lastStatus;
  }

  private static clearRefreshTimer(): void {
    BackgroundKeepAlive.generation++;
    if (BackgroundKeepAlive.refreshTimerId !== -1) {
      clearInterval(BackgroundKeepAlive.refreshTimerId);
      BackgroundKeepAlive.refreshTimerId = -1;
    }
  }

  private static scheduleProgress(notificationId: number, readBytes: () => Promise<number>): void {
    BackgroundKeepAlive.clearRefreshTimer();
    const generation = BackgroundKeepAlive.generation;
    let updating = false;
    const publish = async (): Promise<void> => {
      if (updating || generation !== BackgroundKeepAlive.generation) { return; }
      updating = true;
      try {
        const bytes = await readBytes();
        if (generation !== BackgroundKeepAlive.generation || !Number.isFinite(bytes) || bytes < 0) { return; }
        const transferred = `已传输 ${(bytes / 1048576).toFixed(2)} MiB`;
        await notificationManager.publish({
          id: notificationId,
          notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
          content: {
            notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
            systemLiveView: {
              typeCode: 8, title: 'LexiClash VPN', text: transferred,
              progress: { currentValue: Math.floor(bytes / 1024), isPercentage: false }
            }
          }
        });
      } catch (err) {
        RuntimeDiagnostics.record(`VPN transfer notification update failed: ${String(err)}`);
      } finally {
        updating = false;
      }
    };
    publish();
    BackgroundKeepAlive.refreshTimerId = setInterval((): void => { publish(); }, 2 * 60 * 1000);
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

  static start(bundleName: string, abilityName: string, readBytes: () => Promise<number>): Promise<void> {
    BackgroundKeepAlive.pending = BackgroundKeepAlive.pending.then(() =>
      BackgroundKeepAlive.startTask(bundleName, abilityName, readBytes));
    return BackgroundKeepAlive.pending;
  }

  private static async startTask(bundleName: string, abilityName: string, readBytes: () => Promise<number>): Promise<void> {
    const ctx = BackgroundKeepAlive.abilityContext;
    if (ctx === null || BackgroundKeepAlive.active) { return; }
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
        const request = new backgroundTaskManager.ContinuousTaskRequest();
        request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER];
        request.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_LIVE_VIEW_NOTIFICATION];
        request.wantAgent = agent;
        const task = await backgroundTaskManager.startBackgroundRunning(ctx, request);
        BackgroundKeepAlive.continuousTaskId = task.continuousTaskId ?? -1;
        if (ctx === BackgroundKeepAlive.abilityContext) {
          BackgroundKeepAlive.scheduleProgress(task.notificationId, readBytes);
        }
        BackgroundKeepAlive.lastStatus = 'running:dataTransfer';
        hilog.info(DOMAIN, 'LexiKeepAlive', 'Started DATA_TRANSFER continuous background task');
      }

      if (ctx !== BackgroundKeepAlive.abilityContext) {
        await backgroundTaskManager.stopBackgroundRunning(ctx);
        return;
      }
      BackgroundKeepAlive.active = true;
      RuntimeDiagnostics.record(`KeepAlive started (${BackgroundKeepAlive.lastStatus})`);
    } catch (err) {
      BackgroundKeepAlive.active = false;
      BackgroundKeepAlive.lastStatus = `error:${String(err)}`;
      hilog.warn(DOMAIN, 'LexiKeepAlive', 'Continuous task unavailable: %{public}s', String(err));
      RuntimeDiagnostics.record(`KeepAlive start failed: ${String(err)}`);
    }
  }

  static stop(): Promise<void> {
    BackgroundKeepAlive.pending = BackgroundKeepAlive.pending.then(() => BackgroundKeepAlive.stopTask());
    return BackgroundKeepAlive.pending;
  }

  private static async stopTask(): Promise<void> {
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

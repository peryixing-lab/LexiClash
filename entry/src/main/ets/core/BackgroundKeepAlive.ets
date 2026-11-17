import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { RuntimeDiagnostics } from './RuntimeDiagnostics';

export class BackgroundKeepAlive {
  private static abilityContext: common.UIAbilityContext | null = null;
  private static active: boolean = false;
  private static pending: Promise<void> = Promise.resolve();
  private static generation: number = 0;
  private static continuousTaskId: number = -1;
  private static refreshTimerId: number = -1;
  private static cancelListening: boolean = false;
  private static lastStatus: string = 'idle';
  private static lastError: string = '';
  private static userCancelled: boolean = false;

  private static cancelListener: (info: backgroundTaskManager.ContinuousTaskCancelInfo) => void =
    (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      if (info.id !== BackgroundKeepAlive.continuousTaskId) { return; }
      BackgroundKeepAlive.clearRefreshTimer();
      BackgroundKeepAlive.active = false;
      BackgroundKeepAlive.continuousTaskId = -1;
      BackgroundKeepAlive.lastStatus = `canceled:${info.reason}`;
      BackgroundKeepAlive.userCancelled = info.reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL ||
        info.detailedReason === backgroundTaskManager.ContinuousTaskDetailedCancelReason.USER_CANCEL_REMOVE_NOTIFICATION;
      BackgroundKeepAlive.lastError = BackgroundKeepAlive.userCancelled
        ? '后台连接通知已被关闭，请重新连接以恢复后台运行'
        : `后台运行已被系统停止，请回到应用重新连接（${info.detailedReason ?? info.reason}）`;
      RuntimeDiagnostics.record(`Continuous task canceled by OS reason=${info.reason} detailedReason=${info.detailedReason} id=${info.id}`);
    };

  static setAbilityContext(context: common.UIAbilityContext | null): void {
    if (context === BackgroundKeepAlive.abilityContext) { return; }
    BackgroundKeepAlive.clearRefreshTimer();
    BackgroundKeepAlive.abilityContext = context;
    BackgroundKeepAlive.active = false;
    BackgroundKeepAlive.continuousTaskId = -1;
  }

  static isActive(): boolean {
    return BackgroundKeepAlive.active;
  }

  static getLastStatus(): string {
    return BackgroundKeepAlive.lastStatus;
  }

  static getLastError(): string {
    return BackgroundKeepAlive.lastError;
  }

  private static describeError(error: BusinessError): string {
    return `${error.code ?? ''} ${error.message || String(error)}`.trim();
  }

  private static clearRefreshTimer(): void {
    BackgroundKeepAlive.generation++;
    if (BackgroundKeepAlive.refreshTimerId !== -1) {
      clearInterval(BackgroundKeepAlive.refreshTimerId);
      BackgroundKeepAlive.refreshTimerId = -1;
    }
  }

  private static async publishProgress(notificationId: number, readBytes: () => Promise<number>,
    generation: number): Promise<void> {
    const bytes: number = await readBytes();
    if (generation !== BackgroundKeepAlive.generation || !BackgroundKeepAlive.active) { return; }
    if (!Number.isFinite(bytes) || bytes < 0) { throw new Error('VPN 流量统计无效'); }
    const transferred: string = `已传输 ${(bytes / 1048576).toFixed(2)} MiB`;
    await notificationManager.publish({
      id: notificationId,
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: {
          typeCode: 8, title: 'LexiClash VPN', text: transferred,
          progress: { currentValue: Math.floor(bytes / 1024), isPercentage: false }
        }
      },
      // progressValue is completion percentage, not a byte counter. A VPN is
      // an open-ended transfer; keep it unfinished and show actual bytes above.
      template: {
        name: 'downloadTemplate',
        data: { title: 'LexiClash VPN', fileName: transferred, progressValue: 0 }
      }
    });
    if (generation !== BackgroundKeepAlive.generation) { return; }
    BackgroundKeepAlive.lastError = '';
    RuntimeDiagnostics.record(`VPN transfer progress published id=${notificationId} bytes=${Math.floor(bytes)}`);
  }

  private static scheduleProgress(notificationId: number, readBytes: () => Promise<number>, generation: number): void {
    let updating: boolean = false;
    const publish = async (): Promise<void> => {
      if (updating || generation !== BackgroundKeepAlive.generation) { return; }
      updating = true;
      try {
        await BackgroundKeepAlive.publishProgress(notificationId, readBytes, generation);
      } catch (err) {
        if (generation !== BackgroundKeepAlive.generation) { return; }
        const detail: string = BackgroundKeepAlive.describeError(err as BusinessError);
        BackgroundKeepAlive.lastError = `后台连接状态更新失败：${detail}`;
        RuntimeDiagnostics.record(`VPN transfer notification update failed: ${detail}`);
      } finally {
        updating = false;
      }
    };
    BackgroundKeepAlive.refreshTimerId = setInterval((): void => { publish(); }, 60 * 1000);
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

  static start(bundleName: string, abilityName: string, readBytes: () => Promise<number>,
    userInitiated: boolean = true): Promise<void> {
    const generation: number = BackgroundKeepAlive.generation;
    const operation: Promise<void> = BackgroundKeepAlive.pending.then(() => {
      if (generation !== BackgroundKeepAlive.generation) { throw new Error('后台运行申请已取消'); }
      if (userInitiated) { BackgroundKeepAlive.userCancelled = false; }
      if (BackgroundKeepAlive.userCancelled) { throw new Error(BackgroundKeepAlive.lastError); }
      return BackgroundKeepAlive.startTask(bundleName, abilityName, readBytes);
    });
    // Keep the caller's rejection without poisoning subsequent stop/start operations.
    BackgroundKeepAlive.pending = operation.catch((): void => {});
    return operation;
  }

  private static async startTask(bundleName: string, abilityName: string, readBytes: () => Promise<number>): Promise<void> {
    const ctx: common.UIAbilityContext | null = BackgroundKeepAlive.abilityContext;
    if (BackgroundKeepAlive.active) { return; }
    if (ctx === null) {
      BackgroundKeepAlive.lastError = '无法启用后台连接：应用窗口尚未就绪';
      throw new Error(BackgroundKeepAlive.lastError);
    }
    const generation: number = BackgroundKeepAlive.generation;
    let taskId: number = -1;
    try {
      if (!BackgroundKeepAlive.cancelListening) {
        backgroundTaskManager.on('continuousTaskCancel', BackgroundKeepAlive.cancelListener);
        BackgroundKeepAlive.cancelListening = true;
      }
      const agent: WantAgent = await BackgroundKeepAlive.buildLaunchAgent(bundleName, abilityName);
      const request: backgroundTaskManager.ContinuousTaskRequest = new backgroundTaskManager.ContinuousTaskRequest();
      request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER];
      request.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_LIVE_VIEW_NOTIFICATION];
      request.wantAgent = agent;
      const task: backgroundTaskManager.ContinuousTaskNotification =
        await backgroundTaskManager.startBackgroundRunning(ctx, request);
      taskId = task.continuousTaskId ?? -1;
      if (!Number.isFinite(taskId) || taskId < 0 || !Number.isFinite(task.notificationId)) {
        throw new Error('系统未返回有效的后台任务或通知标识');
      }
      if (ctx !== BackgroundKeepAlive.abilityContext || generation !== BackgroundKeepAlive.generation) {
        throw new Error('后台运行申请已取消');
      }
      BackgroundKeepAlive.continuousTaskId = taskId;
      BackgroundKeepAlive.active = true;
      await BackgroundKeepAlive.publishProgress(task.notificationId, readBytes, generation);
      if (generation !== BackgroundKeepAlive.generation || !BackgroundKeepAlive.active) {
        throw new Error('后台运行申请已取消');
      }
      BackgroundKeepAlive.scheduleProgress(task.notificationId, readBytes, generation);
      BackgroundKeepAlive.lastStatus = 'running:dataTransfer';
      RuntimeDiagnostics.record(`KeepAlive started (running:dataTransfer) id=${taskId} notificationId=${task.notificationId}`);
    } catch (err) {
      if (BackgroundKeepAlive.continuousTaskId === taskId) {
        BackgroundKeepAlive.active = false;
        BackgroundKeepAlive.continuousTaskId = -1;
      }
      if (taskId >= 0) {
        try { await backgroundTaskManager.stopBackgroundRunning(ctx, taskId); } catch (_stopErr) {}
      }
      const detail: string = BackgroundKeepAlive.describeError(err as BusinessError);
      if (generation === BackgroundKeepAlive.generation) {
        BackgroundKeepAlive.lastStatus = `error:${detail}`;
        BackgroundKeepAlive.lastError = `无法启用后台连接：${detail}`;
      }
      RuntimeDiagnostics.record(`KeepAlive start failed: ${detail}`);
      throw new Error(`无法启用后台连接：${detail}`);
    }
  }

  static stop(): Promise<void> {
    // Invalidate queued starts and in-flight progress reads immediately.
    BackgroundKeepAlive.clearRefreshTimer();
    BackgroundKeepAlive.pending = BackgroundKeepAlive.pending.then(() => BackgroundKeepAlive.stopTask());
    return BackgroundKeepAlive.pending;
  }

  private static async stopTask(): Promise<void> {
    const ctx: common.UIAbilityContext | null = BackgroundKeepAlive.abilityContext;
    const taskId: number = BackgroundKeepAlive.continuousTaskId;
    BackgroundKeepAlive.active = false;
    BackgroundKeepAlive.continuousTaskId = -1;
    BackgroundKeepAlive.lastStatus = 'stopped';
    BackgroundKeepAlive.lastError = '';
    BackgroundKeepAlive.userCancelled = false;
    if (ctx === null || taskId < 0) { return; }
    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx, taskId);
      RuntimeDiagnostics.record(`KeepAlive stopped id=${taskId}`);
    } catch (err) {
      RuntimeDiagnostics.record(`Stop continuous task warning: ${BackgroundKeepAlive.describeError(err as BusinessError)}`);
    }
  }
}

import { abilityAccessCtrl, bundleManager, common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError, deviceInfo, runningLock } from '@kit.BasicServicesKit';
import { RuntimeDiagnostics } from './RuntimeDiagnostics';

export type LexiKeepAliveMode = 'none' | 'specialScenario' | 'taskKeeping' | 'dataTransfer';

export class BackgroundKeepAlive {
  private static readonly AUTH_TIMEOUT_MS: number = 45000;
  private static readonly RUNNING_LOCK_WINDOW_MS: number = 5 * 60 * 1000;
  private static readonly RELAY_SUSPEND_TIMEOUT_MS: number = 10 * 1000;

  private static abilityContext: common.UIAbilityContext | null = null;
  private static active: boolean = false;
  private static activeMode: LexiKeepAliveMode = 'none';
  private static activeSlotType: notificationManager.SlotType = notificationManager.SlotType.LIVE_VIEW;
  private static activeContentType: notificationManager.ContentType = notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW;
  private static pending: Promise<void> = Promise.resolve();
  private static generation: number = 0;
  private static continuousTaskId: number = -1;
  private static notificationId: number = -1;
  private static refreshTimerId: number = -1;
  private static cancelListening: boolean = false;
  private static suspendListening: boolean = false;
  private static activeListening: boolean = false;
  private static lastStatus: string = 'idle';
  private static lastError: string = '';
  private static userCancelled: boolean = false;
  private static specialScenarioUnauthorized: boolean = false;
  private static lastPublishedBytes: number = 0;
  private static progressTick: number = 0;
  private static idleLock: runningLock.RunningLock | null = null;
  private static relaySuspendRequestId: number = -1;
  private static relaySuspendTimerId: number = -1;
  private static onSystemCancel: (() => void) | null = null;
  private static abortPendingConsent: (() => void) | null = null;

  static setSystemCancelHandler(handler: (() => void) | null): void {
    BackgroundKeepAlive.onSystemCancel = handler;
  }

  private static suspendListener: (info: backgroundTaskManager.ContinuousTaskSuspendInfo) => void =
    (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
      if (info.continuousTaskId !== BackgroundKeepAlive.continuousTaskId || !info.suspendState) { return; }
      const suspendedTaskId: number = BackgroundKeepAlive.continuousTaskId;
      const ctx: common.UIAbilityContext | null = BackgroundKeepAlive.abilityContext;
      const unauthorizedReason: number = Number(
        backgroundTaskManager.ContinuousTaskSuspendReason?.SYSTEM_SUSPEND_USER_UNAUTHORIZED ?? 19
      );
      if (Number(info.suspendReason) === unauthorizedReason) {
        BackgroundKeepAlive.specialScenarioUnauthorized = true;
      }
      BackgroundKeepAlive.clearRefreshTimer();
      BackgroundKeepAlive.active = false;
      BackgroundKeepAlive.activeMode = 'none';
      BackgroundKeepAlive.continuousTaskId = -1;
      BackgroundKeepAlive.notificationId = -1;
      BackgroundKeepAlive.progressTick = 0;
      BackgroundKeepAlive.releaseRunningLock();
      BackgroundKeepAlive.acquireRelaySuspendDelay('keepalive-suspend-relay');
      BackgroundKeepAlive.lastStatus = `suspended:${info.suspendReason}`;
      BackgroundKeepAlive.lastError = `后台运行已被系统挂起，正在尝试恢复（${info.suspendReason}）`;
      RuntimeDiagnostics.record(
        `Continuous task suspended by OS id=${suspendedTaskId} state=${info.suspendState} reason=${info.suspendReason}`
      );
      if (ctx !== null && suspendedTaskId >= 0) {
        BackgroundKeepAlive.pending = BackgroundKeepAlive.pending.then(async (): Promise<void> => {
          try {
            await backgroundTaskManager.stopBackgroundRunning(ctx, suspendedTaskId);
          } catch (_stopErr) {
            // Ignore if the system already reclaimed the suspended task.
          }
        });
      }
      if (BackgroundKeepAlive.onSystemCancel !== null) {
        try { BackgroundKeepAlive.onSystemCancel(); } catch (_err) {}
      }
    };

  private static activeListener: (info: backgroundTaskManager.ContinuousTaskActiveInfo) => void =
    (info: backgroundTaskManager.ContinuousTaskActiveInfo): void => {
      if (info.id !== BackgroundKeepAlive.continuousTaskId) { return; }
      RuntimeDiagnostics.record(`Continuous task activated by OS id=${info.id}`);
    };

  private static cancelListener: (info: backgroundTaskManager.ContinuousTaskCancelInfo) => void =
    (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      if (info.id !== BackgroundKeepAlive.continuousTaskId) { return; }
      const unauthorizedDetailed: number = Number(
        backgroundTaskManager.ContinuousTaskDetailedCancelReason?.SYSTEM_CANCEL_USER_UNAUTHORIZED ?? 14
      );
      if (Number(info.detailedReason) === unauthorizedDetailed) {
        BackgroundKeepAlive.specialScenarioUnauthorized = true;
      }
      BackgroundKeepAlive.clearRefreshTimer();
      BackgroundKeepAlive.active = false;
      BackgroundKeepAlive.activeMode = 'none';
      BackgroundKeepAlive.continuousTaskId = -1;
      BackgroundKeepAlive.notificationId = -1;
      BackgroundKeepAlive.progressTick = 0;
      BackgroundKeepAlive.releaseRunningLock();
      BackgroundKeepAlive.releaseRelaySuspendDelay();
      BackgroundKeepAlive.lastStatus = `canceled:${info.reason}`;
      BackgroundKeepAlive.userCancelled = info.reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL ||
        info.detailedReason === backgroundTaskManager.ContinuousTaskDetailedCancelReason.USER_CANCEL_REMOVE_NOTIFICATION;
      BackgroundKeepAlive.lastError = BackgroundKeepAlive.userCancelled
        ? '后台连接通知已被关闭，请重新连接以恢复后台运行'
        : `后台运行已被系统停止，请回到应用重新连接（${info.detailedReason ?? info.reason}）`;
      RuntimeDiagnostics.record(`Continuous task canceled by OS reason=${info.reason} detailedReason=${info.detailedReason} id=${info.id}`);
      if (!BackgroundKeepAlive.userCancelled && BackgroundKeepAlive.onSystemCancel !== null) {
        try { BackgroundKeepAlive.onSystemCancel(); } catch (_err) {}
      }
    };

  static setAbilityContext(context: common.UIAbilityContext | null): void {
    if (context === BackgroundKeepAlive.abilityContext) { return; }
    BackgroundKeepAlive.clearRefreshTimer();
    BackgroundKeepAlive.abilityContext = context;
    BackgroundKeepAlive.active = false;
    BackgroundKeepAlive.activeMode = 'none';
    BackgroundKeepAlive.continuousTaskId = -1;
    BackgroundKeepAlive.notificationId = -1;
    BackgroundKeepAlive.lastPublishedBytes = 0;
    BackgroundKeepAlive.progressTick = 0;
    BackgroundKeepAlive.specialScenarioUnauthorized = false;
    BackgroundKeepAlive.releaseRunningLock();
    BackgroundKeepAlive.releaseRelaySuspendDelay();
  }

  static isActive(): boolean {
    return BackgroundKeepAlive.active;
  }

  static getActiveMode(): LexiKeepAliveMode {
    return BackgroundKeepAlive.activeMode;
  }

  static getLastStatus(): string {
    return BackgroundKeepAlive.lastStatus;
  }

  static getLastError(): string {
    return BackgroundKeepAlive.lastError;
  }

  static async runWithSuspendDelay<T>(reason: string, action: () => Promise<T>): Promise<T> {
    let requestId: number = -1;
    if (typeof backgroundTaskManager?.requestSuspendDelay === 'function') {
      try {
        const info: backgroundTaskManager.DelaySuspendInfo = backgroundTaskManager.requestSuspendDelay(
          reason,
          (): void => {
            RuntimeDiagnostics.record(`Transient suspend delay expiring: ${reason}`);
          }
        );
        requestId = Number(info?.requestId ?? -1);
      } catch (_delayErr) {
        requestId = -1;
      }
    }
    try {
      return await action();
    } finally {
      if (requestId >= 0 && typeof backgroundTaskManager?.cancelSuspendDelay === 'function') {
        try {
          backgroundTaskManager.cancelSuspendDelay(requestId);
        } catch (_cancelErr) {
          // Ignore if already expired or cancelled.
        }
      }
    }
  }

  private static acquireRelaySuspendDelay(reason: string): void {
    BackgroundKeepAlive.releaseRelaySuspendDelay();
    if (typeof backgroundTaskManager?.requestSuspendDelay !== 'function') { return; }
    try {
      const info: backgroundTaskManager.DelaySuspendInfo = backgroundTaskManager.requestSuspendDelay(
        reason,
        (): void => {
          BackgroundKeepAlive.releaseRelaySuspendDelay();
        }
      );
      BackgroundKeepAlive.relaySuspendRequestId = Number(info?.requestId ?? -1);
      if (BackgroundKeepAlive.relaySuspendRequestId >= 0) {
        BackgroundKeepAlive.relaySuspendTimerId = setTimeout((): void => {
          BackgroundKeepAlive.releaseRelaySuspendDelay();
        }, BackgroundKeepAlive.RELAY_SUSPEND_TIMEOUT_MS);
      }
    } catch (_delayErr) {
      BackgroundKeepAlive.relaySuspendRequestId = -1;
    }
  }

  private static releaseRelaySuspendDelay(): void {
    if (BackgroundKeepAlive.relaySuspendTimerId !== -1) {
      clearTimeout(BackgroundKeepAlive.relaySuspendTimerId);
      BackgroundKeepAlive.relaySuspendTimerId = -1;
    }
    const requestId: number = BackgroundKeepAlive.relaySuspendRequestId;
    BackgroundKeepAlive.relaySuspendRequestId = -1;
    if (requestId >= 0 && typeof backgroundTaskManager?.cancelSuspendDelay === 'function') {
      try {
        backgroundTaskManager.cancelSuspendDelay(requestId);
      } catch (_cancelErr) {
        // Ignore if already expired or cancelled.
      }
    }
  }

  private static async acquireOrRenewRunningLock(): Promise<void> {
    if (typeof runningLock?.create !== 'function') { return; }
    const lockType: runningLock.RunningLockType =
      runningLock.RunningLockType?.BACKGROUND_USER_IDLE ?? (129 as runningLock.RunningLockType);
    try {
      if (typeof runningLock.isSupported === 'function' && !runningLock.isSupported(lockType)) {
        return;
      }
      if (BackgroundKeepAlive.idleLock === null) {
        BackgroundKeepAlive.idleLock = await runningLock.create('LexiClashVpnKeepAlive', lockType);
      }
      BackgroundKeepAlive.idleLock.hold(BackgroundKeepAlive.RUNNING_LOCK_WINDOW_MS);
    } catch (lockErr) {
      RuntimeDiagnostics.record(
        `RunningLock hold skipped: ${BackgroundKeepAlive.describeError(lockErr as BusinessError)}`
      );
    }
  }

  private static releaseRunningLock(): void {
    const lock: runningLock.RunningLock | null = BackgroundKeepAlive.idleLock;
    BackgroundKeepAlive.idleLock = null;
    if (lock === null) { return; }
    try {
      if (typeof lock.isHolding !== 'function' || lock.isHolding()) {
        lock.unhold();
      }
    } catch (_lockErr) {
      // Ignore if lock is already released.
    }
  }

  static async hasSpecialScenarioPermission(): Promise<boolean> {
    try {
      if (typeof bundleManager?.getBundleInfoForSelf !== 'function' ||
        typeof abilityAccessCtrl?.createAtManager !== 'function') {
        return false;
      }
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const tokenId: number | undefined = info?.appInfo?.accessTokenId;
      if (typeof tokenId !== 'number' || !Number.isFinite(tokenId)) {
        return false;
      }
      const status: abilityAccessCtrl.GrantStatus = await abilityAccessCtrl.createAtManager().checkAccessToken(
        tokenId,
        'ohos.permission.KEEP_BACKGROUND_RUNNING_SPECIAL_SCENARIO'
      );
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_error) {
      return false;
    }
  }

  private static describeError(error: BusinessError): string {
    return `${error.code ?? ''} ${error.message || String(error)}`.trim();
  }

  private static clearRefreshTimer(): void {
    BackgroundKeepAlive.generation++;
    if (BackgroundKeepAlive.abortPendingConsent !== null) {
      const abort: () => void = BackgroundKeepAlive.abortPendingConsent;
      BackgroundKeepAlive.abortPendingConsent = null;
      try { abort(); } catch (_err) {}
    }
    if (BackgroundKeepAlive.refreshTimerId !== -1) {
      clearInterval(BackgroundKeepAlive.refreshTimerId);
      BackgroundKeepAlive.refreshTimerId = -1;
    }
  }

  private static async publishProgress(notificationId: number, readBytes: () => Promise<number>,
    generation: number, initial: boolean = true): Promise<void> {
    let bytes: number = BackgroundKeepAlive.lastPublishedBytes;
    if (initial) {
      bytes = await readBytes();
      if (generation !== BackgroundKeepAlive.generation || !BackgroundKeepAlive.active) { return; }
      if (!Number.isFinite(bytes) || bytes < 0) { throw new Error('VPN 流量统计无效'); }
      BackgroundKeepAlive.lastPublishedBytes = bytes;
    } else {
      try {
        const latest: number = await readBytes();
        if (generation !== BackgroundKeepAlive.generation || !BackgroundKeepAlive.active) { return; }
        if (!Number.isFinite(latest) || latest < 0) { throw new Error('VPN 流量统计无效'); }
        bytes = latest;
        BackgroundKeepAlive.lastPublishedBytes = latest;
      } catch (readErr) {
        if (generation !== BackgroundKeepAlive.generation || !BackgroundKeepAlive.active) { return; }
        const detail: string = BackgroundKeepAlive.describeError(readErr as BusinessError);
        RuntimeDiagnostics.record(`VPN traffic read fallback bytes=${Math.floor(bytes)}: ${detail}`);
      }
    }
    const transferred: string = `已传输 ${(bytes / 1048576).toFixed(2)} MiB`;
    const isLiveViewMode: boolean = BackgroundKeepAlive.activeMode === 'dataTransfer' ||
      BackgroundKeepAlive.activeContentType === notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW;
    if (isLiveViewMode) {
      BackgroundKeepAlive.progressTick = (BackgroundKeepAlive.progressTick + 1) % 99;
      const rollingProgress: number = ((Math.floor(bytes / 65536) + BackgroundKeepAlive.progressTick) % 99) + 1;
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
        // Advance progressValue dynamically (1..99, never reaching 100) so HarmonyOS
        // TASK_DETECTION observes active DATA_TRANSFER updates past the 10-minute mark.
        template: {
          name: 'downloadTemplate',
          data: { title: 'LexiClash VPN', fileName: transferred, progressValue: rollingProgress }
        }
      });
    } else {
      try {
        const basicContentType: notificationManager.ContentType =
          notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT ??
          notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW;
        const slotType: notificationManager.SlotType = BackgroundKeepAlive.activeSlotType ??
          notificationManager.SlotType.SERVICE_INFORMATION ??
          notificationManager.SlotType.LIVE_VIEW;
        await notificationManager.publish({
          id: notificationId,
          notificationSlotType: slotType,
          content: {
            notificationContentType: basicContentType,
            normal: {
              title: 'LexiClash VPN',
              text: transferred,
              additionalText: '后台保活运行中'
            }
          }
        });
      } catch (pubErr) {
        // System already owns and displays the persistent normal notification for
        // non-live-view continuous tasks; never tear down protection if publish is rejected.
        RuntimeDiagnostics.record(
          `Continuous task notification update skipped: ${BackgroundKeepAlive.describeError(pubErr as BusinessError)}`
        );
      }
    }
    if (!initial && (BackgroundKeepAlive.activeMode === 'dataTransfer' || BackgroundKeepAlive.activeMode === 'taskKeeping')) {
      await BackgroundKeepAlive.acquireOrRenewRunningLock();
    }
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
        await BackgroundKeepAlive.publishProgress(notificationId, readBytes, generation, false);
      } catch (err) {
        if (generation !== BackgroundKeepAlive.generation) { return; }
        const detail: string = BackgroundKeepAlive.describeError(err as BusinessError);
        BackgroundKeepAlive.lastError = `后台连接状态更新失败：${detail}`;
        RuntimeDiagnostics.record(`VPN transfer notification update failed: ${detail}`);
      } finally {
        updating = false;
      }
    };
    BackgroundKeepAlive.refreshTimerId = setInterval((): void => { publish(); }, 30 * 1000);
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
      if (userInitiated) {
        BackgroundKeepAlive.userCancelled = false;
        BackgroundKeepAlive.specialScenarioUnauthorized = false;
      }
      if (BackgroundKeepAlive.userCancelled) { throw new Error(BackgroundKeepAlive.lastError); }
      return BackgroundKeepAlive.startTask(bundleName, abilityName, readBytes, userInitiated);
    });
    // Keep the caller's rejection without poisoning subsequent stop/start operations.
    BackgroundKeepAlive.pending = operation.catch((): void => {});
    return operation;
  }

  private static isSpecialScenarioAuthGranted(auth: backgroundTaskManager.UserAuthResult): boolean {
    const grantedOnce: backgroundTaskManager.UserAuthResult =
      backgroundTaskManager.UserAuthResult?.GRANTED_ONCE ?? (3 as backgroundTaskManager.UserAuthResult);
    const grantedAlways: backgroundTaskManager.UserAuthResult =
      backgroundTaskManager.UserAuthResult?.GRANTED_ALWAYS ?? (4 as backgroundTaskManager.UserAuthResult);
    return auth === grantedAlways || auth === grantedOnce;
  }

  private static async checkSpecialScenarioAuthState(ctx: common.UIAbilityContext,
    request: backgroundTaskManager.ContinuousTaskRequest): Promise<backgroundTaskManager.UserAuthResult> {
    const notDetermined: backgroundTaskManager.UserAuthResult =
      backgroundTaskManager.UserAuthResult?.NOT_DETERMINED ?? (1 as backgroundTaskManager.UserAuthResult);
    if (typeof request.checkSpecialScenarioAuthResult === 'function') {
      try {
        return await request.checkSpecialScenarioAuthResult(ctx);
      } catch (_err) {
        // Fall through to legacy checkSpecialScenarioAuth if unavailable on this runtime.
      }
    }
    if (typeof request.checkSpecialScenarioAuth === 'function') {
      try {
        return await request.checkSpecialScenarioAuth(ctx);
      } catch (_err) {
        return notDetermined;
      }
    }
    return notDetermined;
  }

  private static requestSpecialScenarioConsent(ctx: common.UIAbilityContext,
    request: backgroundTaskManager.ContinuousTaskRequest): Promise<backgroundTaskManager.UserAuthResult> {
    const notDetermined: backgroundTaskManager.UserAuthResult =
      backgroundTaskManager.UserAuthResult?.NOT_DETERMINED ?? (1 as backgroundTaskManager.UserAuthResult);
    const invokePrompt = (useDialog: boolean): Promise<backgroundTaskManager.UserAuthResult> => {
      return new Promise<backgroundTaskManager.UserAuthResult>(
        (resolve: (result: backgroundTaskManager.UserAuthResult) => void,
          reject: (reason: Error) => void): void => {
          let settled: boolean = false;
          const finish = (res: backgroundTaskManager.UserAuthResult): void => {
            if (settled) { return; }
            settled = true;
            if (BackgroundKeepAlive.abortPendingConsent === cancelWait) {
              BackgroundKeepAlive.abortPendingConsent = null;
            }
            clearTimeout(timerId);
            resolve(res);
          };
          const cancelWait = (): void => { finish(notDetermined); };
          BackgroundKeepAlive.abortPendingConsent = cancelWait;
          const timerId: number = setTimeout((): void => {
            finish(notDetermined);
          }, BackgroundKeepAlive.AUTH_TIMEOUT_MS);
          try {
            if (useDialog && typeof request.requestAuthFromUserByDialog === 'function') {
              request.requestAuthFromUserByDialog(ctx, (result: backgroundTaskManager.UserAuthResult): void => {
                finish(result);
              });
            } else if (typeof request.requestAuthFromUser === 'function') {
              request.requestAuthFromUser(ctx, (result: backgroundTaskManager.UserAuthResult): void => {
                finish(result);
              });
            } else {
              finish(notDetermined);
            }
          } catch (err) {
            clearTimeout(timerId);
            if (BackgroundKeepAlive.abortPendingConsent === cancelWait) {
              BackgroundKeepAlive.abortPendingConsent = null;
            }
            if (!settled) {
              settled = true;
              reject(err instanceof Error ? err : new Error(BackgroundKeepAlive.describeError(err as BusinessError)));
            }
          }
        }
      );
    };

    if (typeof request.requestAuthFromUserByDialog === 'function') {
      return invokePrompt(true).catch((_dialogErr: Error): Promise<backgroundTaskManager.UserAuthResult> => {
        if (typeof request.requestAuthFromUser === 'function') {
          return invokePrompt(false);
        }
        return Promise.resolve(notDetermined);
      });
    }
    return invokePrompt(false);
  }

  private static async tryStartSpecialScenario(ctx: common.UIAbilityContext, agent: WantAgent,
    generation: number, userInitiated: boolean): Promise<backgroundTaskManager.ContinuousTaskNotification | null> {
    if (BackgroundKeepAlive.specialScenarioUnauthorized) {
      return null;
    }
    const specialMode: backgroundTaskManager.BackgroundTaskMode | undefined =
      backgroundTaskManager.BackgroundTaskMode?.MODE_SPECIAL_SCENARIO_PROCESSING;
    const specialSubmode: backgroundTaskManager.BackgroundTaskSubmode | undefined =
      backgroundTaskManager.BackgroundTaskSubmode?.SUBMODE_MEDIA_PROCESS_NORMAL_NOTIFICATION;
    if (specialMode === undefined || specialSubmode === undefined) {
      return null;
    }
    if (!await BackgroundKeepAlive.hasSpecialScenarioPermission()) {
      return null;
    }
    if (ctx !== BackgroundKeepAlive.abilityContext || generation !== BackgroundKeepAlive.generation) {
      throw new Error('后台运行申请已取消');
    }
    const request: backgroundTaskManager.ContinuousTaskRequest = new backgroundTaskManager.ContinuousTaskRequest();
    request.backgroundTaskModes = [specialMode];
    request.backgroundTaskSubmodes = [specialSubmode];
    request.wantAgent = agent;
    if (typeof request.isModeSupported === 'function') {
      let supported: boolean = false;
      try {
        supported = request.isModeSupported();
      } catch (_supErr) {
        supported = false;
      }
      if (!supported) {
        RuntimeDiagnostics.record('MODE_SPECIAL_SCENARIO_PROCESSING unsupported on current device; falling back to dataTransfer');
        return null;
      }
    }
    let auth: backgroundTaskManager.UserAuthResult =
      await BackgroundKeepAlive.checkSpecialScenarioAuthState(ctx, request);
    if (!BackgroundKeepAlive.isSpecialScenarioAuthGranted(auth)) {
      if (!userInitiated) {
        RuntimeDiagnostics.record(`Special scenario auth unavailable in background (${auth}); falling back to dataTransfer`);
        return null;
      }
      try {
        auth = await BackgroundKeepAlive.requestSpecialScenarioConsent(ctx, request);
      } catch (authErr) {
        RuntimeDiagnostics.record(`Special scenario consent failed, falling back to dataTransfer: ${String(authErr)}`);
        return null;
      }
      if (ctx !== BackgroundKeepAlive.abilityContext || generation !== BackgroundKeepAlive.generation) {
        throw new Error('后台运行申请已取消');
      }
      const deniedResult: backgroundTaskManager.UserAuthResult =
        backgroundTaskManager.UserAuthResult?.DENIED ?? (2 as backgroundTaskManager.UserAuthResult);
      if (!BackgroundKeepAlive.isSpecialScenarioAuthGranted(auth)) {
        if (auth === deniedResult) {
          BackgroundKeepAlive.specialScenarioUnauthorized = true;
        }
        RuntimeDiagnostics.record(`Special scenario user auth result=${auth}; falling back to dataTransfer`);
        return null;
      }
    }
    try {
      return await backgroundTaskManager.startBackgroundRunning(ctx, request);
    } catch (startErr) {
      RuntimeDiagnostics.record(
        `Special scenario startBackgroundRunning failed, falling back: ${BackgroundKeepAlive.describeError(startErr as BusinessError)}`
      );
      return null;
    }
  }

  private static async tryStartTaskKeeping(ctx: common.UIAbilityContext, agent: WantAgent,
    generation: number): Promise<backgroundTaskManager.ContinuousTaskNotification | null> {
    const devType: string = String(deviceInfo?.deviceType ?? '').toLowerCase();
    if (devType !== '2in1' && devType !== 'pc') {
      return null;
    }
    const keepMode: backgroundTaskManager.BackgroundTaskMode | undefined =
      backgroundTaskManager.BackgroundTaskMode?.MODE_TASK_KEEPING;
    const normalSubmode: backgroundTaskManager.BackgroundTaskSubmode | undefined =
      backgroundTaskManager.BackgroundTaskSubmode?.SUBMODE_NORMAL_NOTIFICATION;
    if (keepMode === undefined || normalSubmode === undefined) {
      return null;
    }
    if (ctx !== BackgroundKeepAlive.abilityContext || generation !== BackgroundKeepAlive.generation) {
      throw new Error('后台运行申请已取消');
    }
    const request: backgroundTaskManager.ContinuousTaskRequest = new backgroundTaskManager.ContinuousTaskRequest();
    request.backgroundTaskModes = [keepMode];
    request.backgroundTaskSubmodes = [normalSubmode];
    request.wantAgent = agent;
    if (typeof request.isModeSupported === 'function') {
      let supported: boolean = false;
      try {
        supported = request.isModeSupported();
      } catch (_supErr) {
        supported = false;
      }
      if (!supported) {
        return null;
      }
    }
    try {
      return await backgroundTaskManager.startBackgroundRunning(ctx, request);
    } catch (startErr) {
      RuntimeDiagnostics.record(
        `TaskKeeping startBackgroundRunning failed, falling back to dataTransfer: ${BackgroundKeepAlive.describeError(startErr as BusinessError)}`
      );
      return null;
    }
  }

  private static ensureListeners(): void {
    if (!BackgroundKeepAlive.cancelListening) {
      backgroundTaskManager.on('continuousTaskCancel', BackgroundKeepAlive.cancelListener);
      BackgroundKeepAlive.cancelListening = true;
    }
    if (!BackgroundKeepAlive.suspendListening) {
      try {
        backgroundTaskManager.on('continuousTaskSuspend', BackgroundKeepAlive.suspendListener);
        BackgroundKeepAlive.suspendListening = true;
      } catch (_suspendErr) {
        // Optional on older runtimes or test harnesses.
      }
    }
    if (!BackgroundKeepAlive.activeListening) {
      try {
        backgroundTaskManager.on('continuousTaskActive', BackgroundKeepAlive.activeListener);
        BackgroundKeepAlive.activeListening = true;
      } catch (_activeErr) {
        // Optional on older runtimes or test harnesses.
      }
    }
  }

  private static async startTask(bundleName: string, abilityName: string,
    readBytes: () => Promise<number>, userInitiated: boolean): Promise<void> {
    const ctx: common.UIAbilityContext | null = BackgroundKeepAlive.abilityContext;
    if (BackgroundKeepAlive.active) { return; }
    if (ctx === null) {
      BackgroundKeepAlive.lastError = '无法启用后台连接：应用窗口尚未就绪';
      throw new Error(BackgroundKeepAlive.lastError);
    }
    const generation: number = BackgroundKeepAlive.generation;
    let taskId: number = -1;
    try {
      BackgroundKeepAlive.progressTick = 0;
      BackgroundKeepAlive.ensureListeners();
      const agent: WantAgent = await BackgroundKeepAlive.buildLaunchAgent(bundleName, abilityName);
      if (ctx !== BackgroundKeepAlive.abilityContext || generation !== BackgroundKeepAlive.generation) {
        throw new Error('后台运行申请已取消');
      }
      let chosenMode: LexiKeepAliveMode = 'specialScenario';
      let task: backgroundTaskManager.ContinuousTaskNotification | null =
        await BackgroundKeepAlive.tryStartSpecialScenario(ctx, agent, generation, userInitiated);
      if (task !== null) {
        BackgroundKeepAlive.releaseRunningLock();
      } else {
        task = await BackgroundKeepAlive.tryStartTaskKeeping(ctx, agent, generation);
        if (task !== null) {
          chosenMode = 'taskKeeping';
        } else {
          chosenMode = 'dataTransfer';
          const request: backgroundTaskManager.ContinuousTaskRequest = new backgroundTaskManager.ContinuousTaskRequest();
          request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER];
          request.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_LIVE_VIEW_NOTIFICATION];
          request.wantAgent = agent;
          task = await backgroundTaskManager.startBackgroundRunning(ctx, request);
        }
      }
      taskId = task.continuousTaskId ?? -1;
      if (!Number.isFinite(taskId) || taskId < 0 || !Number.isFinite(task.notificationId)) {
        throw new Error('系统未返回有效的后台任务或通知标识');
      }
      if (ctx !== BackgroundKeepAlive.abilityContext || generation !== BackgroundKeepAlive.generation) {
        throw new Error('后台运行申请已取消');
      }
      BackgroundKeepAlive.continuousTaskId = taskId;
      BackgroundKeepAlive.notificationId = task.notificationId;
      BackgroundKeepAlive.activeMode = chosenMode;
      BackgroundKeepAlive.activeSlotType = task.slotType ?? (
        chosenMode === 'specialScenario' || chosenMode === 'taskKeeping'
          ? (notificationManager.SlotType.SERVICE_INFORMATION ?? notificationManager.SlotType.LIVE_VIEW)
          : notificationManager.SlotType.LIVE_VIEW
      );
      BackgroundKeepAlive.activeContentType = task.contentType ?? (
        chosenMode === 'specialScenario' || chosenMode === 'taskKeeping'
          ? (notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT ?? notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW)
          : notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW
      );
      BackgroundKeepAlive.active = true;
      await BackgroundKeepAlive.publishProgress(task.notificationId, readBytes, generation, true);
      if (generation !== BackgroundKeepAlive.generation || !BackgroundKeepAlive.active) {
        throw new Error('后台运行申请已取消');
      }
      if (chosenMode === 'taskKeeping' || chosenMode === 'dataTransfer') {
        await BackgroundKeepAlive.acquireOrRenewRunningLock();
      }
      BackgroundKeepAlive.scheduleProgress(task.notificationId, readBytes, generation);
      BackgroundKeepAlive.lastStatus = chosenMode === 'specialScenario'
        ? 'running:specialScenario'
        : chosenMode === 'taskKeeping'
          ? 'running:taskKeeping'
          : 'running:dataTransfer';
      RuntimeDiagnostics.record(
        `KeepAlive started (${BackgroundKeepAlive.lastStatus}) id=${taskId} notificationId=${task.notificationId}`
      );
    } catch (err) {
      if (BackgroundKeepAlive.continuousTaskId === taskId) {
        BackgroundKeepAlive.active = false;
        BackgroundKeepAlive.activeMode = 'none';
        BackgroundKeepAlive.continuousTaskId = -1;
        BackgroundKeepAlive.notificationId = -1;
      }
      BackgroundKeepAlive.releaseRunningLock();
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
    } finally {
      BackgroundKeepAlive.releaseRelaySuspendDelay();
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
    BackgroundKeepAlive.activeMode = 'none';
    BackgroundKeepAlive.continuousTaskId = -1;
    BackgroundKeepAlive.notificationId = -1;
    BackgroundKeepAlive.lastPublishedBytes = 0;
    BackgroundKeepAlive.progressTick = 0;
    BackgroundKeepAlive.lastStatus = 'stopped';
    BackgroundKeepAlive.lastError = '';
    BackgroundKeepAlive.userCancelled = false;
    BackgroundKeepAlive.releaseRunningLock();
    BackgroundKeepAlive.releaseRelaySuspendDelay();
    if (ctx === null || taskId < 0) { return; }
    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx, taskId);
      RuntimeDiagnostics.record(`KeepAlive stopped id=${taskId}`);
    } catch (err) {
      RuntimeDiagnostics.record(`Stop continuous task warning: ${BackgroundKeepAlive.describeError(err as BusinessError)}`);
    }
  }
}

import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { launchAsync, startTunAsync, getTunError, stopAsync, invoke } from 'libclash_bridge.so';
import { VpnRuntimeManager } from '../core/VpnRuntimeManager';
import { RuntimeDiagnostics } from '../core/RuntimeDiagnostics';
import { AppAccessControl, LexiAppAccessPolicy } from '../core/AppAccessControl';
import { LexiTunSettings, TunConfig } from '../core/TunConfig';

const DOMAIN: number = 0xF1C1;

interface VpnCommand {
  sessionId: string;
  action: string;
  requestedAt: number;
  secret: string;
  accessControl?: LexiAppAccessPolicy;
  tun?: LexiTunSettings;
}

interface VpnRuntimeStatus {
  sessionId: string;
  status: string;
  error: string;
  updatedAt: number;
  cleanupComplete: boolean;
  accessControl: LexiAppAccessPolicy;
  tun: LexiTunSettings;
}

interface VpnSession {
  sessionId: string;
  startedAt: number;
}

export default class LexiVpnExtension extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;
  private connectionCreated: boolean = false;
  private coreAttempted: boolean = false;
  private pendingFd: number = -1;
  private cancelled: boolean = false;
  private sessionId: string = '';
  private status: string = 'starting';
  private statusError: string = '';
  private cleaned: boolean = false;
  private startup?: Promise<void>;
  private stopping?: Promise<void>;
  private coreStopping?: Promise<void>;
  private cleanup?: Promise<void>;
  private commandTimer: number = -1;
  private networkManager: VpnRuntimeManager = new VpnRuntimeManager();
  private networkTimer: number = -1;
  private lastHeartbeat: number = 0;
  private lastCoreGcAt: number = 0;
  private accessControl: LexiAppAccessPolicy = AppAccessControl.unrestricted();
  private tunSettings: LexiTunSettings = TunConfig.defaults();

  onCreate(): void {
    RuntimeDiagnostics.watch(this.context.filesDir, 'vpn');
    RuntimeDiagnostics.record('LexiVpnExtension created');
    hilog.info(DOMAIN, 'LexiClashVPN', 'VPN extension created');
    const command: VpnCommand | undefined = this.readCommand();
    if (!command || !command.sessionId) {
      hilog.error(DOMAIN, 'LexiClashVPN', 'Missing VPN session command; refusing unowned startup');
      return;
    }
    this.sessionId = command.sessionId;
    this.accessControl = command.accessControl ?? AppAccessControl.unrestricted();
    this.tunSettings = command.tun ?? TunConfig.defaults();
    if (command.action !== 'start') {
      this.cleaned = true;
      this.publishStatus('stopped');
      return;
    }
    this.publishStatus('starting');
    this.commandTimer = setInterval((): void => { this.pollCommand(); }, 1000);
    this.startup = this.start(command.secret);
  }

  private readCommand(): VpnCommand | undefined {
    try {
      return JSON.parse(fs.readTextSync(`${this.context.filesDir}/vpn-command.json`)) as VpnCommand;
    } catch (_err) {
      return undefined;
    }
  }

  private ownsSession(): boolean {
    return this.sessionId.length > 0 && this.readCommand()?.sessionId === this.sessionId;
  }

  private writeJson(name: string, content: string): void {
    const targetPath: string = `${this.context.filesDir}/${name}`;
    const temporary: string = `${targetPath}.extension.tmp`;
    const file: fs.File = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(temporary, targetPath);
  }

  private writeStatusSnapshot(status: string, error: string = ''): void {
    const data: VpnRuntimeStatus = {
      sessionId: this.sessionId,
      status: status,
      error: error,
      updatedAt: Date.now(),
      cleanupComplete: this.cleaned,
      accessControl: this.accessControl,
      tun: this.tunSettings
    };
    try {
      this.writeJson('vpn-status.json', JSON.stringify(data));
      this.lastHeartbeat = data.updatedAt;
    } catch (failure) {
      hilog.error(DOMAIN, 'LexiClashVPN', 'Cannot publish VPN state: %{public}s', String(failure));
    }
  }

  private publishStatus(status: string, error: string = ''): void {
    this.status = status;
    this.statusError = error;
    if (!this.ownsSession()) { return; }
    this.writeStatusSnapshot(status, error);
  }

  private pollCommand(): void {
    const command: VpnCommand | undefined = this.readCommand();
    if (!command || command.sessionId !== this.sessionId || command.action !== 'start') {
      this.requestStop();
      return;
    }
    const now: number = Date.now();
    if (now - this.lastHeartbeat >= 2000) {
      this.writeStatusSnapshot(this.status, this.statusError);
    }
    if (this.status === 'running' && !this.cancelled && now - this.lastCoreGcAt >= 90000) {
      this.lastCoreGcAt = now;
      if (typeof invoke === 'function') {
        try {
          invoke('{"id":"gc","method":"forceGc","arguments":{}}');
        } catch (_gcErr) {
          // Non-fatal maintenance GC
        }
      }
    }
  }

  private async createTunWithRetry(connectionObj: vpnExtension.VpnConnection,
    config: vpnExtension.VpnConfig): Promise<number> {
    const delays: number[] = [350, 700];
    for (let attempt: number = 0; ; attempt++) {
      this.checkStartAllowed();
      try {
        return await connectionObj.create(config);
      } catch (err) {
        const vpnError: BusinessError = err as BusinessError;
        if (vpnError.code === 2203002) {
          if (attempt < delays.length) {
            RuntimeDiagnostics.record(`VPN TUN create hit 2203002, waiting ${delays[attempt]}ms for prior interface release`);
            await new Promise<void>((resolve: () => void): void => {
              setTimeout(resolve, delays[attempt]);
            });
            continue;
          }
          throw new Error('系统已有 VPN 连接，请先断开其他 VPN 后重试（2203002）');
        }
        throw err instanceof Error ? err : new Error(vpnError.message || String(err));
      }
    }
  }

  private checkStartAllowed(): void {
    const command: VpnCommand | undefined = this.readCommand();
    if (this.cancelled || !command || command.sessionId !== this.sessionId || command.action !== 'start') {
      this.cancelled = true;
      throw new Error('VPN 启动已取消');
    }
  }

  private async start(secret: string): Promise<void> {
    let failure: string = '';
    try {
      this.checkStartAllowed();
      if (!secret) { throw new Error('VPN 会话凭据缺失，请重新连接'); }
      const accessError: string = AppAccessControl.validationError(this.accessControl);
      if (accessError.length > 0) { throw new Error(accessError); }
      const tunError: string = TunConfig.validationError(this.tunSettings);
      if (tunError.length > 0) { throw new Error(tunError); }
      // Launch mihomo core & REST controller before routing system traffic into TUN.
      this.coreAttempted = true;
      const launchError: string = await launchAsync(this.context.filesDir, secret);
      this.checkStartAllowed();
      if (launchError.length > 0) { throw new Error(launchError); }
      hilog.info(DOMAIN, 'LexiClashVPN', 'Native core launch completed');

      this.connection = vpnExtension.createVpnConnection(this.context);
      const address: vpnExtension.LinkAddress = {
        address: { address: '172.19.0.1', family: 1 },
        prefixLength: 30
      };
      const route: vpnExtension.RouteInfo = {
        interface: 'vpn-tun',
        destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
        gateway: { address: '172.19.0.1', family: 1 },
        hasGateway: false,
        isDefaultRoute: true
      };
      const config: vpnExtension.VpnConfig = {
        addresses: [address, {
          address: { address: 'fdfe:dcba:9876::1', family: 2 }, prefixLength: 126
        }],
        routes: [route, {
          interface: 'vpn-tun',
          destination: { address: { address: '::', family: 2 }, prefixLength: 0 },
          gateway: { address: 'fdfe:dcba:9876::1', family: 2 },
          hasGateway: false, isDefaultRoute: true
        }],
        dnsAddresses: ['172.19.0.2'],
        mtu: this.tunSettings.mtu,
        isIPv4Accepted: true,
        // Always capture IPv6. The core rejects it when the user disables IPv6.
        isIPv6Accepted: true
      };
      AppAccessControl.configureVpn(config, this.accessControl);
      this.pendingFd = await this.createTunWithRetry(this.connection, config);
      this.connectionCreated = true;
      hilog.info(DOMAIN, 'LexiClashVPN', 'VPN TUN created');
      this.checkStartAllowed();

      const fd: number = this.pendingFd;
      this.pendingFd = -1;
      const started: boolean = await startTunAsync(fd);
      this.checkStartAllowed();
      if (!started) {
        throw new Error(`mihomo 无法读取系统 TUN 接口: ${getTunError()}`);
      }
      const session: VpnSession = { sessionId: this.sessionId, startedAt: Date.now() };
      this.writeJson('vpn-session.json', JSON.stringify(session));
      this.networkManager.setFilesDir(this.context.filesDir);
      this.networkManager.setSecret(secret);
      this.networkManager.startNetworkWatch((_changed: boolean, netId: number): void => {
        clearTimeout(this.networkTimer);
        this.networkTimer = setTimeout((): void => { this.refreshUpstream(netId); }, 1500);
      });
      this.lastCoreGcAt = Date.now();
      this.publishStatus('running');
      hilog.info(DOMAIN, 'LexiClashVPN', 'Native TUN started');
      return;
    } catch (error) {
      if (!this.cancelled) {
        const vpnError: BusinessError = error as BusinessError;
        failure = vpnError.code === 2203002
          ? '系统已有 VPN 连接，请先断开其他 VPN 后重试（2203002）'
          : (vpnError.message || String(error));
        hilog.error(DOMAIN, 'LexiClashVPN', 'VPN start failed: %{public}s', failure);
      }
    }
    try {
      await this.releaseResources();
    } catch (error) {
      failure = `${failure ? `${failure}；` : ''}VPN 清理失败：${String(error)}`;
    }
    this.clearCommandTimer();
    this.publishStatus(failure ? 'error' : 'stopped', failure);
  }

  private async refreshUpstream(netId: number): Promise<void> {
    this.networkTimer = -1;
    if (this.cancelled || !this.ownsSession()) { return; }
    try {
      await this.networkManager.flushDnsCache();
      if (this.cancelled || !this.ownsSession()) { return; }
      // New sockets select the current physical network in socket_ohos.go.
      await this.networkManager.closeAllConnections();
      if (typeof invoke === 'function') {
        try {
          invoke('{"id":"gc","method":"forceGc","arguments":{}}');
          this.lastCoreGcAt = Date.now();
        } catch (_gcErr) {
          // Non-fatal maintenance GC
        }
      }
      RuntimeDiagnostics.record(`VPN upstream connections refreshed netId=${netId}`);
    } catch (err) {
      RuntimeDiagnostics.record(`VPN upstream refresh failed: ${String(err)}`);
    }
  }

  private stopCore(): Promise<void> {
    if (!this.coreStopping) {
      this.coreStopping = this.coreAttempted ? stopAsync() : Promise.resolve();
      this.coreStopping.catch((): void => {});
    }
    return this.coreStopping;
  }

  private releaseResources(): Promise<void> {
    if (!this.cleanup) {
      this.cleanup = this.releaseOwnedResources();
    }
    return this.cleanup;
  }

  private async releaseOwnedResources(): Promise<void> {
    let failure: string = '';
    try {
      await this.stopCore();
    } catch (error) {
      failure = String(error);
    }
    if (this.pendingFd >= 0) {
      try {
        fs.closeSync(this.pendingFd);
      } catch (error) {
        hilog.warn(DOMAIN, 'LexiClashVPN', 'Unused TUN fd cleanup: %{public}s', String(error));
      }
      this.pendingFd = -1;
    }
    if (this.connectionCreated && this.connection) {
      try {
        await this.connection.destroy();
        this.connectionCreated = false;
      } catch (error) {
        failure = `${failure ? `${failure}；` : ''}${String(error)}`;
      }
    }
    if (failure) { throw new Error(failure); }
    this.cleaned = true;
    this.connection = undefined;
    try {
      const sessionPath: string = `${this.context.filesDir}/vpn-session.json`;
      const session: VpnSession = JSON.parse(fs.readTextSync(sessionPath)) as VpnSession;
      if (session.sessionId === this.sessionId) { fs.unlinkSync(sessionPath); }
    } catch (_err) {
      // ignore missing session file
    }
  }

  private requestStop(): void {
    if (this.stopping) { return; }
    this.cancelled = true;
    this.networkManager.stopNetworkWatch();
    clearTimeout(this.networkTimer);
    this.publishStatus('stopping');
    this.stopCore();
    this.stopping = this.finishStop();
  }

  private async finishStop(): Promise<void> {
    try {
      await this.startup;
      await this.releaseResources();
      this.publishStatus('stopped');
    } catch (error) {
      const detail: string = `VPN 清理失败：${String(error)}`;
      hilog.error(DOMAIN, 'LexiClashVPN', '%{public}s', detail);
      this.publishStatus('error', detail);
    } finally {
      this.clearCommandTimer();
    }
  }

  private clearCommandTimer(): void {
    if (this.commandTimer >= 0) {
      clearInterval(this.commandTimer);
      this.commandTimer = -1;
    }
  }

  onDestroy(): void {
    RuntimeDiagnostics.record(`VPN extension destroyed: status=${this.status} cancelled=${this.cancelled}`);
    this.requestStop();
  }
}

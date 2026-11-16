import type { Want } from '@kit.AbilityKit';
import { connection, http, vpnExtension } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BackgroundKeepAlive } from './BackgroundKeepAlive';
import { RuntimeDiagnostics } from './RuntimeDiagnostics';
import { VpnAuthorization } from './VpnAuthorization';

export interface LexiVpnCommand {
  sessionId: string;
  action: string;
  requestedAt: number;
  secret: string;
}

export interface LexiVpnRuntimeStatus {
  sessionId: string;
  status: string;
  error: string;
  updatedAt: number;
  cleanupComplete: boolean;
}

export interface LexiControllerTraffic {
  uploadTotal: number;
  downloadTotal: number;
  connections: Array<Record<string, Object>>;
}

export class VpnRuntimeManager {
  private static readonly BUNDLE_NAME: string = 'com.lovexjy.lexiclash';
  private static readonly EXTENSION_ABILITY_NAME: string = 'LexiVpnExtension';
  readonly controllerUrl: string = 'http://127.0.0.1:9090';

  private filesDir: string = '';
  private secretValue: string = '';
  private netConn: connection.NetConnection | null = null;
  private lastPhysicalNetId: number = 0;
  private netLostObserved: boolean = false;

  setFilesDir(filesDir: string): void {
    this.filesDir = filesDir;
    this.loadSecretFromDisk();
  }

  getFilesDir(): string {
    return this.filesDir;
  }

  getSecret(): string {
    return this.secretValue;
  }

  private vpnWant(): Want {
    return {
      deviceId: '',
      bundleName: VpnRuntimeManager.BUNDLE_NAME,
      abilityName: VpnRuntimeManager.EXTENSION_ABILITY_NAME
    };
  }

  private generateRandomToken(): string {
    const chars: string = '0123456789abcdef';
    let token: string = `${Date.now().toString(16)}_`;
    for (let i: number = 0; i < 32; i++) {
      token += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return token;
  }

  private writePrivateFile(name: string, content: string): void {
    if (this.filesDir.length === 0) {
      throw new Error('应用沙箱目录尚未就绪');
    }
    const targetPath: string = `${this.filesDir}/${name}`;
    const tmpPath: string = `${targetPath}.tmp`;
    const file: fs.File = fs.openSync(tmpPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(tmpPath, targetPath);
  }

  private loadSecretFromDisk(): void {
    if (this.filesDir.length === 0) {
      return;
    }
    try {
      const raw: string = fs.readTextSync(`${this.filesDir}/vpn-command.json`);
      const cmd: LexiVpnCommand = JSON.parse(raw) as LexiVpnCommand;
      if (typeof cmd.secret === 'string' && cmd.secret.length > 0) {
        this.secretValue = cmd.secret;
      }
    } catch (_err) {
      // ignore missing command file
    }
  }

  getRuntimeStatus(): LexiVpnRuntimeStatus {
    if (this.filesDir.length === 0) {
      return { sessionId: '', status: 'stopped', error: '', updatedAt: 0, cleanupComplete: true };
    }
    try {
      const raw: string = fs.readTextSync(`${this.filesDir}/vpn-status.json`);
      return JSON.parse(raw) as LexiVpnRuntimeStatus;
    } catch (_err) {
      return { sessionId: '', status: 'stopped', error: '', updatedAt: 0, cleanupComplete: true };
    }
  }

  runtimeIsFresh(state: LexiVpnRuntimeStatus): boolean {
    return typeof state.sessionId === 'string' && state.sessionId.length > 0 && Date.now() - state.updatedAt < 15000;
  }

  getSessionStartedAt(): number {
    if (this.filesDir.length === 0) {
      return 0;
    }
    try {
      const raw: string = fs.readTextSync(`${this.filesDir}/vpn-session.json`);
      const data: Record<string, number> = JSON.parse(raw) as Record<string, number>;
      return Number(data['startedAt'] ?? 0);
    } catch (_err) {
      return 0;
    }
  }

  requestVpnStop(): string {
    if (this.filesDir.length === 0) {
      return '';
    }
    let cmd: LexiVpnCommand;
    try {
      cmd = JSON.parse(fs.readTextSync(`${this.filesDir}/vpn-command.json`)) as LexiVpnCommand;
    } catch (_err) {
      cmd = {
        sessionId: this.getRuntimeStatus().sessionId || '',
        action: 'stop',
        requestedAt: Date.now(),
        secret: this.secretValue
      };
    }
    cmd.action = 'stop';
    cmd.requestedAt = Date.now();
    try {
      this.writePrivateFile('vpn-command.json', JSON.stringify(cmd));
    } catch (_err) {
      // ignore write failure on cleanup
    }
    return cmd.sessionId;
  }

  private async pauseFor(ms: number): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, ms);
    });
  }

  async releaseVpn(): Promise<void> {
    const initial: LexiVpnRuntimeStatus = this.getRuntimeStatus();
    const sessionId: string = this.requestVpnStop();
    let abilityStopped: boolean = false;
    if (!this.runtimeIsFresh(initial) || initial.cleanupComplete) {
      try {
        await vpnExtension.stopVpnExtensionAbility(this.vpnWant());
      } catch (_err) {
        // ignore if extension was never running
      }
      abilityStopped = true;
    }
    if (sessionId.length === 0 && abilityStopped) {
      return;
    }
    const deadline: number = Date.now() + 18000;
    while (Date.now() < deadline) {
      const state: LexiVpnRuntimeStatus = this.getRuntimeStatus();
      if (state.sessionId === sessionId && state.cleanupComplete &&
        (state.status === 'stopped' || state.status === 'error')) {
        if (!abilityStopped) {
          try {
            await vpnExtension.stopVpnExtensionAbility(this.vpnWant());
          } catch (_err) {
            // ignore
          }
        }
        return;
      }
      if (abilityStopped && !this.runtimeIsFresh(state)) {
        try {
          await this.request('/version', http.RequestMethod.GET, '', 1000);
        } catch (_err) {
          return;
        }
      }
      if (!abilityStopped && Date.now() > deadline - 7000) {
        try {
          await vpnExtension.stopVpnExtensionAbility(this.vpnWant());
        } catch (_err) {
          // ignore
        }
        abilityStopped = true;
      }
      await this.pauseFor(200);
    }
    throw new Error('上次 VPN 尚未释放，请稍后重试');
  }

  prepareStartFiles(yamlContent: string, selectionsMap: Record<string, string>): string {
    if (this.secretValue.length === 0) {
      this.secretValue = this.generateRandomToken();
    }
    this.writePrivateFile('proxy-selections.json', JSON.stringify(selectionsMap));
    this.writePrivateFile('config.yaml', yamlContent);
    const sessionId: string = this.generateRandomToken();
    const cmd: LexiVpnCommand = {
      sessionId: sessionId,
      action: 'start',
      requestedAt: Date.now(),
      secret: this.secretValue
    };
    this.writePrivateFile('vpn-command.json', JSON.stringify(cmd));
    return sessionId;
  }

  async startVpn(yamlContent: string, selectionsMap: Record<string, string>): Promise<void> {
    await this.releaseVpn();
    const sessionId: string = this.prepareStartFiles(yamlContent, selectionsMap);
    let denied: boolean = false;
    let rejectAuthorization: ((reason: Error) => void) | undefined = undefined;
    const authorizationDenied: Promise<void> = new Promise<void>(
      (_resolve: () => void, reject: (reason: Error) => void): void => {
        rejectAuthorization = reject;
      }
    );

    VpnAuthorization.subscribe((authorized: boolean): void => {
      denied = !authorized;
      if (denied && rejectAuthorization) {
        rejectAuthorization(new Error('未授权 VPN，请重新连接并允许系统授权'));
      }
    });

    let startTimeoutId: number = -1;
    try {
      try {
        await Promise.race<void>([
          vpnExtension.startVpnExtensionAbility(this.vpnWant()),
          authorizationDenied,
          new Promise<void>((_resolve: () => void, reject: (reason: Error) => void): void => {
            startTimeoutId = setTimeout((): void => {
              reject(new Error('系统 VPN 授权或扩展启动超时（模拟器若不支持系统 VPN 服务可连接真机使用）'));
            }, 60000);
          })
        ]);
      } finally {
        if (startTimeoutId !== -1) {
          clearTimeout(startTimeoutId);
        }
      }

      const deadline: number = Date.now() + 45000;
      let ready: boolean = false;
      while (Date.now() < deadline) {
        if (denied) {
          throw new Error('未授权 VPN，请重新连接并允许系统授权');
        }
        const state: LexiVpnRuntimeStatus = this.getRuntimeStatus();
        if (state.sessionId === sessionId) {
          if (state.status === 'error') {
            throw new Error(state.error || 'VPN 启动失败');
          }
          if (state.status === 'running') {
            ready = true;
            break;
          }
          if (state.status === 'stopped') {
            throw new Error('VPN 启动已取消');
          }
        }
        await this.pauseFor(250);
      }
      if (!ready) {
        throw new Error('VPN 扩展进程未响应启动，请确认设备支持系统 VPN 扩展后重试');
      }
      await this.checkController();
      await BackgroundKeepAlive.start(VpnRuntimeManager.BUNDLE_NAME, 'EntryAbility');
    } catch (error) {
      try {
        await this.releaseVpn();
      } catch (_releaseErr) {
        // ignore secondary cleanup error
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(String(error));
    } finally {
      VpnAuthorization.unsubscribe();
    }
  }

  async stopVpn(): Promise<void> {
    this.stopNetworkWatch();
    try {
      await this.releaseVpn();
    } finally {
      await BackgroundKeepAlive.stop();
    }
  }

  async isSessionHealthy(): Promise<boolean> {
    const status: LexiVpnRuntimeStatus = this.getRuntimeStatus();
    if (status.status !== 'running' || status.cleanupComplete) {
      return false;
    }
    try {
      await this.checkController();
      await BackgroundKeepAlive.start(VpnRuntimeManager.BUNDLE_NAME, 'EntryAbility');
      return true;
    } catch (_err) {
      return false;
    }
  }

  startNetworkWatch(onNetworkRecover: (netIdChanged: boolean, netId: number) => void): void {
    this.stopNetworkWatch();
    try {
      if (typeof connection?.getDefaultNetSync === 'function') {
        const initial: connection.NetHandle = connection.getDefaultNetSync();
        this.lastPhysicalNetId = Number(initial?.netId ?? 0);
      }
    } catch (_err) {
      this.lastPhysicalNetId = 0;
    }
    try {
      if (typeof connection?.createNetConnection !== 'function') {
        return;
      }
      const conn: connection.NetConnection = connection.createNetConnection();
      this.netConn = conn;
      conn.on('netLost', (_handle: connection.NetHandle): void => {
        this.netLostObserved = true;
        RuntimeDiagnostics.record('Physical network lost while VPN active');
      });
      conn.on('netAvailable', (handle: connection.NetHandle): void => {
        const nextId: number = Number(handle?.netId ?? 0);
        if (nextId <= 0) {
          return;
        }
        const changed: boolean = this.lastPhysicalNetId > 0 && nextId !== this.lastPhysicalNetId;
        const recovered: boolean = this.netLostObserved;
        this.lastPhysicalNetId = nextId;
        this.netLostObserved = false;
        if (changed || recovered) {
          RuntimeDiagnostics.record(`Physical network available netId=${nextId} changed=${changed}`);
          onNetworkRecover(changed, nextId);
        }
      });
      conn.register((err): void => {
        if (err) {
          RuntimeDiagnostics.record(`NetConnection register warn: ${String(err.message ?? err.code)}`);
        }
      });
    } catch (err) {
      RuntimeDiagnostics.record(`Physical network watch unavailable: ${String(err)}`);
    }
  }

  stopNetworkWatch(): void {
    if (this.netConn !== null) {
      try {
        this.netConn.unregister((): void => {});
      } catch (_err) {
        // ignore unregister errors
      }
      this.netConn = null;
    }
    this.netLostObserved = false;
  }

  stopKeepAliveAndNetworkWatch(): void {
    this.stopNetworkWatch();
    BackgroundKeepAlive.stop();
  }

  async request(
    path: string,
    method: http.RequestMethod = http.RequestMethod.GET,
    body: string = '',
    readTimeout: number = 8000
  ): Promise<string> {
    const endpoint: string = this.controllerUrl;
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.secretValue.length > 0) {
      headers['Authorization'] = `Bearer ${this.secretValue}`;
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const result: http.HttpResponse = await client.request(endpoint + path, {
        method: method,
        header: headers,
        extraData: body,
        connectTimeout: 2500,
        readTimeout: readTimeout,
        usingCache: false,
        expectDataType: http.HttpDataType.STRING
      });
      if (result.responseCode < 200 || result.responseCode >= 300) {
        throw new Error(`控制器返回 HTTP ${result.responseCode}`);
      }
      return result.result === undefined || result.result === null ? '' : String(result.result);
    } finally {
      client.destroy();
    }
  }

  async checkController(): Promise<string> {
    const data: Record<string, Object> = JSON.parse(
      await this.request('/version', http.RequestMethod.GET, '', 2500)
    ) as Record<string, Object>;
    return String(data['version'] ?? 'mihomo');
  }

  async getMode(): Promise<string> {
    const data: Record<string, Object> = JSON.parse(await this.request('/configs')) as Record<string, Object>;
    return String(data['mode'] ?? 'rule');
  }

  async setMode(mode: string): Promise<void> {
    await this.request('/configs', http.RequestMethod.PATCH, JSON.stringify({ mode: mode }));
    if (await this.getMode() !== mode) {
      throw new Error('内核未确认出站模式，请重试');
    }
  }

  async selectProxy(groupName: string, proxyName: string): Promise<void> {
    await this.request(
      `/proxies/${encodeURIComponent(groupName)}`,
      http.RequestMethod.PUT,
      JSON.stringify({ name: proxyName })
    );
    const data: Record<string, Object> = JSON.parse(
      await this.request(`/proxies/${encodeURIComponent(groupName)}`)
    ) as Record<string, Object>;
    if (String(data['now'] ?? '') !== proxyName) {
      throw new Error('内核未确认节点选择，请重试');
    }
  }

  /**
   * Reloads runtime YAML in-place via mihomo REST PUT /configs?force=true without
   * dropping the active VpnConnection TUN file descriptor, matching clash-verge-rev.
   */
  async reloadRuntimeConfig(
    yamlContent: string,
    selectionsMap: Record<string, string>,
    mode: string,
    targetGroup: string = '',
    targetProxy: string = ''
  ): Promise<void> {
    if (this.filesDir.length === 0) {
      throw new Error('VPN 工作目录未初始化');
    }
    this.writePrivateFile('proxy-selections.json', JSON.stringify(selectionsMap));
    this.writePrivateFile('config.yaml', yamlContent);
    await this.request(
      '/configs?force=true',
      http.RequestMethod.PUT,
      JSON.stringify({ payload: yamlContent }),
      10000
    );
    if (mode.length > 0) {
      try {
        await this.setMode(mode);
      } catch (_modeErr) {
        // Outbound mode is already encoded in the reloaded YAML payload.
      }
    }
    const groupKeys: string[] = Object.keys(selectionsMap);
    for (let i: number = 0; i < groupKeys.length; i++) {
      const grp: string = groupKeys[i];
      const pick: string = selectionsMap[grp];
      if (pick.length > 0 && grp !== targetGroup) {
        try {
          await this.selectProxy(grp, pick);
        } catch (_selErr) {
          // Non-Selector groups may ignore manual selection.
        }
      }
    }
    if (targetGroup.length > 0 && targetProxy.length > 0) {
      await this.selectProxy(targetGroup, targetProxy);
    }
    try {
      await this.closeAllConnections();
    } catch (_closeErr) {
      // Connections may already be closed.
    }
  }

  async testProxyDelay(proxyName: string, testUrl: string, timeoutMs: number = 10000): Promise<number> {
    const encodedUrl: string = encodeURIComponent(testUrl.length > 0 ? testUrl : 'https://www.gstatic.com/generate_204');
    for (let attempt: number = 0; attempt < 2; attempt++) {
      try {
        const raw: string = await this.request(
          `/proxies/${encodeURIComponent(proxyName)}/delay?url=${encodedUrl}&timeout=${timeoutMs}`,
          http.RequestMethod.GET,
          '',
          timeoutMs + 3000
        );
        const data: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
        const delay: number = Number(data['delay'] ?? 0);
        if (delay > 0) {
          return delay;
        }
      } catch (_err) {
        // retry once on transient failure
      }
    }
    return -1;
  }

  async getConnectionsSnapshot(): Promise<LexiControllerTraffic> {
    const raw: string = await this.request('/connections', http.RequestMethod.GET, '', 3000);
    const data: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const entries: Array<Record<string, Object>> =
      Array.isArray(data['connections']) ? (data['connections'] as Array<Record<string, Object>>) : [];
    return {
      uploadTotal: Number(data['uploadTotal'] ?? 0),
      downloadTotal: Number(data['downloadTotal'] ?? 0),
      connections: entries
    };
  }

  async closeConnection(id: string): Promise<void> {
    await this.request(`/connections/${encodeURIComponent(id)}`, http.RequestMethod.DELETE);
  }

  async closeAllConnections(): Promise<void> {
    await this.request('/connections', http.RequestMethod.DELETE);
  }

  async flushDnsCache(): Promise<void> {
    try {
      await this.request('/cache/fakeip/flush', http.RequestMethod.POST);
    } catch (_err) {
      // Ignore if core runs without fake-ip DNS cache
    }
  }

  async getLocalIntranetIp(): Promise<string> {
    try {
      const networks: connection.NetHandle[] = await connection.getAllNets();
      for (let i: number = 0; i < networks.length; i++) {
        const netHandle: connection.NetHandle = networks[i];
        const caps: connection.NetCapabilities = await connection.getNetCapabilities(netHandle);
        if (!caps.networkCap?.includes(connection.NetCap.NET_CAPABILITY_NOT_VPN)) {
          continue;
        }
        const properties: connection.ConnectionProperties = await connection.getConnectionProperties(netHandle);
        if (properties.interfaceName.startsWith('tun') || properties.interfaceName.startsWith('lo')) {
          continue;
        }
        for (let j: number = 0; j < properties.linkAddresses.length; j++) {
          const link: connection.LinkAddress = properties.linkAddresses[j];
          const address: string = link.address.address;
          if (link.address.family === 1 && !address.startsWith('127.') && !address.startsWith('169.254.')) {
            return address;
          }
        }
      }
    } catch (_err) {
      // ignore in sandbox or disconnected states
    }
    return '—';
  }
}

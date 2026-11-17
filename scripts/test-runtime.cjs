/* Host-side regression tests for pure ArkTS logic. Kits/native calls are explicit test doubles;
 * these tests do not claim to verify device VPN or real proxy traffic. Run: node scripts/test-runtime.cjs */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const tsPath = process.env.LEXI_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript';
const ts = require(tsPath);
const root = path.resolve(__dirname, '..');
const cases = [];
function test(name, fn) { cases.push({ name, fn }); }

function runtime({
  loaded = false, fail = () => null, nativeThrows = false, resultFor, wrongId = false, realTimers = false,
  vpnHooks = {}
} = {}) {
  const cache = new Map();
  const calls = [];
  const disk = new Map();
  const openModes = new Map();
  const vpnState = {
    observerCount: 0, observerCallback: null, unsubscribed: 0,
    startCalls: [], stopCalls: [], tunCreates: [], tunDestroyed: 0, closedFds: [],
    nativeLaunchCalls: [], proxyLaunchCalls: [], nativeStartTunCalls: [], nativeStopCalls: 0,
    physicalNetId: 100, netConnections: [], keepAliveStarts: [], keepAliveStops: 0,
    keepAliveCancelCb: null, notifications: [], keepAliveStoppedIds: [], systemVpnActive: false,
    systemVpnAddress: '172.19.0.1'
  };
  const native = {
    nativeInitCore: () => JSON.stringify({ id: 0, result: loaded ? { initialized: true } : null, error: loaded ? null : 'CORE_UNAVAILABLE' }),
    nativeIsGoCoreLoaded: () => loaded,
    nativeGetCoreVersion: () => loaded ? 'test core' : 'Proxy core unavailable',
    nativeInvokeMethod: raw => {
      if (nativeThrows) throw Error('native failure');
      const request = JSON.parse(raw);
      calls.push(request);
      return JSON.stringify({ id: wrongId ? 'wrong-id' : request.id,
        result: request.method === 'privacy.capabilities' ? { version: 1 } : resultFor ? resultFor(request) : request.method === 'proxy.testDelay' ? { value: 48 } : { ok: true }, error: fail(request, calls) });
    },
    launchAsync: async (filesDir, secret) => {
      vpnState.nativeLaunchCalls.push({ filesDir, secret });
      return vpnHooks.launchAsync ? vpnHooks.launchAsync(filesDir, secret) : '';
    },
    startTunAsync: async fd => {
      vpnState.nativeStartTunCalls.push(fd);
      return vpnHooks.startTunAsync ? vpnHooks.startTunAsync(fd) : true;
    },
    getTunError: () => (vpnHooks.getTunError ? vpnHooks.getTunError() : 'tun failed'),
    stopAsync: async () => {
      vpnState.nativeStopCalls++;
      if (vpnHooks.stopAsync) return vpnHooks.stopAsync();
    }
  };
  const fakeFs = {
    OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4, WRITE_ONLY: 8, APPEND: 16 },
    accessSync: file => disk.has(file), readTextSync: file => disk.get(file), mkdirSync() {}, unlinkSync: file => disk.delete(file),
    openSync: (file, mode) => {
      openModes.set(file, mode);
      if (mode & 4) disk.set(file, '');
      return { fd: file };
    },
    writeSync: (file, text) => disk.set(file, (openModes.get(file) & 16) ? (disk.get(file) || '') + text : text),
    statSync: file => ({ size: Buffer.byteLength(disk.get(file) || '') }),
    closeSync: fd => { if (typeof fd === 'number') vpnState.closedFds.push(fd); },
    renameSync: (from, to) => { disk.set(to, disk.get(from)); disk.delete(from); },
  };
  const httpState = { requests: [], destroyed: 0, response: { responseCode: 200, result: '', header: {} }, throws: false };
  const network = {
    http: {
      RequestMethod: { GET: 'GET', HEAD: 'HEAD', PATCH: 'PATCH', PUT: 'PUT', POST: 'POST', DELETE: 'DELETE' },
      HttpDataType: { STRING: 0 },
      AddressFamily: { ONLY_V4: 1 },
      createHttp: () => ({
        request: async (url, options) => {
          httpState.requests.push({ url, options });
          if (httpState.throws) throw Error('HTTP failed');
          if (vpnHooks.httpHandler) return vpnHooks.httpHandler(url, options);
          return httpState.response;
        },
        destroy: () => { httpState.destroyed++; },
      })
    },
    vpnExtension: {
      startVpnExtensionAbility: async want => {
        vpnState.startCalls.push(want);
        if (vpnHooks.onStartAbility) return vpnHooks.onStartAbility(want, vpnState);
      },
      stopVpnExtensionAbility: async want => {
        vpnState.stopCalls.push(want);
        if (vpnHooks.onStopAbility) return vpnHooks.onStopAbility(want, vpnState);
      },
      createVpnObserver: () => {
        vpnState.observerCount++;
        return {
          onAuthorizationResult: cb => { vpnState.observerCallback = cb; },
          offAuthorizationResult: () => { vpnState.observerCallback = null; vpnState.unsubscribed++; }
        };
      },
      createVpnConnection: () => ({
        create: async cfg => {
          vpnState.tunCreates.push(cfg);
          vpnState.systemVpnActive = true;
          return vpnHooks.createTunFd ? vpnHooks.createTunFd(cfg) : 77;
        },
        destroy: async () => { vpnState.tunDestroyed++; vpnState.systemVpnActive = false; }
      })
    },
    VpnExtensionAbility: class VpnExtensionAbility { constructor() { this.context = { filesDir: '/sandbox' }; } },
    connection: {
      NetCap: { NET_CAPABILITY_INTERNET: 12, NET_CAPABILITY_NOT_VPN: 15 },
      NetBearType: { BEARER_WIFI: 1, BEARER_VPN: 4 },
      getDefaultNet: async () => ({ netId: vpnState.physicalNetId }),
      getDefaultNetSync: () => ({ netId: vpnState.physicalNetId }),
      getAllNets: async () => [{ netId: vpnState.physicalNetId }, ...(vpnState.systemVpnActive ? [{ netId: 900 }] : [])],
      getNetCapabilities: async net => ({ bearerTypes: [net.netId === 900 ? 4 : 1] }),
      getConnectionProperties: async net => ({ linkAddresses: net.netId === 900
        ? [{ address: { address: vpnState.systemVpnAddress, family: 1 }, prefixLength: 30 }] : [] }),
      createNetConnection: () => {
        const handlers = {};
        const conn = {
          on: (ev, cb) => { handlers[ev] = cb; },
          register: cb => { if (cb) cb(undefined); },
          unregister: cb => { if (cb) cb(undefined); },
          _emit: (ev, arg) => { if (handlers[ev]) handlers[ev](arg); }
        };
        vpnState.netConnections.push(conn);
        return conn;
      }
    }
  };
  function load(file) {
    file = path.resolve(file);
    if (cache.has(file)) return cache.get(file).exports;
    const module = { exports: {} };
    cache.set(file, module);
    const source = fs.readFileSync(file, 'utf8');
    const output = ts.transpileModule(source, { fileName: file.replace(/\.ets$/, '.ts'), compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } });
    const requireLocal = specifier => {
      if (specifier === '@kit.ArkTS') return { buffer: { Buffer, from: Buffer.from } };
      if (specifier === '@kit.CoreFileKit') return { fileIo: fakeFs };
      if (specifier === '@kit.NetworkKit') return network;
      if (specifier === '@kit.NotificationKit') return { notificationManager: {
        SlotType: { LIVE_VIEW: 6 }, ContentType: { NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW: 5 },
        publish: async request => {
          if (vpnHooks.publishNotification) await vpnHooks.publishNotification(request);
          vpnState.notifications.push(request);
        }
      } };
      if (specifier === '@kit.BackgroundTasksKit') return {
        backgroundTaskManager: {
          BackgroundMode: { DATA_TRANSFER: 1, TASK_KEEPING: 9 },
          BackgroundTaskMode: { MODE_DATA_TRANSFER: 1, MODE_TASK_KEEPING: 9 },
          BackgroundTaskSubmode: { SUBMODE_NORMAL_NOTIFICATION: 2, SUBMODE_LIVE_VIEW_NOTIFICATION: 3 },
          ContinuousTaskCancelReason: { USER_CANCEL: 1, SYSTEM_CANCEL: 2 },
          ContinuousTaskDetailedCancelReason: { USER_CANCEL_REMOVE_NOTIFICATION: 3, SYSTEM_CANCEL_DATA_TRANSFER_NOT_UPDATE: 12 },
          ContinuousTaskRequest: class { isModeSupported() { return false; } },
          on: (_type, cb) => { vpnState.keepAliveCancelCb = cb; },
          startBackgroundRunning: async (_ctx, mode) => {
            vpnState.keepAliveStarts.push(mode);
            if (vpnHooks.startBackgroundRunning) return vpnHooks.startBackgroundRunning(mode);
            return { notificationId: 71, continuousTaskId: 91 };
          },
          stopBackgroundRunning: async (_ctx, id) => {
            vpnState.keepAliveStops += 1;
            vpnState.keepAliveStoppedIds.push(id);
          },
          getAllContinuousTasks: async () => vpnState.keepAliveStarts.length > vpnState.keepAliveStops ? [{ id: 1 }] : []
        }
      };
      if (specifier === '@kit.AbilityKit') return {
        wantAgent: {
          OperationType: { START_ABILITY: 1 },
          WantAgentFlags: { UPDATE_PRESENT_FLAG: 3 },
          getWantAgent: async info => info
        }
      };
      if (specifier === '@kit.BasicServicesKit') return {};
      if (specifier === '@kit.PerformanceAnalysisKit') return {
        hilog: { info() {}, warn() {}, error() {}, debug() {} },
        hiAppEvent: { addWatcher() {}, EventType: { FAULT: 1 }, domain: { OS: 'OS' },
          event: { APP_CRASH: 'APP_CRASH', APP_FREEZE: 'APP_FREEZE', APP_KILLED: 'APP_KILLED', RESOURCE_OVERLIMIT: 'RESOURCE_OVERLIMIT' } }
      };
      if (specifier === 'libclash_bridge.so') return native;
      if (specifier.startsWith('.')) return load(path.resolve(path.dirname(file), specifier + '.ets'));
      throw Error('Unexpected import: ' + specifier);
    };
    const intervals = new Set();
    const timeouts = new Set();
    const context = vm.createContext({
      module, exports: module.exports, require: requireLocal, console, Buffer,
      setInterval: realTimers ? ((fn, ms) => { const id = setInterval(fn, Math.min(ms || 10, 10)); intervals.add(id); return id; }) : (() => 1),
      setTimeout: realTimers ? ((fn, ms) => { const id = setTimeout(() => { timeouts.delete(id); fn(); }, ms > 5000 ? ms : Math.min(ms || 1, 5)); timeouts.add(id); return id; }) : (() => 1),
      clearTimeout: realTimers ? (id => { timeouts.delete(id); clearTimeout(id); }) : (() => {}),
      clearInterval: realTimers ? (id => { intervals.delete(id); clearInterval(id); }) : (() => {})
    });
    vpnState._timers.push({ intervals, timeouts });
    vm.runInContext(output.outputText, context, { filename: file });
    return module.exports;
  }
  vpnState._timers = [];
  const dispose = () => {
    for (const bucket of vpnState._timers) {
      for (const id of bucket.intervals) clearInterval(id);
      for (const id of bucket.timeouts) clearTimeout(id);
      bucket.intervals.clear();
      bucket.timeouts.clear();
    }
  };
  const { ProxyChainConfig } = load(path.join(root, 'entry/src/main/ets/core/ProxyChainConfig.ets'));
  const { ClashUriParser } = load(path.join(root, 'entry/src/main/ets/core/ClashUriParser.ets'));
  const { YamlProfileParser } = load(path.join(root, 'entry/src/main/ets/core/YamlProfileParser.ets'));
  const { AppStateStore } = load(path.join(root, 'entry/src/main/ets/store/AppStateStore.ets'));
  const { CoreController } = load(path.join(root, 'entry/src/main/ets/core/CoreController.ets'));
  const { ThemeManager } = load(path.join(root, 'entry/src/main/ets/common/ThemeManager.ets'));
  const { ResponsiveLayout } = load(path.join(root, 'entry/src/main/ets/common/ResponsiveLayout.ets'));
  const { BackgroundKeepAlive } = load(path.join(root, 'entry/src/main/ets/core/BackgroundKeepAlive.ets'));
  const { RuntimeDiagnostics } = load(path.join(root, 'entry/src/main/ets/core/RuntimeDiagnostics.ets'));
  BackgroundKeepAlive.setAbilityContext({ bundleName: 'com.lovexjy.lexiclash' });
  const { VpnAuthorization } = load(path.join(root, 'entry/src/main/ets/core/VpnAuthorization.ets'));
  const { AppAccessControl } = load(path.join(root, 'entry/src/main/ets/core/AppAccessControl.ets'));
  const { TunConfig } = load(path.join(root, 'entry/src/main/ets/core/TunConfig.ets'));
  const LexiVpnExtension = load(path.join(root, 'entry/src/main/ets/vpnextension/LexiVpnExtension.ets')).default;
  const store = AppStateStore.getInstance();
  store.initialize('/sandbox');
  return { chain: ProxyChainConfig, uriParser: ClashUriParser, parser: YamlProfileParser, ThemeManager, ResponsiveLayout, BackgroundKeepAlive, RuntimeDiagnostics, store, AppStateStore, controller: CoreController.getInstance(), VpnAuthorization, AppAccessControl, TunConfig, LexiVpnExtension, vpnState, calls, disk, httpState, dispose };
}

const fixture = `mixed-port: 7890
mode: rule
proxies:
  - name: '入口, A'
    type: trojan
    server: entry.example
    port: 443
    password: 'secret:#, preserved'
    dialer-proxy: old-route
    ws-opts:
      path: /a
      headers:
        name: nested-header
        server: nested-server
      early-data-header-name: Sec-WebSocket-Protocol
  - {name: '出口 B', type: socks5, server: exit.example, port: 1080, username: user, password: 'p,a:ss#word', dialer-proxy: old-route, udp: false}
  - name: C
    type: http
    server: third.example
    port: 8080
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - '入口, A'
      - '出口 B'
      - C
      - DIRECT
  - name: Other
    type: select
    proxies: [C, DIRECT]
rules:
  - MATCH,Proxy
`;

async function imported(options) {
  const r = runtime(options);
  assert.equal(await r.store.addNewProfile('测试', '', 'file', fixture), '');
  return r;
}
function names(r) { return Array.from(r.store.getProxyChainDraft().nodeNames); }
function pair(r) { assert.equal(r.store.addProxyChainNode('入口, A'), ''); assert.equal(r.store.addProxyChainNode('出口 B'), ''); }

test('YAML: preserves credentials, nested options and rules; wires B through A', () => {
  const r = runtime();
  const built = r.chain.build(fixture, ['入口, A', '出口 B']);
  assert.equal(built.errorMessage, '');
  assert.ok(built.yamlContent.includes("password: 'secret:#, preserved'"));
  assert.ok(built.yamlContent.includes("password: 'p,a:ss#word'"));
  assert.ok(built.yamlContent.includes('name: nested-header'));
  assert.ok(built.yamlContent.includes('dialer-proxy: "入口, A"'));
  assert.ok(!built.yamlContent.includes('old-route'));
  assert.ok(built.yamlContent.endsWith('  - MATCH,Proxy\n'));
});
test('YAML: supports inline proxies arrays with quoted commas and nested maps', () => {
  const r = runtime();
  const yaml = `proxies: [{name: 'A, 1', type: http, server: a, port: 80, ws-opts: {headers: {Host: 'a,b'}}}, {name: B, type: socks5, server: b, port: 1080}]\nrules: [MATCH,DIRECT]`;
  const built = r.chain.build(yaml, ['A, 1', 'B']);
  assert.equal(built.errorMessage, '');
  assert.ok(built.yamlContent.includes("Host: 'a,b'"));
  assert.ok(built.yamlContent.includes('dialer-proxy: "A, 1"'));
  assert.equal(r.parser.parseYaml(yaml).proxiesCount, 2);
});
test('YAML: supports indentless sequences and quoted/escaped names', () => {
  const r = runtime();
  const yaml = 'proxies:\n- name: "A \\"quoted\\""\n  type: http\n  server: a\n  port: 80\n- name: B\n  type: http\n  server: b\n  port: 80\n';
  const parsed = r.parser.parseYaml(yaml);
  assert.equal(parsed.proxiesCount, 2);
  const built = r.chain.build(yaml, ['A "quoted"', 'B']);
  assert.equal(built.errorMessage, '');
  assert.ok(built.yamlContent.includes('dialer-proxy: "A \\"quoted\\""'));
});
test('YAML: rejects duplicate, missing, builtin nodes and aliases', () => {
  const r = runtime();
  for (const chain of [['C', 'C'], ['C', 'missing'], ['C', 'DIRECT'], ['C', 'REJECT']]) assert.notEqual(r.chain.build(fixture, chain).errorMessage, '');
  assert.notEqual(r.chain.build('proxies:\n  - *node', ['A', 'B']).errorMessage, '');
});
test('YAML: clearing follows Verge and removes all top-level dialer links', () => {
  const r = runtime();
  const built = r.chain.build(fixture, []);
  assert.equal(built.errorMessage, '');
  assert.ok(!built.yamlContent.includes('dialer-proxy:'));
});
test('YAML: an independent YAML parser confirms all other proxy fields are unchanged', () => {
  const r = runtime();
  const generated = r.chain.build(fixture, ['入口, A', '出口 B', 'C']);
  const result = spawnSync('python3', ['-c', [
    'import json, sys, yaml',
    'source, compiled = json.load(sys.stdin)',
    'a, b = yaml.safe_load(source), yaml.safe_load(compiled)',
    'for proxy in a["proxies"]: proxy.pop("dialer-proxy", None)',
    'assert b["proxies"][1].pop("dialer-proxy") == "入口, A"',
    'assert b["proxies"][2].pop("dialer-proxy") == "出口 B"',
    'assert a == b, "Fields other than dialer-proxy changed"',
  ].join('\n')], { input: JSON.stringify([fixture, generated.yamlContent]), encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
});
test('YAML: top-level comments with colons do not terminate the proxies section', () => {
  const r = runtime();
  const yaml = fixture.replace('  - {name:', '# second node: keep parsing\n  - {name:');
  const built = r.chain.build(yaml, ['入口, A', '出口 B']);
  assert.equal(built.errorMessage, '');
});
test('YAML: supports document boundaries and rejects multiple documents', () => {
  const r = runtime();
  const simple = "---\nproxies:\n  - {name: A, type: http, server: a, port: 80}\n  - {name: B, type: http, server: b, port: 80}\n...\n";
  const built = r.chain.build(simple, ['A', 'B']);
  assert.equal(built.errorMessage, '');
  assert.ok(built.yamlContent.indexOf('dialer-proxy: "A"') < built.yamlContent.indexOf('...'));
  assert.notEqual(r.chain.build(simple + '---\nmode: rule', ['A', 'B']).errorMessage, '');
});
test('Parser: nested name/server fields do not overwrite proxy metadata', () => {
  const summary = runtime().parser.parseYaml(fixture);
  assert.equal(summary.valid, true);
  assert.equal(summary.proxiesCount, 3);
  assert.equal(summary.parsedNodes[0].name, '入口, A');
  assert.equal(summary.parsedNodes[0].server, 'entry.example');
  assert.equal(summary.parsedNodes[1].udp, false);
  assert.deepEqual(Array.from(summary.parsedGroups[0].nodeNames), ['入口, A', '出口 B', 'C', 'DIRECT']);
});
test('Parser: inline member names can contain commas', () => {
  const summary = runtime().parser.parseYaml("proxies: []\nproxy-groups:\n  - name: Group\n    type: select\n    proxies: ['A, 1', B]\n");
  assert.deepEqual(Array.from(summary.parsedGroups[0].nodeNames), ['A, 1', 'B']);
});
test('Draft: duplicate prevention, reorder, remove and minimum length', async () => {
  const r = await imported();
  assert.notEqual(r.store.getProxyChainValidationError(), '');
  pair(r);
  assert.equal(r.store.getProxyChainValidationError(), '');
  assert.notEqual(r.store.addProxyChainNode('入口, A'), '');
  r.store.moveProxyChainNode(0, 1);
  assert.deepEqual(names(r), ['出口 B', '入口, A']);
  r.store.removeProxyChainNode('入口, A');
  assert.notEqual(r.store.getProxyChainValidationError(), '');
});
test('Draft: rule group changes clear nodes; global accepts independent nodes', async () => {
  const r = await imported(); pair(r);
  assert.equal(r.store.setProxyChainGroup('Other'), '');
  assert.deepEqual(names(r), []);
  assert.notEqual(r.store.addProxyChainNode('入口, A'), '');
  r.store.setOutboundMode('global');
  assert.equal(r.store.addProxyChainNode('入口, A'), '');
  assert.notEqual(r.store.addProxyChainNode('DIRECT'), '');
  r.store.setOutboundMode('direct');
  assert.notEqual(r.store.getProxyChainValidationError(), '');
});
test('Lifecycle: missing core never reports running, VPN, memory or chain success', async () => {
  const r = await imported(); pair(r);
  assert.equal(r.store.toggleRunning(), false);
  assert.equal(r.store.isRunning, false);
  assert.equal(r.store.vpnEnabled, false);
  assert.notEqual(r.store.connectProxyChain(), '');
  assert.equal(r.store.chainConnected, false);
  assert.equal(r.store.memorySnapshot.appBytes, 0);
  r.store.restartCore(); assert.equal(r.store.isRunning, false);
  assert.equal(await r.controller.testNodeDelay('C', '', 'https://example.test', 1000), -1);
  assert.equal(r.httpState.requests.length, 0);
  assert.equal(await r.controller.probeOutboundIpInfo(), null);
});
test('Connection: validates, applies full config then selects last node', async () => {
  const r = await imported({ loaded: true }); pair(r);
  assert.equal(r.store.toggleRunning(), true);
  assert.equal(r.store.vpnEnabled, false);
  r.calls.length = 0;
  assert.equal(r.store.connectProxyChain(), '');
  assert.deepEqual(r.calls.slice(0, 3).map(c => c.method), ['config.validate', 'config.setup', 'proxy.select']);
  assert.equal(r.calls[2].arguments['proxy-name'], '出口 B');
  assert.equal(r.calls[2].arguments['group-name'], 'Proxy');
  assert.ok(r.disk.get(r.calls[1].arguments.base.path).includes('dialer-proxy: "入口, A"'));
  assert.equal(typeof r.calls[1].id, 'string');
  assert.equal(r.store.isProxyChainDraftApplied(), true);
  assert.equal(r.store.disconnectProxyChain(), '');
  assert.equal(r.store.chainConnected, false);
  assert.equal(r.calls.at(-1).method, 'connection.closeAll');
  assert.equal(r.calls.at(-2).arguments['proxy-name'], 'DIRECT');
});
test('Connection: global mode selects GLOBAL and preserves source YAML', async () => {
  const r = await imported({ loaded: true }); pair(r); r.store.setOutboundMode('global');
  r.store.toggleRunning(); assert.equal(r.store.connectProxyChain(), '');
  assert.ok(r.disk.get(r.calls.at(-2).arguments.base.path).includes('mode: global'));
  assert.equal(r.calls.at(-1).arguments['group-name'], 'GLOBAL');
  assert.equal(r.store.getCurrentProfile().yamlContent, fixture);
});
test('Connection: validation failure leaves state and runtime config unchanged', async () => {
  let reject = false;
  const r = await imported({ loaded: true, fail: req => reject && req.method === 'config.validate' ? 'bad config' : null });
  pair(r); r.store.toggleRunning(); r.calls.length = 0; reject = true;
  assert.equal(r.store.connectProxyChain(), 'bad config');
  assert.deepEqual(r.calls.map(c => c.method), ['config.validate']);
  assert.equal(r.store.chainConnected, false);
});
test('Connection: failed exit selection rolls back full runtime config', async () => {
  const r = await imported({ loaded: true, fail: req => req.method === 'proxy.select' ? 'cannot select' : null });
  pair(r); r.store.toggleRunning();
  assert.equal(r.store.connectProxyChain(), 'cannot select');
  assert.equal(r.calls.at(-1).method, 'config.setup');
  assert.equal(r.disk.get(r.calls.at(-1).arguments.base.path), r.store.runtimeYaml(fixture));
  assert.equal(r.store.chainConnected, false);
});
test('Lifecycle: listener failure does not mark the application running', async () => {
  const r = await imported({ loaded: true, fail: req => req.method === 'listener.start' ? 'listen failed' : null });
  assert.equal(r.store.toggleRunning(), false); assert.equal(r.store.isRunning, false);
  assert.equal(r.store.lastOperationError, 'listen failed');
});
test('Selection: invalid group or foreign member never changes active group', async () => {
  const r = await imported(); const group = r.store.proxyGroups[0]; const before = group.selectedName;
  r.store.selectProxyInGroup('missing-id', 'C'); assert.equal(group.selectedName, before);
  r.store.selectProxyInGroup(group.id, 'missing-node'); assert.equal(group.selectedName, before);
});
test('Persistence: profiles, drafts, order and selection survive cold store reload', async () => {
  const r = await imported(); pair(r); r.store.moveProxyChainNode(1, 0);
  r.store.selectProxyInGroup(r.store.proxyGroups[0].id, 'C');
  r.store.themeMode = 'light'; r.store.persistState();
  assert.ok(r.disk.has('/sandbox/lexiclash-state.json'));
  const savedId = r.store.currentProfileId;
  r.AppStateStore.instance = null;
  const restored = r.AppStateStore.getInstance(); restored.initialize('/sandbox');
  assert.equal(restored.currentProfileId, savedId);
  assert.equal(restored.profiles.length, 1);
  assert.deepEqual(Array.from(restored.getProxyChainDraft().nodeNames), ['出口 B', '入口, A']);
  assert.equal(restored.proxyGroups[0].selectedName, 'C');
  assert.equal(restored.themeMode, 'light'); assert.equal(restored.chainConnected, false);
});
test('Profiles: switching and deleting isolate chain drafts', async () => {
  const r = await imported(); pair(r); const first = r.store.currentProfileId;
  await r.store.addNewProfile('第二个', '', 'file', fixture);
  assert.deepEqual(names(r), []);
  r.store.selectProfile(first); assert.deepEqual(names(r), ['入口, A', '出口 B']);
  const before = r.store.currentProfileId; r.store.selectProfile('missing-profile'); assert.equal(r.store.currentProfileId, before);
  r.store.deleteProfile(first); assert.notEqual(r.store.currentProfileId, first);
});
test('Profiles: subscription update invalidates removed chain nodes', async () => {
  const r = await imported(); pair(r);
  const saved = r.store.saveProfileYaml(r.store.currentProfileId, fixture.replaceAll('出口 B', 'New Exit'));
  assert.equal(saved.valid, true); assert.notEqual(r.store.getProxyChainValidationError(), '');
});
test('Profiles: base64 YAML and share-link URIs convert to complete YAML while invalid inputs are rejected', async () => {
  const r = runtime();
  assert.equal(await r.store.addNewProfile('base64', '', 'file', Buffer.from(fixture).toString('base64')), '');
  assert.equal(r.store.getCurrentProfile().yamlContent, fixture);
  assert.equal(await r.store.addNewProfile('uri', '', 'file', 'socks5://alice:s%40ecret@socks.example:1080?udp=1#HK-SOCKS5\ntrojan://password@demo.invalid:443?sni=demo.invalid#TestTrojan'), '');
  const convertedYaml = r.store.getCurrentProfile().yamlContent;
  assert.ok(convertedYaml.includes('proxies:'));
  assert.ok(convertedYaml.includes('type: socks5'));
  assert.ok(convertedYaml.includes('username: "alice"'));
  assert.ok(convertedYaml.includes('proxy-groups:'));
  assert.equal(r.store.proxyNodes.some(n => n.name === 'HK-SOCKS5' && n.protocol === 'SOCKS5'), true);
  assert.notEqual(await r.store.addNewProfile('baduri', '', 'file', 'ftp://unsupported.invalid:21#Bad'), '');
  assert.equal(r.store.profiles.length, 2);
});
test('HTTP: subscription requests destroy resources on success and failure', async () => {
  const r = runtime(); r.httpState.response.result = fixture;
  const reply = await r.controller.fetchSubscriptionFromUrl('clash://install-config?url=https%3A%2F%2Fexample.test%2Fsub%3Fa%3D1%26b%3D2&name=test');
  assert.equal(reply.ok, true);
  assert.equal(r.httpState.requests[0].url, 'https://example.test/sub?a=1&b=2');
  r.httpState.throws = true; assert.equal((await r.controller.fetchSubscriptionFromUrl('https://example.test')).ok, false);
  assert.equal(r.httpState.destroyed, 2);
});
test('Controller: native exceptions and malformed responses never become success', () => {
  const r = runtime({ loaded: true, nativeThrows: true });
  assert.notEqual(r.controller.execute('listener.start'), '');
  assert.notEqual(r.controller.responseError('not JSON'), '');
  assert.notEqual(r.controller.responseError('{"id":1}'), '');
});
test('Controller: wrong response id cannot confirm an operation', () => {
  const r = runtime({ loaded: true, wrongId: true });
  assert.notEqual(r.controller.execute('listener.start'), '');
});
test('Controller: FlClash validation errors returned as result strings are rejected', () => {
  const r = runtime({ loaded: true, resultFor: () => 'configuration is invalid' });
  assert.equal(r.controller.execute('config.validate', JSON.stringify({ yaml: fixture })), 'configuration is invalid');
  assert.equal([...r.disk.keys()].filter(file => file.endsWith('.yaml')).length, 0);
});
test('Controller: delay and memory follow FlClash response schemas', async () => {
  const r = runtime({ loaded: true, resultFor: req => req.method === 'core.memory'
    ? { rss: 100, 'heap-inuse': 50, 'heap-idle': 20, 'stack-inuse': 10, 'runtime-other': 20 }
    : { value: 48 } });
  assert.equal(await r.controller.testNodeDelay('出口 B', '', 'https://example.test', 1000), 48);
  assert.equal(r.controller.queryMemoryStats(true).coreRssBytes, 100);
  assert.equal(r.controller.queryMemoryStats(true).heapInuseBytes, 50);
  assert.equal(r.httpState.requests.length, 0);
});
test('Controller: outbound IP comes from core-routed response with no fabricated quality score', async () => {
  const r = runtime({ loaded: true, resultFor: () => ({ body: JSON.stringify({ success: true,
    ip: '192.0.2.1', country_code: 'US', country: 'United States', connection: { isp: 'Test ISP', asn: 64500 }, timezone: { id: 'Etc/UTC' } }) }) });
  const info = await r.controller.probeOutboundIpInfo();
  assert.equal(info.ip, '192.0.2.1'); assert.equal(info.asn, 'AS64500'); assert.equal(info.qualityScore, 0);
  assert.deepEqual(r.calls.at(-1).arguments.urls, ['https://ipwho.is/']);
  assert.equal(r.httpState.requests.length, 0);
});
test('Lifecycle: saved proxy selection and test URL are included in setup', async () => {
  const r = await imported({ loaded: true });
  r.store.selectProxyInGroup(r.store.proxyGroups[0].id, 'C');
  r.store.toggleRunning();
  const setup = r.calls.find(call => call.method === 'config.setup');
  assert.equal(setup.arguments['selected-map'].Proxy, 'C');
  assert.equal(setup.arguments.options['test-url'], r.store.testUrl);
});

test('VPN: VpnAuthorization retains single observer across repeated attempts', () => {
  const r = runtime({ loaded: true });
  r.VpnAuthorization.subscribe(() => {});
  r.VpnAuthorization.unsubscribe();
  r.VpnAuthorization.subscribe(() => {});
  r.VpnAuthorization.unsubscribe();
  assert.equal(r.vpnState.observerCount, 1);
  assert.equal(r.vpnState.unsubscribed, 2);
});

test('VPN: toggleRunningAsync launches LexiVpnExtension, creates TUN, patches mode, and disconnects cleanly', async () => {
  let extension = null;
  let currentMode = 'rule';
  const r = runtime({
    loaded: true,
    realTimers: true,
    vpnHooks: {
      onStartAbility: () => {
        extension = new r.LexiVpnExtension();
        extension.onCreate();
      },
      onStopAbility: () => {
        if (extension) extension.onDestroy();
      },
      httpHandler: (url, options) => {
        if (url.endsWith('/version')) return { responseCode: 200, result: JSON.stringify({ version: 'mihomo-test' }) };
        if (url.endsWith('/configs') && options.method === 'PATCH') {
          currentMode = JSON.parse(options.extraData).mode;
          return { responseCode: 204, result: '' };
        }
        if (url.endsWith('/configs')) return { responseCode: 200, result: JSON.stringify({ mode: currentMode }) };
        return { responseCode: 200, result: JSON.stringify({ up: 0, down: 0, connections: [] }) };
      }
    }
  });
  await r.store.addNewProfile('主配置', '', 'file', fixture);
  r.store.selectProxyInGroup(r.store.proxyGroups[0].id, 'C');
  r.store.setOutboundMode('global');

  try {
    const connected = await r.store.toggleRunningAsync();
    assert.equal(connected, true);
    assert.equal(r.store.isRunning, true);
    assert.equal(r.store.vpnEnabled, true);
    assert.equal(r.store.coreStatus, 'connected');
    assert.equal(r.vpnState.nativeLaunchCalls.length, 1);
    assert.deepEqual(r.vpnState.nativeStartTunCalls, [77]);
    assert.equal(r.vpnState.tunCreates[0].mtu, 1400);
    assert.deepEqual(Array.from(r.vpnState.tunCreates[0].dnsAddresses), ['172.19.0.2']);
    assert.match(r.disk.get('/sandbox/config.yaml'), /^mode: global$/m);
    assert.equal(r.httpState.requests.some(req => req.options.method === 'PATCH'), false);
    assert.equal(JSON.parse(r.disk.get('/sandbox/proxy-selections.json')).Proxy, 'C');
    assert.equal(JSON.parse(r.disk.get('/sandbox/vpn-status.json')).status, 'running');

    const disconnected = await r.store.toggleRunningAsync();
    assert.equal(disconnected, true);
    assert.equal(r.store.isRunning, false);
    assert.equal(r.store.vpnEnabled, false);
    assert.equal(r.store.coreStatus, 'disconnected');
    assert.equal(r.vpnState.tunDestroyed, 1);
    assert.equal(r.vpnState.nativeStopCalls, 1);
  } finally {
    r.dispose();
  }
});

test('VPN: authorization denial and TUN failure leave VPN disconnected with error message', async () => {
  const denied = runtime({
    loaded: true,
    realTimers: true,
    vpnHooks: {
      onStartAbility: (_want, state) => new Promise(() => {
        setTimeout(() => { if (state.observerCallback) state.observerCallback(false); }, 5);
      }),
      httpHandler: () => { throw Error('ECONNREFUSED'); }
    }
  });
  try {
    await denied.store.addNewProfile('主配置', '', 'file', fixture);
    const denialOk = await denied.store.toggleRunningAsync();
    assert.equal(denialOk, false);
    assert.equal(denied.store.isRunning, false);
    assert.equal(denied.store.vpnEnabled, false);
    assert.match(denied.store.lastOperationError, /未授权/);
  } finally {
    denied.dispose();
  }

  let ext = null;
  const tunFail = runtime({
    loaded: true,
    realTimers: true,
    vpnHooks: {
      onStartAbility: () => {
        ext = new tunFail.LexiVpnExtension();
        ext.onCreate();
      },
      onStopAbility: () => { if (ext) ext.onDestroy(); },
      startTunAsync: async () => false,
      getTunError: () => 'bad tun fd 77'
    }
  });
  try {
    await tunFail.store.addNewProfile('主配置', '', 'file', fixture);
    const tunOk = await tunFail.store.toggleRunningAsync();
    assert.equal(tunOk, false);
    assert.equal(tunFail.store.isRunning, false);
    assert.equal(tunFail.store.vpnEnabled, false);
    assert.match(tunFail.store.lastOperationError, /bad tun fd 77/);
    assert.equal(tunFail.vpnState.tunDestroyed, 1);
    assert.equal(tunFail.vpnState.nativeStopCalls, 1);
  } finally {
    tunFail.dispose();
  }
});

test('UriParser: parses socks5/http/ss/ssr/vmess/vless/trojan/hy/hy2/tuic/wg/anytls matching clash-verge-rev', () => {
  const r = runtime();
  const socks = r.uriParser.parseUri('socks5://u1:p%3A1@198.51.100.2:1080?tls=1&udp=1&skip-cert-verify=1&ip-version=ipv4#SocksExit');
  assert.equal(socks.type, 'socks5');
  assert.equal(socks.name, 'SocksExit');
  assert.equal(socks.server, '198.51.100.2');
  assert.equal(socks.port, 1080);
  assert.equal(socks.username, 'u1');
  assert.equal(socks.password, 'p:1');
  assert.equal(socks.tls, true);
  assert.equal(socks.udp, true);
  assert.equal(socks.skipCertVerify, true);
  assert.equal(socks.ipVersion, 'ipv4');

  const http = r.uriParser.parseUri('https://user:pass@proxy.example:8443?skip-cert-verify=1#HttpTls');
  assert.equal(http.type, 'http');
  assert.equal(http.tls, true);
  assert.equal(http.port, 8443);

  const ssUserInfo = Buffer.from('aes-256-gcm:secret-ss').toString('base64');
  const ss = r.uriParser.parseUri(`ss://${ssUserInfo}@ss.example:8388?uot=1&tfo=1#SSNode`);
  assert.equal(ss.type, 'ss');
  assert.equal(ss.cipher, 'aes-256-gcm');
  assert.equal(ss.password, 'secret-ss');
  assert.equal(ss.udpOverTcp, true);

  const vmessJson = Buffer.from(JSON.stringify({ ps: 'VM', add: 'vm.example', port: '443', id: 'uuid-1', scy: 'auto', net: 'ws', host: 'cdn.example', path: '/ws', tls: 'tls' })).toString('base64');
  const vmess = r.uriParser.parseUri(`vmess://${vmessJson}`);
  assert.equal(vmess.type, 'vmess');
  assert.equal(vmess.name, 'VM');
  assert.equal(vmess.wsOpts.path, '/ws');

  const vless = r.uriParser.parseUri('vless://uuid-2@vl.example:443?security=reality&sni=www.apple.com&fp=chrome&pbk=pub123&sid=abcd&flow=xtls-rprx-vision#VLReality');
  assert.equal(vless.type, 'vless');
  assert.equal(vless.flow, 'xtls-rprx-vision');
  assert.equal(vless.realityOpts.publicKey, 'pub123');
  assert.equal(vless.realityOpts.shortId, 'abcd');

  const hy2 = r.uriParser.parseUri('hy2://pwd-hy2@hy2.example:443?sni=hy2.example&insecure=1&obfs=salamander&obfs-password=obfspwd#HY2');
  assert.equal(hy2.type, 'hysteria2');
  assert.equal(hy2.obfs, 'salamander');

  const tuic = r.uriParser.parseUri('tuic://uuid-t:pass-t@tuic.example:443?congestion_controller=bbr&alpn=h3#TuicNode');
  assert.equal(tuic.type, 'tuic');
  assert.equal(tuic.congestionController, 'bbr');

  const wg = r.uriParser.parseUri('wg://privKey==@wg.example:51820?publickey=pubKey==&address=10.0.0.2/32&mtu=1280#WG');
  assert.equal(wg.type, 'wireguard');
  assert.equal(wg.ip, '10.0.0.2');
  assert.equal(wg.mtu, 1280);

  const anytls = r.uriParser.parseUri('anytls://any-pass@any.example:443?sni=any.example&fp=chrome#AnyTLS');
  assert.equal(anytls.type, 'anytls');
  assert.equal(anytls.password, 'any-pass');

  const fullYaml = r.uriParser.buildCompleteYamlFromEntries([socks, vless, hy2]);
  const pyCheck = spawnSync('python3', ['-c', 'import sys, yaml; d = yaml.safe_load(sys.stdin.read()); assert len(d["proxies"]) == 3; assert d["proxies"][0]["type"] == "socks5"'], {
    input: fullYaml, encoding: 'utf8'
  });
  assert.equal(pyCheck.status, 0, pyCheck.stderr);
  assert.throws(() => r.uriParser.parseUri('ftp://bad.example:21'));
});

test('ProfileSeq & Chain: prepend/append/delete proxies (clash-verge-rev seq semantics) and readChain', async () => {
  const r = await imported({ loaded: true });
  const pre = r.uriParser.parseUri('socks5://u:p@pre.example:1080#前置-Socks5');
  const app = r.uriParser.parseUri('socks5://u2:p2@exit.socks:1080#落地-Socks5');
  assert.equal(r.store.applyProfileProxiesEdit(r.store.currentProfileId, [pre], [app], ['C']), '');
  const updatedYaml = r.store.getCurrentProfile().yamlContent;
  assert.ok(!updatedYaml.includes('\n  - name: C\n'));
  const listed = Array.from(r.uriParser.listProfileProxyBlocks(updatedYaml)).map(x => x.name);
  assert.equal(listed[0], '前置-Socks5');
  assert.equal(listed[listed.length - 1], '落地-Socks5');
  assert.ok(r.store.proxyGroups[0].nodeNames.includes('前置-Socks5'));
  assert.ok(r.store.proxyGroups[0].nodeNames.includes('落地-Socks5'));
  assert.ok(!r.store.proxyGroups[0].nodeNames.includes('C'));

  const chained = r.chain.build(updatedYaml, ['入口, A', '落地-Socks5']);
  assert.equal(chained.errorMessage, '');
  assert.deepEqual(Array.from(r.chain.readChain(chained.yamlContent, '落地-Socks5')), ['入口, A', '落地-Socks5']);
});

test('VPN Chain: connectProxyChainAsync hot-reloads active VPN via PUT /configs?force=true without tunnel drop', async () => {
  let extension = null;
  let putConfigPayloads = [];
  let putSelections = [];
  let deletedConnections = 0;
  let currentMode = 'rule';
  const r = runtime({
    loaded: true,
    realTimers: true,
    vpnHooks: {
      onStartAbility: () => { extension = new r.LexiVpnExtension(); extension.onCreate(); },
      onStopAbility: () => { if (extension) extension.onDestroy(); },
      httpHandler: (url, options) => {
        if (url.endsWith('/version')) return { responseCode: 200, result: JSON.stringify({ version: 'mihomo-test' }) };
        if (url.includes('/configs?force=true') && options.method === 'PUT') {
          putConfigPayloads.push(JSON.parse(options.extraData).payload);
          return { responseCode: 204, result: '' };
        }
        if (url.endsWith('/configs') && options.method === 'PATCH') {
          currentMode = JSON.parse(options.extraData).mode;
          return { responseCode: 204, result: '' };
        }
        if (url.endsWith('/configs')) return { responseCode: 200, result: JSON.stringify({ mode: currentMode }) };
        if (url.includes('/proxies/') && options.method === 'PUT') {
          const name = JSON.parse(options.extraData).name;
          putSelections.push({ group: decodeURIComponent(url.split('/proxies/')[1]), name });
          return { responseCode: 204, result: '' };
        }
        if (url.includes('/proxies/')) {
          const group = decodeURIComponent(url.split('/proxies/')[1]);
          const last = [...putSelections].reverse().find(s => s.group === group);
          return { responseCode: 200, result: JSON.stringify({ now: last ? last.name : 'DIRECT' }) };
        }
        if (url.endsWith('/connections') && options.method === 'DELETE') {
          deletedConnections++;
          return { responseCode: 204, result: '' };
        }
        return { responseCode: 200, result: JSON.stringify({ up: 0, down: 0, connections: [] }) };
      }
    }
  });
  try {
    await r.store.addNewProfile('主配置', '', 'file', fixture);
    assert.equal(r.store.importUriTextToProfile(r.store.currentProfileId, 'append', 'socks5://u:p@exit.socks:1080#Socks落地'), '');
    assert.equal(await r.store.toggleRunningAsync(), true);
    assert.equal(r.store.addProxyChainNode('入口, A'), '');
    assert.equal(r.store.addProxyChainNode('Socks落地'), '');

    assert.equal(await r.store.connectProxyChainAsync(), '');
    assert.equal(r.store.chainConnected, true);
    assert.equal(r.vpnState.startCalls.length, 1); // TUN did not restart!
    assert.equal(putConfigPayloads.length, 1);
    assert.ok(putConfigPayloads[0].includes('dialer-proxy: "入口, A"'));
    assert.equal(putSelections.at(-1).name, 'Socks落地');
    assert.ok(deletedConnections >= 1);

    assert.equal(await r.store.disconnectProxyChainAsync(), '');
    assert.equal(r.store.chainConnected, false);
    assert.equal(putConfigPayloads.length, 2);
    assert.ok(!putConfigPayloads[1].includes('dialer-proxy:'));
    assert.equal(putSelections.at(-1).name, 'DIRECT');

    await r.store.toggleRunningAsync();
  } finally {
    r.dispose();
  }
});

test('Chain Imported Nodes: lists all imported nodes, resolves active selection through nested groups, and picks direct-node Selector', async () => {
  const nestedSub = `
proxies:
  - { name: HK-01, type: trojan, server: hk1.example, port: 443, password: p1 }
  - { name: US-02, type: socks5, server: us2.example, port: 1080, username: u, password: p2 }
proxy-groups:
  - name: MainSelect
    type: select
    proxies: [AutoGroup, DIRECT]
  - name: AutoGroup
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 300
    proxies: [HK-01, US-02]
  - name: ManualNodes
    type: select
    proxies: [HK-01, US-02, DIRECT]
rules:
  - MATCH,MainSelect
`;
  const r = runtime({ loaded: true });
  try {
    assert.equal(await r.store.addNewProfile('机场订阅', '', 'file', nestedSub), '');
    const importedNodes = r.store.getImportedProfileNodes();
    assert.deepEqual(Array.from(importedNodes).map(n => n.name), ['HK-01', 'US-02']);

    // MainSelect only contains [AutoGroup, DIRECT], so chain draft must prefer ManualNodes (which has direct proxy nodes)
    const draft = r.store.getProxyChainDraft();
    assert.equal(draft.targetGroup, 'ManualNodes');
    assert.deepEqual(Array.from(r.store.getChainCandidates()).map(n => n.name), ['HK-01', 'US-02']);

    // Selecting US-02 in ManualNodes makes getActiveSelectedProxyNode return US-02
    const manualGrp = r.store.proxyGroups.find(g => g.name === 'ManualNodes');
    r.store.selectProxyInGroup(manualGrp.id, 'US-02');
    assert.equal(r.store.getActiveSelectedProxyNode().name, 'US-02');

    // Even if draft targets MainSelect -> AutoGroup -> HK-01, active selected leaf node still resolves cleanly
    r.store.setProxyChainGroup('MainSelect');
    assert.equal(r.store.getActiveSelectedProxyNode().name, 'HK-01');
  } finally {
    r.dispose();
  }
});

test('Indent Repair & Prepend: preserves 4-space subscription indent on prepend and heals previously mixed-indent YAML', async () => {
  const fourSpaceSub = [
    'mixed-port: 7890',
    'proxies:',
    "    - { name: 'HK-Node-1', type: vless, server: hk1.example.com, port: 443, uuid: 11111111-1111-1111-1111-111111111111, reality-opts: { public-key: abc, short-id: def } }",
    "    - { name: 'SG-Node-2', type: trojan, server: sg2.example.com, port: 443, password: secret }",
    'proxy-groups:',
    '  - name: Main',
    '    type: select',
    '    proxies:',
    '      - HK-Node-1',
    '      - SG-Node-2',
    '      - DIRECT',
    'rules:',
    '  - MATCH,Main',
  ].join('\n');
  const r = runtime({ loaded: true });
  try {
    assert.equal(await r.store.addNewProfile('4Space', '', 'file', fourSpaceSub), '');
    assert.equal(r.store.importUriTextToProfile(r.store.currentProfileId, 'prepend', 'socks5://u:p@38.246.131.191:443#SOCKS5-Exit'), '');
    const importedAfterPrepend = r.store.getImportedProfileNodes();
    assert.deepEqual(Array.from(importedAfterPrepend).map(n => n.name), ['SOCKS5-Exit', 'HK-Node-1', 'SG-Node-2']);
    const built = r.chain.build(r.store.getCurrentProfile().yamlContent, ['HK-Node-1', 'SOCKS5-Exit']);
    assert.equal(built.errorMessage, '');
    const pyCheck = spawnSync('python3', ['-c', 'import sys, yaml; cfg = yaml.safe_load(sys.stdin.read()); assert len(cfg["proxies"]) == 3'], { input: built.yamlContent, encoding: 'utf8' });
    assert.equal(pyCheck.status, 0, pyCheck.stderr);

    // Also test healing an already-broken mixed-indent (2-space + 4-space) YAML from disk
    const brokenMixed = [
      'proxies:',
      '  - name: "SOCKS5-Exit"',
      '    type: socks5',
      '    server: "38.246.131.191"',
      '    port: 443',
      '    username: "u"',
      '    password: "p"',
      "    - { name: 'HK-Node-1', type: vless, server: hk1.example.com, port: 443 }",
      "    - { name: 'SG-Node-2', type: trojan, server: sg2.example.com, port: 443, password: secret }",
      'proxy-groups:',
      '  - name: Main',
      '    type: select',
      '    proxies: [SOCKS5-Exit, HK-Node-1, SG-Node-2, DIRECT]',
    ].join('\n');
    const repairedSummary = r.parser.parseYaml(brokenMixed);
    assert.equal(repairedSummary.proxiesCount, 3);
    assert.deepEqual(Array.from(repairedSummary.parsedNodes).map(n => n.name), ['SOCKS5-Exit', 'HK-Node-1', 'SG-Node-2']);
  } finally {
    r.dispose();
  }
});

test('VPN Outbound Mode: switching rule/global/direct syncs GLOBAL group & flushes connections', async () => {
  let extension = null;
  let currentMode = 'rule';
  const groupState = { Proxy: '入口, A', GLOBAL: 'DIRECT' };
  let closeAllCount = 0;
  const r = runtime({
    loaded: true,
    realTimers: true,
    vpnHooks: {
      onStartAbility: () => {
        extension = new r.LexiVpnExtension();
        extension.onCreate();
      },
      onStopAbility: () => {
        if (extension) extension.onDestroy();
      },
      httpHandler: (url, options) => {
        if (url.endsWith('/version')) return { responseCode: 200, result: JSON.stringify({ version: 'mihomo-test' }) };
        if (url.endsWith('/configs') && options.method === 'PATCH') {
          currentMode = JSON.parse(options.extraData).mode;
          return { responseCode: 204, result: '' };
        }
        if (url.endsWith('/configs')) return { responseCode: 200, result: JSON.stringify({ mode: currentMode }) };
        if (url.includes('/proxies/')) {
          const grp = decodeURIComponent(url.split('/proxies/')[1]);
          if (options.method === 'PUT') {
            groupState[grp] = JSON.parse(options.extraData).name;
            return { responseCode: 204, result: '' };
          }
          return { responseCode: 200, result: JSON.stringify({ now: groupState[grp] || '' }) };
        }
        if (url.endsWith('/connections') && options.method === 'DELETE') {
          closeAllCount += 1;
          return { responseCode: 204, result: '' };
        }
        return { responseCode: 200, result: JSON.stringify({ uploadTotal: 0, downloadTotal: 0, connections: [] }) };
      }
    }
  });
  try {
    await r.store.addNewProfile('主配置', '', 'file', fixture);
    r.store.selectProxyInGroup(r.store.proxyGroups[0].id, '出口 B');
    const ok = await r.store.toggleRunningAsync();
    assert.equal(ok, true);
    assert.equal(currentMode, 'rule');
    assert.equal(JSON.parse(r.disk.get('/sandbox/proxy-selections.json')).GLOBAL, '出口 B');

    // Switch to global -> must patch mode AND select GLOBAL to the active node ('出口 B'), never DIRECT
    r.store.setOutboundMode('global');
    await new Promise(res => setTimeout(res, 60));
    assert.equal(currentMode, 'global');
    assert.equal(groupState.GLOBAL, '出口 B');
    assert.ok(closeAllCount >= 1);

    // Selecting another node in Proxies while in global mode must also sync GLOBAL
    r.store.selectProxyInGroup(r.store.proxyGroups[0].id, 'C');
    await new Promise(res => setTimeout(res, 60));
    assert.equal(groupState.Proxy, 'C');
    assert.equal(groupState.GLOBAL, 'C');

    // Switch to direct and back to rule cleanly
    r.store.setOutboundMode('direct');
    await new Promise(res => setTimeout(res, 60));
    assert.equal(currentMode, 'direct');
    let reloaded = r.httpState.requests.filter(req => req.url.includes('/configs?force=true')).at(-1);
    assert.equal(JSON.parse(JSON.parse(reloaded.options.extraData).payload.split('\n').find(line => line.startsWith('lexiclash: ')).slice(11)).mode, 'direct');
    r.store.setOutboundMode('rule');
    await new Promise(res => setTimeout(res, 60));
    assert.equal(currentMode, 'rule');
    reloaded = r.httpState.requests.filter(req => req.url.includes('/configs?force=true')).at(-1);
    assert.equal(JSON.parse(JSON.parse(reloaded.options.extraData).payload.split('\n').find(line => line.startsWith('lexiclash: ')).slice(11)).mode, 'rule');

    await r.store.toggleRunningAsync();
  } finally {
    r.dispose();
  }
});

test('ThemeManager: countryFlagEmoji & countryDisplayName treat TW as China PR flag', () => {
  const { ThemeManager } = runtime();
  assert.equal(ThemeManager.countryFlagEmoji('CN', 'China'), '🇨🇳');
  assert.equal(ThemeManager.countryFlagEmoji('TW', 'Taiwan'), '🇨🇳');
  assert.equal(ThemeManager.countryFlagEmoji('tw', ''), '🇨🇳');
  assert.equal(ThemeManager.countryFlagEmoji('', '中国台湾'), '🇨🇳');
  assert.equal(ThemeManager.countryFlagEmoji('HK', 'Hong Kong'), '🇭🇰');
  assert.equal(ThemeManager.countryFlagEmoji('SG', 'Singapore'), '🇸🇬');
  assert.equal(ThemeManager.countryFlagEmoji('US', 'United States'), '🇺🇸');
  assert.equal(ThemeManager.countryDisplayName('TW', 'Taiwan', 'zh_CN'), '中国台湾');
  assert.equal(ThemeManager.countryDisplayName('CN', 'China', 'zh_CN'), '中国');
  assert.equal(ThemeManager.countryDisplayName('HK', 'Hong Kong', 'zh_CN'), '中国香港');
  assert.equal(ThemeManager.countryDisplayName('SG', 'Singapore', 'zh_CN'), '新加坡');
});

test('IP Classification: derives genuine ipType & qualityLevel without fabricating scores', () => {
  const { controller } = runtime();
  const CoreCls = controller.constructor;
  const plain = v => JSON.parse(JSON.stringify(v));
  assert.deepEqual(plain(CoreCls.classifyOutboundIp('Amazon.com, Inc.', 'AS16509')), { ipType: 'DataCenter', qualityLevel: 'normal' });
  assert.deepEqual(plain(CoreCls.classifyOutboundIp('GLOBAL COMMUNICATION NETWORK LIMITED', 'AS152179', { isHosting: true, hasIntelFlags: true })), { ipType: 'DataCenter', qualityLevel: 'normal' });
  assert.deepEqual(plain(CoreCls.classifyOutboundIp('FDCservers.net', 'AS30058', { isProxy: true })), { ipType: 'DataCenter', qualityLevel: 'risky' });
  assert.deepEqual(plain(CoreCls.classifyOutboundIp('China Telecom', 'AS4134', { isHosting: false, hasIntelFlags: true })), { ipType: 'Residential', qualityLevel: 'good' });
  assert.deepEqual(plain(CoreCls.classifyOutboundIp('T-Mobile USA', 'AS21928', { isMobile: true, hasIntelFlags: true })), { ipType: 'Mobile', qualityLevel: 'good' });
  assert.deepEqual(plain(CoreCls.classifyOutboundIp('Unknown Transit Co', 'AS999999', { isAbuser: true })), { ipType: 'Business', qualityLevel: 'risky' });
  assert.deepEqual(plain(CoreCls.classifyOutboundIp('Mystery Operator', 'AS999999')), { ipType: '', qualityLevel: 'normal' });
});

test('ResponsiveLayout: computes phone, tablet, and PC 2in1 breakpoints', () => {
  const { ResponsiveLayout } = runtime();
  assert.equal(ResponsiveLayout.isCompact(390), true);
  assert.equal(ResponsiveLayout.dashboardColumns(390), 1);
  assert.equal(ResponsiveLayout.proxyColumnsTemplate(390), '1fr 1fr');

  assert.equal(ResponsiveLayout.isMedium(768), true);
  assert.equal(ResponsiveLayout.dashboardColumns(768), 2);
  assert.equal(ResponsiveLayout.proxyColumnsTemplate(768), '1fr 1fr 1fr');
  assert.equal(ResponsiveLayout.floatingBarWidth(768, 'floating'), 480);

  assert.equal(ResponsiveLayout.isExpanded(1280), true);
  assert.equal(ResponsiveLayout.dashboardColumns(1280), 3);
  assert.equal(ResponsiveLayout.proxyColumnsTemplate(1280), '1fr 1fr 1fr 1fr');
  assert.equal(ResponsiveLayout.bottomContentPadding(1280, 0), 28);
  assert.equal(ResponsiveLayout.bottomContentPadding(390, 14), 118);
  assert.equal(ResponsiveLayout.secondaryBottomPadding(0), 28);
  assert.equal(ResponsiveLayout.secondaryBottomPadding(14), 42);
});

test('KeepAlive & Network Recovery: injects keep-alive YAML, tracks continuous task, pauses/resumes polling, and keeps the tunnel on netId change', async () => {
  let extension = null;
  const r = runtime({
    loaded: true,
    realTimers: true,
    vpnHooks: {
      onStartAbility: () => {
        extension = new r.LexiVpnExtension();
        extension.onCreate();
      },
      onStopAbility: () => {
        if (extension) extension.onDestroy();
      },
      httpHandler: (url, options) => {
        if (url.endsWith('/version')) return { responseCode: 200, result: JSON.stringify({ version: 'mihomo-test' }) };
        if (url.endsWith('/configs') && options.method === 'PATCH') return { responseCode: 204, result: '' };
        if (url.endsWith('/configs')) return { responseCode: 200, result: JSON.stringify({ mode: 'rule' }) };
        if (url.includes('/proxies/')) return { responseCode: 200, result: JSON.stringify({ now: '出口 B' }) };
        if (url.endsWith('/connections')) return { responseCode: 200, result: JSON.stringify({ uploadTotal: 1048576, downloadTotal: 2097152, connections: [] }) };
        if (url.endsWith('/cache/fakeip/flush')) return { responseCode: 204, result: '' };
        return { responseCode: 200, result: '{}' };
      }
    }
  });
  try {
    r.BackgroundKeepAlive.setAbilityContext({ bundleName: 'com.lovexjy.lexiclash' });
    await r.store.addNewProfile('主配置', '', 'file', fixture);
    const started = await r.store.toggleRunningAsync();
    assert.equal(started, true);
    assert.ok(r.disk.get('/sandbox/config.yaml').includes('keep-alive-interval: 15'));
    assert.ok(r.disk.get('/sandbox/config.yaml').includes('keep-alive-idle: 60'));
    await new Promise(resolve => setTimeout(resolve, 15)); // Notifications finish after connection readiness.
    assert.equal(r.vpnState.keepAliveStarts.length, 1);
    assert.equal(r.BackgroundKeepAlive.isActive(), true);

    // Aged status timestamp (>15s during OS sleep) stays healthy if /version controller answers
    const st = JSON.parse(r.disk.get('/sandbox/vpn-status.json'));
    st.updatedAt = Date.now() - 60000;
    r.disk.set('/sandbox/vpn-status.json', JSON.stringify(st));
    assert.equal(await r.store.vpnManager.isSessionHealthy(), true);

    // Backgrounding pauses heavy 1s polling; foregrounding resumes cleanly without dropping VPN
    r.store.setAppInForeground(false);
    await new Promise(res => setTimeout(res, 25));
    const reqsAtBg = r.httpState.requests.length;
    await new Promise(res => setTimeout(res, 35));
    // Accelerated timers run several two-minute notification updates in this window.
    const bgRequests = r.httpState.requests.slice(reqsAtBg);
    assert.ok(bgRequests.length > 0 && bgRequests.every(req => req.url.endsWith('/connections')));
    assert.ok(r.vpnState.notifications.length >= 2);
    assert.equal(r.vpnState.notifications.at(-1).id, 71);
    assert.equal(r.vpnState.notifications.at(-1).content.systemLiveView.text, '已传输 3.00 MiB');
    r.store.setAppInForeground(true);
    await new Promise(res => setTimeout(res, 40));
    assert.equal(r.store.isRunning, true);

    // Handover releases upstream sockets while preserving the same system VPN.
    const conn = r.vpnState.netConnections[r.vpnState.netConnections.length - 1];
    const startCallsBefore = r.vpnState.startCalls.length;
    const beforeHandover = r.httpState.requests.length;
    r.store.setAppInForeground(false);
    conn._emit('netAvailable', { netId: 100 });
    conn._emit('netAvailable', { netId: 202 });
    const waitDeadline = Date.now() + 500;
    const closedUpstream = () => r.httpState.requests.slice(beforeHandover).some(req => req.url.endsWith('/connections') && req.options.method === 'DELETE');
    while (Date.now() < waitDeadline && !closedUpstream()) {
      await new Promise(res => setTimeout(res, 15));
    }
    assert.ok(closedUpstream());
    assert.equal(r.vpnState.startCalls.length, startCallsBefore);
    assert.equal(r.vpnState.tunDestroyed, 0);
    assert.equal(r.store.isRunning, true);

    await r.store.toggleRunningAsync();
    assert.equal(r.vpnState.keepAliveStops, 1);
    assert.equal(r.BackgroundKeepAlive.isActive(), false);
    const stoppedCount = r.vpnState.notifications.length;
    await new Promise(res => setTimeout(res, 30));
    assert.equal(r.vpnState.notifications.length, stoppedCount);
  } finally {
    r.BackgroundKeepAlive.setAbilityContext(null);
    r.dispose();
  }
});

test('KeepAlive: an open-ended transfer stays unfinished while displaying real traffic, including idle updates', async () => {
  const r = runtime({ realTimers: true });
  try {
    await r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility', async () => 3145728);
    assert.deepEqual(Array.from(r.vpnState.keepAliveStarts[0].backgroundTaskModes), [1]);
    assert.deepEqual(Array.from(r.vpnState.keepAliveStarts[0].backgroundTaskSubmodes), [3]);
    await new Promise(resolve => setTimeout(resolve, 35));
    assert.ok(r.vpnState.notifications.length >= 2);
    for (const notification of r.vpnState.notifications) {
      assert.equal(notification.id, 71);
      assert.equal(notification.template.name, 'downloadTemplate');
      assert.equal(notification.template.data.progressValue, 0);
      assert.equal(notification.template.data.fileName, '已传输 3.00 MiB');
    }
    await r.BackgroundKeepAlive.stop();
    assert.deepEqual(r.vpnState.keepAliveStoppedIds, [91]);
  } finally { r.dispose(); }
});

test('KeepAlive: a rejected initial notification rolls back its task and leaves the start/stop queue usable', async () => {
  let rejectNotification = true;
  const r = runtime({ vpnHooks: { publishNotification: () => {
    if (rejectNotification) throw { code: 1600004, message: 'Notification disabled' };
  } } });
  try {
    await assert.rejects(r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility', async () => 0), /1600004/);
    assert.equal(r.BackgroundKeepAlive.isActive(), false);
    assert.deepEqual(r.vpnState.keepAliveStoppedIds, [91]);
    rejectNotification = false;
    await r.BackgroundKeepAlive.stop();
    await r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility', async () => 0);
    assert.equal(r.BackgroundKeepAlive.isActive(), true);
    assert.equal(r.vpnState.notifications[0].template.data.progressValue, 0);
    await r.BackgroundKeepAlive.stop();
    assert.equal(r.vpnState.keepAliveStops, 2);
  } finally { r.dispose(); }
});

test('KeepAlive: stopping during the initial traffic read cannot publish or leave a task running', async () => {
  let resolveTraffic;
  const r = runtime();
  try {
    const starting = r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility',
      () => new Promise(resolve => { resolveTraffic = resolve; }));
    const rejected = assert.rejects(starting, /已取消/);
    while (!resolveTraffic) await new Promise(resolve => setImmediate(resolve));
    const stopping = r.BackgroundKeepAlive.stop();
    resolveTraffic(1024);
    await rejected;
    await stopping;
    assert.equal(r.vpnState.notifications.length, 0);
    assert.equal(r.BackgroundKeepAlive.isActive(), false);
    assert.deepEqual(r.vpnState.keepAliveStoppedIds, [91]);
    await r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility', async () => 2048);
    assert.equal(r.BackgroundKeepAlive.isActive(), true);
    await r.BackgroundKeepAlive.stop();
  } finally { r.dispose(); }
});

test('KeepAlive: destroying the UI during task creation releases the late task without publishing', async () => {
  let finishTask;
  const r = runtime({ vpnHooks: { startBackgroundRunning: () => new Promise(resolve => { finishTask = resolve; }) } });
  try {
    const starting = r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility', async () => 0);
    const rejected = assert.rejects(starting, /已取消/);
    while (!finishTask) await new Promise(resolve => setImmediate(resolve));
    r.BackgroundKeepAlive.setAbilityContext(null);
    finishTask({ notificationId: 71, continuousTaskId: 91 });
    await rejected;
    assert.deepEqual(r.vpnState.keepAliveStoppedIds, [91]);
    assert.equal(r.vpnState.notifications.length, 0);
    assert.equal(r.BackgroundKeepAlive.isActive(), false);
  } finally { r.dispose(); }
});

test('KeepAlive: dismissing the notification does not silently rearm on resume or misreport a healthy VPN', async () => {
  const r = runtime({ realTimers: true });
  try {
    r.httpState.response.result = JSON.stringify({ version: 'mihomo-test' });
    r.vpnState.systemVpnActive = true;
    r.disk.set('/sandbox/vpn-status.json', JSON.stringify({ status: 'running', cleanupComplete: false }));
    await r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility', async () => 1024);
    r.vpnState.keepAliveCancelCb({ id: 91, reason: 1, detailedReason: 3 });
    assert.equal(r.BackgroundKeepAlive.isActive(), false);
    assert.match(r.BackgroundKeepAlive.getLastError(), /通知已被关闭/);
    const notificationCount = r.vpnState.notifications.length;
    assert.equal(await r.store.vpnManager.isSessionHealthy(), true);
    assert.equal(r.vpnState.keepAliveStarts.length, 1);
    await new Promise(resolve => setTimeout(resolve, 25));
    assert.equal(r.vpnState.notifications.length, notificationCount);
    await r.store.restoreExistingVpnSessionAsync();
    assert.equal(r.store.isRunning, true);
    assert.match(r.store.lastOperationError, /通知已被关闭/);
    await r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility', async () => 2048);
    assert.equal(r.vpnState.keepAliveStarts.length, 2);
    assert.equal(r.BackgroundKeepAlive.getLastError(), '');
    await r.BackgroundKeepAlive.stop();
  } finally { r.dispose(); }
});

test('KeepAlive: a transient refresh failure is visible and the next real update recovers without restarting VPN', async () => {
  let failRefresh = false;
  const r = runtime({ realTimers: true, vpnHooks: { publishNotification: () => {
    if (failRefresh) throw { code: 1600003, message: 'Service unavailable' };
  } } });
  try {
    await r.BackgroundKeepAlive.start('com.lovexjy.lexiclash', 'EntryAbility', async () => 4096);
    failRefresh = true;
    await new Promise(resolve => setTimeout(resolve, 25));
    assert.match(r.BackgroundKeepAlive.getLastError(), /1600003/);
    assert.equal(r.BackgroundKeepAlive.isActive(), true);
    failRefresh = false;
    await new Promise(resolve => setTimeout(resolve, 25));
    assert.equal(r.BackgroundKeepAlive.getLastError(), '');
    assert.equal(r.vpnState.keepAliveStarts.length, 1);
    assert.equal(r.vpnState.notifications.at(-1).template.data.progressValue, 0);
    await r.BackgroundKeepAlive.stop();
  } finally { r.dispose(); }
});

test('VPN startup: rejected background protection fails connection and releases the native core and TUN', async () => {
  let extension;
  const r = runtime({ loaded: true, realTimers: true, vpnHooks: {
    onStartAbility: () => { extension = new r.LexiVpnExtension(); extension.onCreate(); },
    onStopAbility: () => { if (extension) extension.onDestroy(); },
    startBackgroundRunning: () => { throw { code: 9800006, message: 'Notification verification failed' }; }
  } });
  try {
    await r.store.addNewProfile('主配置', '', 'file', fixture);
    assert.equal(await r.store.toggleRunningAsync(), false);
    assert.equal(r.store.isRunning, false);
    assert.equal(r.store.coreStatus, 'disconnected');
    assert.match(r.store.lastOperationError, /9800006/);
    assert.equal(r.vpnState.tunDestroyed, 1);
    assert.equal(r.vpnState.nativeStopCalls, 1);
    assert.equal(r.BackgroundKeepAlive.isActive(), false);
  } finally { r.dispose(); }
});

test('VPN health: a reachable controller and cached running state cannot substitute for the system tunnel', async () => {
  const r = runtime({ loaded: true });
  try {
    r.httpState.response.result = JSON.stringify({ version: 'test' });
    r.disk.set('/sandbox/vpn-status.json', JSON.stringify({ sessionId: 'lost', status: 'running', updatedAt: Date.now(), cleanupComplete: false }));
    assert.equal(await r.store.vpnManager.isSessionHealthy(), false);
    assert.equal(r.vpnState.keepAliveStarts.length, 0);
    r.vpnState.systemVpnActive = true;
    r.vpnState.systemVpnAddress = '192.0.2.1';
    assert.equal(await r.store.vpnManager.isSessionHealthy(), false, 'an unrelated VPN is not our tunnel');
    r.vpnState.systemVpnAddress = '172.19.0.1';
    assert.equal(await r.store.vpnManager.isSessionHealthy(), true);
    await r.BackgroundKeepAlive.stop();
  } finally { r.dispose(); }
});

test('VPN health: polling clears a phantom connection and tells the extension to release its resources', async () => {
  const r = runtime({ loaded: true });
  try {
    r.store.isRunning = true;
    r.store.vpnEnabled = true;
    r.store.managedRuntime = true;
    r.store.coreStatus = 'connected';
    r.disk.set('/sandbox/vpn-status.json', JSON.stringify({ sessionId: 'lost', status: 'running', updatedAt: Date.now(), cleanupComplete: false }));
    await r.store.pollLiveVpnStatsAsync();
    assert.equal(r.store.isRunning, false);
    assert.equal(r.store.vpnEnabled, false);
    assert.equal(r.store.coreStatus, 'disconnected');
    assert.match(r.store.lastOperationError, /系统 VPN 连接已断开/);
    assert.equal(JSON.parse(r.disk.get('/sandbox/vpn-command.json')).action, 'stop');
  } finally { r.dispose(); }
});

test('VPN health: returning to the foreground clears stale UI when the system VPN has vanished', async () => {
  const r = runtime({ loaded: true });
  try {
    r.store.isRunning = true;
    r.store.vpnEnabled = true;
    r.store.managedRuntime = true;
    r.store.coreStatus = 'connected';
    r.disk.set('/sandbox/vpn-status.json', JSON.stringify({ sessionId: 'lost', status: 'running', updatedAt: Date.now(), cleanupComplete: false }));
    await r.store.restoreExistingVpnSessionAsync();
    assert.equal(r.store.isRunning, false);
    assert.equal(r.store.coreStatus, 'disconnected');
  } finally { r.dispose(); }
});

test('VPN health: a transient controller error preserves a fresh live tunnel, but a dead extension cannot stay connected', async () => {
  const r = runtime({ loaded: true });
  try {
    r.store.isRunning = true;
    r.store.vpnEnabled = true;
    r.store.managedRuntime = true;
    r.vpnState.systemVpnActive = true;
    r.httpState.throws = true;
    const status = { sessionId: 'stalled', status: 'running', updatedAt: Date.now(), cleanupComplete: false };
    r.disk.set('/sandbox/vpn-status.json', JSON.stringify(status));
    await r.store.pollLiveVpnStatsAsync();
    await r.store.pollLiveVpnStatsAsync();
    await r.store.pollLiveVpnStatsAsync();
    assert.equal(r.store.isRunning, true);
    status.updatedAt = Date.now() - 60000;
    r.disk.set('/sandbox/vpn-status.json', JSON.stringify(status));
    await r.store.pollLiveVpnStatsAsync();
    assert.equal(r.store.isRunning, false);
    assert.match(r.store.lastOperationError, /停止响应/);
  } finally { r.dispose(); }
});

test('Diagnostics: the bounded journal survives events, masks credentials, and separates UI and VPN logs', () => {
  const r = runtime();
  try {
    r.RuntimeDiagnostics.watch('/sandbox', 'ui');
    r.RuntimeDiagnostics.record('UI background');
    r.RuntimeDiagnostics.record('secret=private-token https://private.example/config');
    const journal = r.disk.get('/sandbox/runtime-ui.log');
    assert.match(journal, /UI background/);
    assert.match(journal, /\[redacted\]/);
    assert.ok(!journal.includes('private-token') && !journal.includes('private.example'));
    r.disk.set('/sandbox/runtime-ui.log', 'x'.repeat(65536));
    r.RuntimeDiagnostics.record('latest cancellation');
    assert.ok(r.disk.get('/sandbox/runtime-ui.log').length < 4000);
    r.RuntimeDiagnostics.watch('/sandbox', 'vpn');
    r.RuntimeDiagnostics.record('VPN extension destroyed');
    assert.match(r.disk.get('/sandbox/runtime-ui.log'), /latest cancellation/);
    assert.match(r.disk.get('/sandbox/runtime-vpn.log'), /extension destroyed/);
  } finally { r.dispose(); }
});

test('Startup: awaitStartupReadyAsync resolves within maxWaitMs even when controller is unavailable', async () => {
  const r = runtime({ loaded: true, realTimers: true });
  try {
    const t0 = Date.now();
    await r.store.awaitStartupReadyAsync(40);
    assert.ok(Date.now() - t0 < 300);
  } finally {
    r.dispose();
  }
});

test('Privacy: runtime policy merges overrides and settings without rewriting subscription fields', async () => {
  const r = await imported({ loaded: true });
  try {
    r.store.overrideRules = [
      { id: 'on', ruleType: 'DST-PORT', payload: '19302', targetGroup: 'REJECT', enabled: true, noResolve: false },
      { id: 'off', ruleType: 'DST-PORT', payload: '80', targetGroup: 'REJECT', enabled: false, noResolve: false }
    ];
    r.store.ipv6Enabled = true;
    r.store.snifferEnabled = false;
    r.store.dnsNameserver = 'https://resolver.example/dns-query';
    const yaml = r.store.buildVpnRuntimeYaml(fixture);
    const policy = JSON.parse(yaml.split('\n').find(line => line.startsWith('lexiclash: ')).slice('lexiclash: '.length));
    assert.deepEqual(policy.rules, ['DST-PORT,19302,REJECT']);
    assert.equal(policy.ipv6, true);
    assert.equal(policy.sniffer, false);
    assert.deepEqual(policy.nameservers, ['https://resolver.example/dns-query']);
    assert.equal(policy.selections.Proxy, '入口, A');
    const result = spawnSync('python3', ['-c', 'import json,sys,yaml; a,b=json.load(sys.stdin); a=yaml.safe_load(a); b=yaml.safe_load(b); assert a["proxies"]==b["proxies"]; assert a["rules"]==b["rules"]'], { input: JSON.stringify([fixture, yaml]), encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(r.store.getCurrentProfile().yamlContent, fixture);
  } finally { r.dispose(); }
});

test('Privacy: recompilation handles YAML document markers and replaces stale policy', async () => {
  const r = await imported();
  try {
    const yaml = r.store.buildVpnRuntimeYaml('---\n' + fixture + '...\n');
    const again = r.store.buildVpnRuntimeYaml(yaml);
    assert.equal(again, yaml);
    assert.equal((again.match(/^lexiclash:/gm) || []).length, 1);
    const result = spawnSync('python3', ['-c', 'import sys,yaml; d=yaml.safe_load(sys.stdin.read()); assert d["lexiclash"]["version"]==1'], { input: again, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.throws(() => r.store.buildVpnRuntimeYaml('---\nmode: rule\n---\nmode: direct'), /多文档/);
  } finally { r.dispose(); }
});

test('Privacy: proxy-chain DNS pins the exit while TCP-only chains remain usable', async () => {
  const r = await imported();
  try {
    pair(r);
    const compiled = r.store.buildProxyChainPreview();
    assert.equal(compiled.errorMessage, '');
    const policy = JSON.parse(compiled.yamlContent.split('\n').find(line => line.startsWith('lexiclash: ')).slice(11));
    assert.equal(policy.dnsProxy, '出口 B');
    assert.equal(policy.selections.Proxy, '出口 B');
    assert.match(r.store.getProxyChainUdpWarning(), /UDP.*拒绝/);
  } finally { r.dispose(); }
});

test('Privacy: network settings survive restart', async () => {
  const r = await imported();
  try {
    r.store.ipv6Enabled = true; r.store.blockStun = false;
    r.store.dnsNameserver = 'https://resolver.example/dns-query';
    r.store.persistState();
    r.store.ipv6Enabled = false; r.store.blockStun = true;
    r.store.initialize('/sandbox');
    assert.equal(r.store.ipv6Enabled, true);
    assert.equal(r.store.blockStun, false);
    assert.equal(r.store.dnsNameserver, 'https://resolver.example/dns-query');
  } finally { r.dispose(); }
});

test('Privacy: old core cannot silently ignore the privacy policy', async () => {
  const r = await imported({ loaded: true, fail: req => req.method === 'privacy.capabilities' ? 'unknown method' : null });
  try {
    assert.equal(await r.store.toggleRunningAsync(), false);
    assert.equal(r.vpnState.nativeLaunchCalls.length, 0);
    assert.match(r.store.lastOperationError, /防泄露策略/);
  } finally { r.dispose(); }
});

test('Privacy: rejected reload preserves restart config and active tunnel', async () => {
  let rejected = true;
  const r = runtime({ loaded: true, vpnHooks: { httpHandler: () => ({ responseCode: rejected ? 400 : 200, result: rejected ? 'invalid profile' : '' }) } });
  try {
    r.disk.set('/sandbox/config.yaml', fixture);
    await assert.rejects(r.store.vpnManager.reloadRuntimeConfig('invalid', {}, 'rule'), /HTTP 400/);
    assert.equal(r.disk.get('/sandbox/config.yaml'), fixture);
    assert.equal(r.vpnState.tunDestroyed, 0);
    rejected = false;
    await r.store.vpnManager.reloadRuntimeConfig(fixture, {}, '');
    assert.equal(r.disk.get('/sandbox/config.yaml'), fixture);
  } finally { r.dispose(); }
});

test('Privacy: unavailable controller does not remove VPN routes during a settings update', async () => {
  const r = await imported({ loaded: true });
  try {
    r.store.isRunning = true; r.store.vpnEnabled = true;
    r.store.vpnManager.isSessionHealthy = async () => false;
    await r.store.restartVpnAfterConfigChangeAsync();
    assert.equal(r.store.isRunning, true);
    assert.equal(r.vpnState.nativeStopCalls, 0);
    assert.equal(r.vpnState.tunDestroyed, 0);
    assert.match(r.store.lastOperationError, /保留当前 VPN/);
  } finally { r.dispose(); }
});

test('Privacy: DNS flush clears resolver answers and preserves fake-IP mappings', async () => {
  const r = runtime({ loaded: true });
  try {
    await r.store.vpnManager.flushDnsCache();
    assert.equal(r.httpState.requests.length, 1);
    assert.match(r.httpState.requests[0].url, /\/cache\/dns\/flush$/);
  } finally { r.dispose(); }
});

test('Privacy: overlapping reloads cannot apply an older config after a newer one', async () => {
  const order = [];
  const r = runtime({ loaded: true, vpnHooks: { httpHandler: async (url, options) => {
    if (url.includes('/configs?force=true')) {
      const name = JSON.parse(options.extraData).payload;
      order.push(name + ':start');
      if (name === 'first') await new Promise(resolve => setTimeout(resolve, 15));
      order.push(name + ':end');
    }
    return { responseCode: 200, result: '' };
  } } });
  try {
    await Promise.all([r.store.vpnManager.reloadRuntimeConfig('first', {}, ''), r.store.vpnManager.reloadRuntimeConfig('second', {}, '')]);
    assert.deepEqual(order, ['first:start', 'first:end', 'second:start', 'second:end']);
    assert.equal(r.disk.get('/sandbox/config.yaml'), 'second');
  } finally { r.dispose(); }
});

test('Privacy: ordinary connections cannot fabricate DNS queries or upstream evidence', async () => {
  const r = runtime({ loaded: true, vpnHooks: { httpHandler: () => ({ responseCode: 200, result: JSON.stringify({
    uploadTotal: 1, downloadTotal: 2, connections: [{ id: 'one', metadata: { host: 'example.test', destinationIP: '192.0.2.1', network: 'TCP' }, chains: ['Exit'] }]
  }) }) } });
  try {
    r.store.isRunning = true; r.store.vpnEnabled = true;
    r.vpnState.systemVpnActive = true;
    r.disk.set('/sandbox/vpn-status.json', JSON.stringify({ status: 'running', cleanupComplete: false }));
    await r.store.pollLiveVpnStatsAsync();
    assert.equal(r.store.liveConnections.length, 1);
    assert.equal(r.store.dnsQueries.length, 0);
    assert.equal(r.store.dnsQueriesCount, 0);
  } finally { r.dispose(); }
});

test('App routing: saves enabled state, mode, labels and unchecked entries across restart', () => {
  const r = runtime();
  try {
    assert.match(r.store.addAppAccessEntry('not a bundle', ''), /包名/);
    assert.equal(r.store.addAppAccessEntry(' com.example.browser ', 'Browser'), '');
    assert.equal(r.store.addAppAccessEntry('com.example.video', 'Video'), '');
    assert.match(r.store.addAppAccessEntry('com.example.browser', ''), /已在列表/);
    r.store.setAppAccessSelected('com.example.video', false);
    r.store.setAppAccessEnabled(true);
    r.store.setAppAccessMode('whitelist');
    r.store.persistState();
    r.store.appAccessList = []; r.store.accessControlEnabled = false; r.store.accessControlMode = 'blacklist';
    r.store.initialize('/sandbox');
    assert.equal(r.store.accessControlEnabled, true);
    assert.equal(r.store.accessControlMode, 'whitelist');
    assert.equal(r.store.appAccessList[0].appName, 'Browser');
    assert.equal(r.store.appAccessList[1].isSelected, false);
    assert.deepEqual(Array.from(r.store.getAppAccessPolicy().bundleNames), ['com.example.browser']);
    r.store.removeAppAccessEntry('com.example.browser');
    assert.match(r.AppAccessControl.validationError(r.store.getAppAccessPolicy()), /至少/);
    // Existing state files upgrade with app routing disabled.
    const legacy = JSON.parse(r.disk.get('/sandbox/lexiclash-state.json'));
    delete legacy.appAccessList; delete legacy.accessControlMode; delete legacy.accessControlEnabled;
    r.disk.set('/sandbox/lexiclash-state.json', JSON.stringify(legacy));
    r.store.initialize('/sandbox');
    assert.equal(r.store.accessControlEnabled, false);
    assert.equal(r.store.appAccessList.length, 0);
  } finally { r.dispose(); }
});

test('App routing: invalid and empty allowlists never release an existing VPN or replace its command', async () => {
  const r = runtime({ loaded: true });
  try {
    const existing = '{"sessionId":"current","action":"start"}';
    r.disk.set('/sandbox/vpn-command.json', existing);
    for (const policy of [
      { enabled: true, mode: 'whitelist', bundleNames: [] },
      { enabled: true, mode: 'blacklist', bundleNames: ['bad package'] },
      { enabled: true, mode: 'blacklist', bundleNames: Array.from({ length: 257 }, (_, i) => `com.test.app${i}`) },
      { enabled: true, mode: 'bogus', bundleNames: ['com.test.app'] }
    ]) {
      await assert.rejects(r.store.vpnManager.startVpn(fixture, {}, policy));
    }
    assert.equal(r.vpnState.stopCalls.length, 0);
    assert.equal(r.disk.get('/sandbox/vpn-command.json'), existing);
    r.store.isRunning = true; r.store.vpnEnabled = true;
    r.store.setAppAccessEnabled(true); r.store.setAppAccessMode('whitelist');
    assert.equal(await r.store.applyAppAccessChangesAsync(), false);
    assert.equal(r.store.isRunning, true);
    assert.equal(r.vpnState.stopCalls.length, 0);
  } finally { r.dispose(); }
});

test('App routing: session command reaches system VPN allowlist and bypass list exclusively', async () => {
  for (const mode of ['whitelist', 'blacklist', 'disabled', 'empty-blacklist', 'legacy']) {
    const r = runtime({ loaded: true });
    let extension;
    try {
      const policy = { enabled: mode !== 'disabled', mode: mode === 'whitelist' ? 'whitelist' : 'blacklist',
        bundleNames: mode === 'empty-blacklist' ? [] : ['com.example.browser'] };
      r.store.vpnManager.prepareStartFiles(fixture, {}, policy);
      if (mode === 'legacy') {
        const command = JSON.parse(r.disk.get('/sandbox/vpn-command.json'));
        delete command.accessControl;
        delete command.tun;
        r.disk.set('/sandbox/vpn-command.json', JSON.stringify(command));
      }
      extension = new r.LexiVpnExtension(); extension.onCreate(); await extension.startup;
      assert.equal(r.vpnState.tunCreates.length, 1);
      const cfg = r.vpnState.tunCreates[0];
      assert.deepEqual(cfg.trustedApplications && Array.from(cfg.trustedApplications), mode === 'whitelist' ? ['com.example.browser'] : undefined);
      assert.deepEqual(cfg.blockedApplications && Array.from(cfg.blockedApplications), mode === 'blacklist' ? ['com.example.browser'] : undefined);
      assert.equal(cfg.isIPv6Accepted, true);
      const status = JSON.parse(r.disk.get('/sandbox/vpn-status.json'));
      assert.equal(status.status, 'running');
      assert.equal(status.accessControl.enabled, mode !== 'disabled' && mode !== 'legacy');
    } finally {
      if (extension) { extension.onDestroy(); await extension.stopping; }
      r.dispose();
    }
  }
});

test('App routing: extension rejects an invalid allowlist before native startup', async () => {
  const r = runtime({ loaded: true });
  try {
    r.store.vpnManager.prepareStartFiles(fixture, {});
    const command = JSON.parse(r.disk.get('/sandbox/vpn-command.json'));
    command.accessControl = { enabled: true, mode: 'whitelist', bundleNames: [] };
    r.disk.set('/sandbox/vpn-command.json', JSON.stringify(command));
    const extension = new r.LexiVpnExtension(); extension.onCreate(); await extension.startup;
    assert.equal(r.vpnState.nativeLaunchCalls.length, 0);
    assert.equal(r.vpnState.tunCreates.length, 0);
    assert.match(JSON.parse(r.disk.get('/sandbox/vpn-status.json')).error, /至少/);
  } finally { r.dispose(); }
});

test('App routing: drafts do not change capture until explicit reconnect, which preserves the proxy chain', async () => {
  let extension;
  const r = runtime({ loaded: true, realTimers: true, vpnHooks: {
    onStartAbility: () => { extension = new r.LexiVpnExtension(); extension.onCreate(); },
    onStopAbility: () => { if (extension) extension.onDestroy(); },
    httpHandler: () => ({ responseCode: 200, result: JSON.stringify({ version: 'test', mode: 'rule', now: '出口 B', uploadTotal: 0, downloadTotal: 0, connections: [] }) })
  } });
  try {
    await r.store.addNewProfile('主配置', '', 'file', fixture);
    pair(r);
    r.store.chainConnected = true;
    r.store.connectedChainNames = ['入口, A', '出口 B'];
    assert.equal(await r.store.toggleRunningAsync(), true);
    assert.equal(r.vpnState.tunCreates.length, 1);
    r.store.addAppAccessEntry('com.example.browser', 'Browser');
    r.store.setAppAccessEnabled(true); r.store.setAppAccessMode('whitelist');
    assert.equal(r.vpnState.tunCreates.length, 1);
    assert.equal(r.store.hasPendingAppAccessChanges(), true);
    assert.equal(await r.store.applyAppAccessChangesAsync(), true);
    assert.equal(r.vpnState.tunDestroyed, 1);
    assert.equal(r.vpnState.tunCreates.length, 2);
    assert.deepEqual(Array.from(r.vpnState.tunCreates[1].trustedApplications), ['com.example.browser']);
    assert.equal(r.store.hasPendingAppAccessChanges(), false);
    assert.equal(r.store.chainConnected, true);
    assert.deepEqual(Array.from(r.store.connectedChainNames), ['入口, A', '出口 B']);
    assert.ok(r.disk.get('/sandbox/config.yaml').includes('dialer-proxy: "入口, A"'));
    assert.equal(await r.store.applyAppAccessChangesAsync(), true);
    assert.equal(r.vpnState.tunCreates.length, 2);
    // Disabling must recreate an unrestricted connection without losing the saved list.
    r.store.setAppAccessEnabled(false);
    assert.equal(await r.store.applyAppAccessChangesAsync(), true);
    assert.equal(r.vpnState.tunCreates[2].trustedApplications, undefined);
    assert.equal(r.vpnState.tunCreates[2].blockedApplications, undefined);
    assert.equal(r.store.appAccessList.length, 1);
    await r.store.toggleRunningAsync();
  } finally { r.dispose(); }
});

test('TUN: persists stack and MTU, rejects invalid drafts and upgrades older state', () => {
  const r = runtime();
  try {
    for (const [stack, mtu] of [['invalid', 1400], ['system', 1279], ['system', 9001], ['mixed', 1400.5]]) {
      assert.notEqual(r.store.setTunSettings(stack, mtu), '');
    }
    assert.equal(r.store.tunStack, 'system'); assert.equal(r.store.tunMtu, 1400);
    assert.equal(r.store.setTunSettings('mixed', 1500), '');
    r.store.persistState();
    r.store.tunStack = 'system'; r.store.tunMtu = 1400;
    r.store.initialize('/sandbox');
    assert.equal(r.store.tunStack, 'mixed'); assert.equal(r.store.tunMtu, 1500);
    const saved = JSON.parse(r.disk.get('/sandbox/lexiclash-state.json'));
    delete saved.tunSettings;
    r.disk.set('/sandbox/lexiclash-state.json', JSON.stringify(saved));
    r.store.initialize('/sandbox');
    assert.equal(r.store.tunStack, 'system'); assert.equal(r.store.tunMtu, 1400);
  } finally { r.dispose(); }
});

test('TUN: both stack and MTU travel in the session, with MTU applied to the system interface', async () => {
  for (const stack of ['system', 'gvisor', 'mixed']) {
    const r = runtime({ loaded: true });
    let extension;
    try {
      const tun = { stack, mtu: 1500 };
      r.store.vpnManager.prepareStartFiles(fixture, {}, r.AppAccessControl.unrestricted(), tun);
      assert.deepEqual(JSON.parse(r.disk.get('/sandbox/vpn-command.json')).tun, tun);
      extension = new r.LexiVpnExtension(); extension.onCreate(); await extension.startup;
      assert.equal(r.vpnState.tunCreates.length, 1);
      assert.equal(r.vpnState.tunCreates[0].mtu, 1500);
      assert.deepEqual(JSON.parse(r.disk.get('/sandbox/vpn-status.json')).tun, tun);
      assert.equal(r.vpnState.tunCreates[0].isIPv4Accepted, true);
      assert.equal(r.vpnState.tunCreates[0].isIPv6Accepted, true);
    } finally {
      if (extension) { extension.onDestroy(); await extension.stopping; }
      r.dispose();
    }
  }
});

test('TUN: invalid settings never release the old session or create a system interface', async () => {
  const r = runtime({ loaded: true });
  try {
    const command = { sessionId: 'current', action: 'start', secret: 'test', tun: { stack: 'system', mtu: 1000 } };
    r.disk.set('/sandbox/vpn-command.json', JSON.stringify(command));
    await assert.rejects(r.store.vpnManager.startVpn(fixture, {}, r.AppAccessControl.unrestricted(), command.tun), /MTU/);
    assert.equal(r.vpnState.stopCalls.length, 0);
    const extension = new r.LexiVpnExtension(); extension.onCreate(); await extension.startup;
    assert.equal(r.vpnState.nativeLaunchCalls.length, 0);
    assert.equal(r.vpnState.tunCreates.length, 0);
  } finally { r.dispose(); }
});

test('TUN: all connections use the system VPN and settings reconnect preserves app routing and chain', async () => {
  let extension;
  const r = runtime({ loaded: true, realTimers: true, vpnHooks: {
    onStartAbility: () => { extension = new r.LexiVpnExtension(); extension.onCreate(); },
    onStopAbility: () => { if (extension) extension.onDestroy(); },
    httpHandler: () => ({ responseCode: 200, result: JSON.stringify({ version: 'test', mode: 'rule', now: '出口 B', uploadTotal: 0, downloadTotal: 0, connections: [] }) })
  } });
  try {
    assert.equal(r.store.isRunning, false);
    assert.equal(r.store.vpnEnabled, false);
    await r.store.addNewProfile('主配置', '', 'file', fixture);
    r.store.addAppAccessEntry('com.example.browser', 'Browser');
    r.store.setAppAccessEnabled(true); r.store.setAppAccessMode('whitelist');
    pair(r); r.store.chainConnected = true; r.store.connectedChainNames = ['入口, A', '出口 B'];
    assert.equal(await r.store.toggleRunningAsync(), true);
    assert.equal(r.vpnState.tunCreates.length, 1);
    assert.equal(r.vpnState.tunCreates.length, 1);
    assert.equal(r.store.setTunSettings('gvisor', 1500), '');
    assert.equal(r.store.hasPendingTunChanges(), true);
    assert.equal(r.vpnState.tunCreates.length, 1);
    assert.equal(await r.store.applyTunSettingsAsync(), true);
    assert.equal(r.vpnState.tunDestroyed, 1);
    assert.equal(r.vpnState.tunCreates.length, 2);
    assert.equal(r.vpnState.tunCreates[1].mtu, 1500);
    assert.deepEqual(Array.from(r.vpnState.tunCreates[1].trustedApplications), ['com.example.browser']);
    assert.equal(JSON.parse(r.disk.get('/sandbox/vpn-command.json')).tun.stack, 'gvisor');
    assert.equal(r.store.hasPendingTunChanges(), false);
    assert.equal(r.store.chainConnected, true);
    assert.ok(r.disk.get('/sandbox/config.yaml').includes('dialer-proxy: "入口, A"'));
    assert.equal(await r.store.applyTunSettingsAsync(), true);
    assert.equal(r.vpnState.tunCreates.length, 2);
    await r.store.toggleRunningAsync();
    assert.equal(r.store.isRunning, false);
    assert.equal(r.store.vpnEnabled, false);
    assert.equal(r.vpnState.tunDestroyed, 2);
  } finally { r.dispose(); }
});

test('Startup: a clean runtime skips dead-controller probes and waits for background readiness', async () => {
  let extension;
  const r = runtime({ loaded: true, realTimers: true, vpnHooks: {
    onStartAbility: () => { extension = new r.LexiVpnExtension(); extension.onCreate(); },
    onStopAbility: () => { if (extension) extension.onDestroy(); }
  } });
  await r.store.addNewProfile('主配置', '', 'file', fixture);
  let finishNotification;
  try {
    await r.store.vpnManager.releaseVpn();
    assert.equal(r.httpState.requests.length, 0);
    assert.equal(r.vpnState.stopCalls.length, 0);
    r.BackgroundKeepAlive.start = () => new Promise(resolve => { finishNotification = resolve; });
    const connecting = r.store.toggleRunningAsync();
    assert.equal(await Promise.race([connecting, new Promise(resolve => setTimeout(() => resolve('pending'), 100))]), 'pending');
    assert.equal(r.store.coreStatus, 'connecting');
    assert.equal(r.httpState.requests.some(req => req.url.endsWith('/configs') && req.options.method === 'PATCH'), false);
    finishNotification();
    assert.equal(await connecting, true);
    assert.equal(r.store.coreStatus, 'connected');
    await r.store.toggleRunningAsync();
  } finally { if (finishNotification) finishNotification(); r.dispose(); }
});

for (const staleDisabledSetting of [false, true]) {
  test(`Chain: replace live nodes, retain old chain on failed selection, and retry without disconnect (legacy disabled setting=${staleDisabledSetting})`, async () => {
    let extension;
    let failSelection = false;
    let groupState = { Proxy: '入口, A', GLOBAL: '出口 B' };
    let reloads = [];
    const r = runtime({ loaded: true, realTimers: true, vpnHooks: {
      onStartAbility: () => { extension = new r.LexiVpnExtension(); extension.onCreate(); },
      onStopAbility: () => { if (extension) extension.onDestroy(); },
      httpHandler: (url, options) => {
        if (url.includes('/configs?force=true')) {
          const yaml = JSON.parse(options.extraData).payload;
          reloads.push(yaml);
          const policy = JSON.parse(yaml.split('\n').find(line => line.startsWith('lexiclash: ')).slice(11));
          groupState = { ...groupState, ...policy.selections };
          return { responseCode: 204, result: '' };
        }
        if (url.includes('/proxies/')) {
          const group = decodeURIComponent(url.split('/proxies/')[1]);
          if (options.method === 'PUT') {
            const name = JSON.parse(options.extraData).name;
            if (failSelection && group === 'Proxy' && name === 'C') return { responseCode: 503, result: '{"message":"selection temporarily unavailable"}' };
            groupState[group] = name;
            return { responseCode: 204, result: '' };
          }
          return { responseCode: 200, result: JSON.stringify({ now: groupState[group] }) };
        }
        if (url.endsWith('/cache/dns/flush')) return { responseCode: 404, result: '' }; // Cleanup is optional.
        return { responseCode: 200, result: JSON.stringify({ version: 'test', mode: 'rule', uploadTotal: 0, downloadTotal: 0, connections: [] }) };
      }
    } });
    try {
      await r.store.addNewProfile('主配置', '', 'file', fixture);
      if (staleDisabledSetting) {
        r.store.persistState();
        const saved = JSON.parse(r.disk.get('/sandbox/lexiclash-state.json'));
        saved.tunEnabled = false; // Ignore the obsolete local-proxy preference during migration.
        r.disk.set('/sandbox/lexiclash-state.json', JSON.stringify(saved));
        r.store.initialize('/sandbox');
      }
      pair(r);
      assert.equal(await r.store.connectProxyChainAsync(), '');
      assert.equal(r.store.vpnEnabled, true);
      assert.equal(r.vpnState.tunCreates.length, 1);
      const starts = r.vpnState.startCalls.length;
      // Change a running chain's exit and make the confirmation fail once.
      r.store.removeProxyChainNode('出口 B'); r.store.addProxyChainNode('C');
      const previousYaml = r.disk.get('/sandbox/config.yaml');
      failSelection = true;
      assert.match(await r.store.connectProxyChainAsync(), /selection temporarily unavailable/);
      assert.equal(r.store.isRunning, true);
      assert.equal(r.store.chainConnected, true);
      assert.deepEqual(Array.from(r.store.connectedChainNames), ['入口, A', '出口 B']);
      assert.equal(r.disk.get('/sandbox/config.yaml'), previousYaml);
      assert.equal(reloads.at(-1), previousYaml);
      failSelection = false;
      assert.equal(await r.store.connectProxyChainAsync(), '');
      assert.deepEqual(Array.from(r.store.connectedChainNames), ['入口, A', 'C']);
      assert.equal(r.store.isProxyChainDraftApplied(), true);
      assert.equal(r.vpnState.startCalls.length, starts);
      assert.equal(r.vpnState.tunDestroyed, 0);
      assert.equal(groupState.Proxy, 'C');
      await r.store.toggleRunningAsync();
    } finally { r.dispose(); }
  });
}

(async () => {
  let failed = 0;
  for (const { name, fn } of cases) {
    try { await fn(); console.log('PASS ' + name); }
    catch (error) { failed++; console.error('FAIL ' + name + '\n' + error.stack); }
  }
  console.log(`${cases.length - failed}/${cases.length} passed (host logic; native networking is mocked)`);
  process.exitCode = failed ? 1 : 0;
})();

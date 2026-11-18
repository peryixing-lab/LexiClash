import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';

interface LexiExitDetailInfo {
  pid?: string | number;
  process_name?: string;
  kill_reason?: string;
  pss?: string | number;
  rss?: string | number;
}

interface LexiFaultParams {
  time?: number;
  pid?: number;
  process_name?: string;
  foreground?: boolean;
  reason?: string;
  external_log?: string[];
  last_exit_detail_info?: LexiExitDetailInfo;
}

// System-delivered reports cover both the UI and VPN processes. Keep the
// observer alive for the process lifetime, including while the UI is hidden.
export class RuntimeDiagnostics {
  private static watching: boolean = false;
  private static filesDir: string = '';
  private static journalPath: string = '';
  private static vpnProcessDiedHandler: ((reason: string) => void) | null = null;

  static setVpnProcessDiedHandler(handler: ((reason: string) => void) | null): void {
    RuntimeDiagnostics.vpnProcessDiedHandler = handler;
  }

  static record(message: string): void {
    const safe: string = message.replace(/https?:\/\/[^\s"']+/g, '[URL]')
      .replace(/(secret|password|token|uuid)\s*[:=]\s*[^\s,}]+/gi, '$1=[redacted]');
    const entry: string = safe.substring(0, 3500);
    hilog.info(0xF1C1, 'LexiClashDiag', '%{public}s', entry);
    if (RuntimeDiagnostics.journalPath.length === 0) { return; }
    try {
      let truncate: boolean = false;
      try { truncate = fs.statSync(RuntimeDiagnostics.journalPath).size >= 65536; } catch (_statErr) {}
      const file: fs.File = fs.openSync(RuntimeDiagnostics.journalPath,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | (truncate ? fs.OpenMode.TRUNC : fs.OpenMode.APPEND));
      try { fs.writeSync(file.fd, `${new Date().toISOString()} ${entry}\n`); } finally { fs.closeSync(file); }
    } catch (_writeErr) {
      // Diagnostics must never interrupt the VPN's lifecycle.
    }
  }

  static replayRecent(): void {
    if (RuntimeDiagnostics.filesDir.length === 0) { return; }
    ['ui', 'vpn'].forEach((kind: string): void => {
      try {
        const lines: string[] = fs.readTextSync(`${RuntimeDiagnostics.filesDir}/runtime-${kind}.log`).split('\n');
        lines.slice(-16).forEach((line: string): void => {
          if (line.length > 0) { hilog.warn(0xF1C1, 'LexiClashDiag', 'Saved %{public}s: %{public}s', kind, line); }
        });
      } catch (_readErr) {}
    });
  }

  static watch(filesDir: string = '', kind: string = 'ui'): void {
    if (filesDir.length > 0) {
      RuntimeDiagnostics.filesDir = filesDir;
      RuntimeDiagnostics.journalPath = `${filesDir}/runtime-${kind === 'vpn' ? 'vpn' : 'ui'}.log`;
    }
    if (RuntimeDiagnostics.watching) { return; }
    try {
      hiAppEvent.addWatcher({
        name: 'LexiClashFaults',
        appEventFilters: [{
          domain: hiAppEvent.domain.OS,
          names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE, hiAppEvent.event.APP_KILLED,
            hiAppEvent.event.RESOURCE_OVERLIMIT]
        }],
        onReceive: (_domain: string, groups: hiAppEvent.AppEventGroup[]): void => {
          groups.forEach((group: hiAppEvent.AppEventGroup): void => {
            group.appEventInfos.forEach((event: hiAppEvent.AppEventInfo): void => {
              const params: LexiFaultParams = event.params as LexiFaultParams;
              const detail: LexiExitDetailInfo | undefined = params.last_exit_detail_info;
              const pid: string = String(params.pid ?? detail?.pid ?? 'unknown');
              const procName: string = String(params.process_name ?? detail?.process_name ?? 'unknown');
              const reason: string = String(params.reason ?? detail?.kill_reason ?? 'unknown');
              RuntimeDiagnostics.record(
                `${event.name} time=${params.time} pid=${pid} process=${procName} foreground=${params.foreground} reason=${reason}`
              );
              RuntimeDiagnostics.record(`System fault parameters: ${JSON.stringify(event.params)}`);
              if ((event.name === hiAppEvent.event.APP_KILLED || event.name === hiAppEvent.event.APP_CRASH ||
                event.name === hiAppEvent.event.APP_FREEZE) &&
                procName.endsWith(':vpn') && RuntimeDiagnostics.vpnProcessDiedHandler !== null) {
                try {
                  RuntimeDiagnostics.vpnProcessDiedHandler(reason);
                } catch (_handlerErr) {}
              }
              (params.external_log ?? []).slice(0, 2).forEach((path: string): void => {
                if (!path.startsWith('/data/storage/el2/log/hiappevent/')) { return; }
                fs.readText(path, { length: 24000 }).then((report: string): void => {
                  const lines: string[] = report.split('\n');
                  let frames: number = 0;
                  lines.forEach((line: string): void => {
                    if (/^(Reason:|Exception|Error name:|Error message:|Pid:|Uid:|Process name:|Timestamp:|Fault thread|Signal:|LastFatalMessage:|#\d{2}|\s+at )/.test(line) && frames++ < 70) {
                      RuntimeDiagnostics.record(line);
                    }
                  });
                }).catch((): void => { RuntimeDiagnostics.record('Fault report unavailable'); });
              });
            });
          });
        }
      });
      RuntimeDiagnostics.watching = true;
    } catch (error) {
      RuntimeDiagnostics.record(`Cannot register fault observer: ${String(error)}`);
    }
  }
}

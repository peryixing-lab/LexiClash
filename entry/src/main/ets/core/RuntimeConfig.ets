import { ProxyChainConfig } from './ProxyChainConfig';

export interface LexiRuntimePolicy {
  mixedPort?: number;
  version: number;
  mode: string;
  dnsProxy: string;
  ipv6: boolean;
  blockStun: boolean;
  sniffer: boolean;
  forceDnsMapping: boolean;
  parsePureIp: boolean;
  enhancedMode: string;
  nameservers: string[];
  fallback: string[];
  rules: string[];
  selections: Record<string, string>;
}

export class RuntimeConfig {
  static servers(raw: string): string[] {
    return raw.split(',').map((server: string): string => server.trim()).filter((server: string): boolean => server.length > 0);
  }

  // Keep the subscription intact and let the native YAML parser merge policy.
  // Strip previous app policy on re-compilation, including quoted keys and
  // indentless lists; place the replacement inside the YAML document markers.
  static attach(yaml: string, policy: LexiRuntimePolicy): string {
    const lines: string[] = yaml.replace(/^\uFEFF/, '').split(/\r?\n/);
    const output: string[] = [];
    let skipping: boolean = false;
    let documentSeen: boolean = false;
    let documentEnded: boolean = false;
    let insertAt: number = 0;
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i];
      const clean: string = ProxyChainConfig.stripComment(line);
      if (clean.trim() === '---') {
        if (documentSeen) { throw new Error('运行配置不支持多文档 YAML'); }
        documentSeen = true;
        skipping = false;
        output.push(line);
        insertAt = output.length;
        continue;
      }
      if (clean.trim() === '...') { documentEnded = true; skipping = false; }
      else if (clean.trim().length > 0 && !clean.startsWith('%')) {
        if (documentEnded) { throw new Error('YAML 文档结束符后存在额外内容'); }
        documentSeen = true;
      }
      const rootField: boolean = /^\S/.test(clean) && !clean.startsWith('-') && clean.trim() !== '...';
      if (rootField) {
        const key: string = ProxyChainConfig.field(clean).key;
        skipping = key === 'lexiclash' || key === 'mode';
      }
      if (!skipping) { output.push(line); }
    }
    const additions: string[] = ['mode: ' + policy.mode, 'lexiclash: ' + JSON.stringify(policy)];
    if (!/^keep-alive-interval\s*:/m.test(yaml)) { additions.push('keep-alive-interval: 15'); }
    if (!/^keep-alive-idle\s*:/m.test(yaml)) { additions.push('keep-alive-idle: 60'); }
    if (!/^tcp-concurrent\s*:/m.test(yaml)) { additions.push('tcp-concurrent: true'); }
    output.splice(insertAt, 0, additions.join('\n'));
    return output.join('\n');
  }
}

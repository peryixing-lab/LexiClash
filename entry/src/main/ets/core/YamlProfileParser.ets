// Profile outline parser for display. Complete configuration validation belongs to the proxy core.

import { buffer } from '@kit.ArkTS';
import { ClashProxyEntry, ClashUriBatchResult, ClashUriParser } from './ClashUriParser';
import { ProxyGroupItem, ProxyGroupKind, ProxyNodeItem } from './CoreProtocol';
import { LexiYamlField, ProxyChainConfig } from './ProxyChainConfig';

export interface ParsedYamlSummary {
  valid: boolean;
  errorMessage: string;
  mixedPort: number;
  allowLan: boolean;
  mode: string;
  ipv6: boolean;
  proxiesCount: number;
  groupsCount: number;
  rulesCount: number;
  parsedNodes: ProxyNodeItem[];
  parsedGroups: ProxyGroupItem[];
}

interface TempProxyNodeFields {
  name: string;
  typeStr: string;
  server: string;
  port: number;
  udp: boolean;
}

interface TempProxyGroupFields {
  name: string;
  typeStr: string;
  nodeNames: string[];
  includeAll: boolean;
  filterRegex: string;
  excludeFilterRegex: string;
}

export class YamlProfileParser {
  static getBlankCustomYaml(): string {
    return `mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: true
unified-delay: true
tcp-concurrent: true

dns:
  enable: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://doh.pub/dns-query
    - 223.5.5.5

proxies: []

proxy-groups: []

rules:
  - GEOIP,CN,DIRECT
  - MATCH,DIRECT
`;
  }

  private static tryDecodeBase64(input: string): string {
    const trimmed: string = input.trim().replace(/\s+/g, '');
    if (trimmed.length < 16) {
      return '';
    }
    // Normalize URL-safe base64
    let normalized: string = trimmed.replace(/-/g, '+').replace(/_/g, '/');
    while (normalized.length % 4 !== 0) {
      normalized += '=';
    }
    try {
      const buf: buffer.Buffer = buffer.from(normalized, 'base64');
      const decoded: string = buf.toString('utf-8');
      if (
        decoded.includes('://') ||
        decoded.includes('proxies:') ||
        decoded.includes('proxy-groups:')
      ) {
        return decoded;
      }
    } catch (e) {
      // ignore invalid base64
    }
    return '';
  }

  private static stripQuotes(raw: string): string {
    return ProxyChainConfig.scalar(raw);
  }

  static normalizeInput(raw: string): string {
    const clean: string = raw.replace(/^\uFEFF/, '');
    if (/^(mixed-port|port|proxies|proxy-groups|proxy-providers|rules|dns|mode)\s*:/m.test(clean)) { return clean; }
    const decoded: string = YamlProfileParser.tryDecodeBase64(clean);
    return decoded.length > 0 ? decoded : clean;
  }

  static parseYaml(rawInput: string): ParsedYamlSummary {
    const result: ParsedYamlSummary = {
      valid: true,
      errorMessage: '',
      mixedPort: 7890,
      allowLan: false,
      mode: 'rule',
      ipv6: true,
      proxiesCount: 0,
      groupsCount: 0,
      rulesCount: 0,
      parsedNodes: [],
      parsedGroups: []
    };

    if (!rawInput || rawInput.trim().length === 0) {
      result.valid = false;
      result.errorMessage = '配置内容为空';
      return result;
    }

    let content: string = YamlProfileParser.normalizeInput(rawInput);
    if (!content.includes('proxies:') && !content.includes('proxy-groups:') && !content.includes('://')) {
      const decoded: string = YamlProfileParser.tryDecodeBase64(content);
      if (decoded.length > 0) {
        content = decoded;
      }
    }

    content = ClashUriParser.repairBrokenProxiesIndent(content);
    // Normalize flow sequences & multi-line flow objects so line-based YAML parsing handles all valid styles safely.
    const sourceLines: string[] = content.split(/\r?\n/);
    const expandedLines: string[] = [];
    for (let i: number = 0; i < sourceLines.length; i++) {
      const cleanLine: string = ProxyChainConfig.stripComment(sourceLines[i]);
      const trimmedClean: string = cleanLine.trim();
      if (trimmedClean.length === 0) {
        expandedLines.push(cleanLine);
        continue;
      }
      // Merge multi-line flow objects (e.g. `- {\n name: ...\n}`) or flow lists (`proxies: [\n ...\n]`)
      if (trimmedClean.startsWith('- {') && !trimmedClean.endsWith('}')) {
        let merged: string = cleanLine;
        while (i + 1 < sourceLines.length && !merged.trim().endsWith('}')) {
          i += 1;
          const nextClean: string = ProxyChainConfig.stripComment(sourceLines[i]).trim();
          if (nextClean.length > 0) {
            merged += ' ' + nextClean;
          }
        }
        expandedLines.push(merged);
        continue;
      }
      if (/^(proxies|proxy-groups)\s*:\s*\[/.test(trimmedClean) && !trimmedClean.endsWith(']')) {
        let mergedList: string = cleanLine;
        while (i + 1 < sourceLines.length && !mergedList.trim().endsWith(']')) {
          i += 1;
          const nextClean: string = ProxyChainConfig.stripComment(sourceLines[i]).trim();
          if (nextClean.length > 0) {
            mergedList += ' ' + nextClean;
          }
        }
        expandedLines.push(mergedList);
        continue;
      }
      expandedLines.push(cleanLine);
    }

    const lines: string[] = [];
    try {
      for (let i: number = 0; i < expandedLines.length; i++) {
        const line: string = expandedLines[i];
        if (/^(proxies|proxy-groups):\s*\[/.test(line)) {
          const colon: number = line.indexOf(':');
          const collection: string = line.substring(colon + 1).trim();
          if (!collection.endsWith(']')) { throw new Error('proxies 或 proxy-groups 集合未闭合'); }
          lines.push(line.substring(0, colon + 1));
          const entries: string[] = ProxyChainConfig.splitFlow(collection.substring(1, collection.length - 1));
          for (let j: number = 0; j < entries.length; j++) { lines.push('  - ' + entries[j]); }
        } else { lines.push(line); }
      }
    } catch (error) { result.valid = false; result.errorMessage = (error as Error).message; return result; }

    // 1. Check if content is URI share links (socks5://, http://, ss://, vmess://, vless://, trojan://, hy2://, tuic://, wg://, anytls://)
    if (!content.includes('proxies:') && ClashUriParser.hasAnySupportedUriLine(content)) {
      const batch: ClashUriBatchResult = ClashUriParser.parseBatchUris(content);
      for (let i: number = 0; i < batch.entries.length; i++) {
        const e: ClashProxyEntry = batch.entries[i];
        result.parsedNodes.push({
          id: `node_${i + 1}_${e.name}`,
          name: e.name,
          protocol: YamlProfileParser.formatProtocolLabel(e.type),
          regionCode: YamlProfileParser.inferRegionFromName(e.name),
          server: e.server,
          port: e.port,
          udp: e.udp ?? true,
          delayMs: 0,
          isTesting: false,
          providerName: 'Subscription'
        });
      }
      if (result.parsedNodes.length > 0) {
        result.proxiesCount = result.parsedNodes.length;
        const allNames: string[] = result.parsedNodes.map((item: ProxyNodeItem): string => item.name);
        allNames.push('DIRECT');
        result.parsedGroups.push({
          id: 'grp_proxy',
          name: 'Proxy',
          groupType: 'Selector',
          iconText: 'P',
          selectedName: YamlProfileParser.pickDefaultSelected(allNames),
          fixedName: '',
          testUrl: 'https://www.gstatic.com/generate_204',
          isTestingGroup: false,
          nodeNames: allNames,
          hidden: false
        });
        result.parsedGroups.push({
          id: 'grp_auto',
          name: 'Auto',
          groupType: 'URLTest',
          iconText: 'A',
          selectedName: allNames[0],
          fixedName: '',
          testUrl: 'https://www.gstatic.com/generate_204',
          isTestingGroup: false,
          nodeNames: allNames.slice(0, Math.max(1, allNames.length - 1)),
          hidden: false
        });
        result.groupsCount = result.parsedGroups.length;
        result.rulesCount = 2;
        return result;
      }
    }

    // 2. Parse Clash / mihomo YAML sections
    let currentSection: string = '';
    let currentNode: TempProxyNodeFields | null = null;
    let currentGroup: TempProxyGroupFields | null = null;
    const rawGroups: TempProxyGroupFields[] = [];
    let inGroupProxiesList: boolean = false;
    let proxyListIndent: number = -1;
    let proxyPropIndent: number = -1;
    let groupListIndent: number = -1;
    let groupPropIndent: number = -1;

    const flushCurrentNode = (): void => {
      if (currentNode !== null && currentNode.name.length > 0) {
        result.proxiesCount += 1;
        result.parsedNodes.push({
          id: `node_${result.proxiesCount}_${currentNode.name}`,
          name: currentNode.name,
          protocol: YamlProfileParser.formatProtocolLabel(currentNode.typeStr.length > 0 ? currentNode.typeStr : 'trojan'),
          regionCode: YamlProfileParser.inferRegionFromName(currentNode.name),
          server: currentNode.server.length > 0 ? currentNode.server : 'server',
          port: currentNode.port > 0 ? currentNode.port : 443,
          udp: currentNode.udp,
          delayMs: 0,
          isTesting: false,
          providerName: 'Profile'
        });
      }
      currentNode = null;
      proxyPropIndent = -1;
    };

    const flushCurrentGroup = (): void => {
      if (currentGroup !== null && currentGroup.name.length > 0) {
        rawGroups.push(currentGroup);
      }
      currentGroup = null;
      inGroupProxiesList = false;
      groupPropIndent = -1;
    };

    for (let i = 0; i < lines.length; i++) {
      const rawLine: string = lines[i];
      const trimmed: string = rawLine.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }

      const indent: number = rawLine.search(/\S/);
      if (indent === 0 && !trimmed.startsWith('-') && trimmed.includes(':')) {
        flushCurrentNode();
        flushCurrentGroup();

        const colonIdx: number = trimmed.indexOf(':');
        const key: string = trimmed.substring(0, colonIdx).trim();
        const val: string = trimmed.substring(colonIdx + 1).trim();
        currentSection = key;

        if (key === 'mixed-port' || key === 'port') {
          const p: number = parseInt(val, 10);
          if (!isNaN(p) && p > 0 && p < 65536) {
            result.mixedPort = p;
          }
        } else if (key === 'allow-lan') {
          result.allowLan = val === 'true';
        } else if (key === 'mode') {
          result.mode = YamlProfileParser.stripQuotes(val);
        } else if (key === 'ipv6') {
          result.ipv6 = val === 'true';
        }
        continue;
      }

      if (currentSection === 'proxies') {
        if (trimmed.startsWith('-') && (proxyListIndent === -1 || indent === proxyListIndent)) {
          proxyListIndent = indent;
          flushCurrentNode();
          const afterDash: string = trimmed.substring(1).trim();
          // Flow-style object: - { name: ..., type: ..., server: ..., port: ... }
          if (afterDash.startsWith('{') || (afterDash.includes('name:') && afterDash.includes('type:'))) {
            if (!afterDash.endsWith('}')) { result.valid = false; result.errorMessage = '流式节点花括号未闭合'; return result; }
            currentNode = { name: '', typeStr: '', server: '', port: 0, udp: true };
            try {
              const innerBody: string = afterDash.startsWith('{')
                ? afterDash.substring(1, afterDash.length - 1)
                : afterDash;
              const entries: string[] = ProxyChainConfig.splitFlow(innerBody);
              for (let fIdx: number = 0; fIdx < entries.length; fIdx++) {
                const f: LexiYamlField = ProxyChainConfig.field(entries[fIdx]);
                const v: string = ProxyChainConfig.scalar(f.rawValue);
                if (f.key === 'name') { currentNode.name = v; }
                else if (f.key === 'type') { currentNode.typeStr = v; }
                else if (f.key === 'server') { currentNode.server = v; }
                else if (f.key === 'port') { currentNode.port = parseInt(v, 10); }
                else if (f.key === 'udp') { currentNode.udp = v !== 'false'; }
              }
            } catch (error) { result.valid = false; result.errorMessage = (error as Error).message; return result; }
            flushCurrentNode();
          } else {
            // Block-style item under proxies:
            currentNode = {
              name: '',
              typeStr: 'trojan',
              server: 'server',
              port: 443,
              udp: true
            };
            if (afterDash.includes(':')) {
              const f: LexiYamlField = ProxyChainConfig.field(afterDash);
              const fVal: string = ProxyChainConfig.scalar(f.rawValue);
              if (f.key === 'name') currentNode.name = fVal;
              else if (f.key === 'type') currentNode.typeStr = fVal;
              else if (f.key === 'server') currentNode.server = fVal;
              else if (f.key === 'port') currentNode.port = parseInt(fVal, 10) || 443;
              else if (f.key === 'udp') currentNode.udp = fVal !== 'false';
            }
          }
        } else if (currentNode !== null && indent > proxyListIndent && trimmed.includes(':')) {
          if (proxyPropIndent === -1) {
            proxyPropIndent = indent;
          }
          if (indent === proxyPropIndent) {
            const f: LexiYamlField = ProxyChainConfig.field(trimmed);
            const fVal: string = ProxyChainConfig.scalar(f.rawValue);
            if (f.key === 'name') currentNode.name = fVal;
            else if (f.key === 'type') currentNode.typeStr = fVal;
            else if (f.key === 'server') currentNode.server = fVal;
            else if (f.key === 'port') currentNode.port = parseInt(fVal, 10) || 443;
            else if (f.key === 'udp') currentNode.udp = fVal !== 'false';
          }
        }
      } else if (currentSection === 'proxy-groups') {
        // Distinguish a new group item (`  - name:` or `  - {`) from a member item inside `proxies:` (`      - NodeName`)
        const isGroupListMember: boolean = inGroupProxiesList && trimmed.startsWith('-') && indent > groupListIndent;
        if (isGroupListMember && currentGroup !== null) {
          const memberName: string = YamlProfileParser.stripQuotes(trimmed.substring(1));
          if (memberName.length > 0) {
            currentGroup.nodeNames.push(memberName);
          }
        } else if (trimmed.startsWith('-') && (groupListIndent === -1 || indent === groupListIndent)) {
          groupListIndent = indent;
          flushCurrentGroup();
          const afterDash: string = trimmed.substring(1).trim();
          currentGroup = {
            name: '',
            typeStr: 'select',
            nodeNames: [],
            includeAll: false,
            filterRegex: '',
            excludeFilterRegex: ''
          };

          if (afterDash.startsWith('{') || (afterDash.includes('name:') && afterDash.includes('type:'))) {
            if (afterDash.startsWith('{') && !afterDash.endsWith('}')) {
              result.valid = false;
              result.errorMessage = '流式策略组花括号未闭合';
              return result;
            }
            try {
              const innerGroupBody: string = afterDash.startsWith('{')
                ? afterDash.substring(1, afterDash.length - 1)
                : afterDash;
              const entries: string[] = ProxyChainConfig.splitFlow(innerGroupBody);
              for (let eIdx: number = 0; eIdx < entries.length; eIdx++) {
                const f: LexiYamlField = ProxyChainConfig.field(entries[eIdx]);
                const rawV: string = f.rawValue.trim();
                const valScalar: string = ProxyChainConfig.scalar(rawV);
                if (f.key === 'name') {
                  currentGroup.name = valScalar;
                } else if (f.key === 'type') {
                  currentGroup.typeStr = valScalar;
                } else if (f.key === 'include-all' || f.key === 'include-all-proxies') {
                  if (valScalar === 'true') {
                    currentGroup.includeAll = true;
                  }
                } else if (f.key === 'filter') {
                  currentGroup.filterRegex = valScalar;
                } else if (f.key === 'exclude-filter') {
                  currentGroup.excludeFilterRegex = valScalar;
                } else if (f.key === 'proxies' && rawV.startsWith('[') && rawV.endsWith(']')) {
                  const items: string[] = ProxyChainConfig.splitFlow(rawV.substring(1, rawV.length - 1));
                  for (let k: number = 0; k < items.length; k++) {
                    const pName: string = YamlProfileParser.stripQuotes(items[k]);
                    if (pName.length > 0) {
                      currentGroup.nodeNames.push(pName);
                    }
                  }
                }
              }
            } catch (error) {
              result.valid = false;
              result.errorMessage = (error as Error).message;
              return result;
            }
            flushCurrentGroup();
          } else if (afterDash.includes(':')) {
            const f: LexiYamlField = ProxyChainConfig.field(afterDash);
            const fVal: string = ProxyChainConfig.scalar(f.rawValue);
            if (f.key === 'name') currentGroup.name = fVal;
            else if (f.key === 'type') currentGroup.typeStr = fVal;
          }
        } else if (currentGroup !== null && indent > groupListIndent && trimmed.includes(':')) {
          if (groupPropIndent === -1) {
            groupPropIndent = indent;
          }
          if (indent === groupPropIndent) {
            const f: LexiYamlField = ProxyChainConfig.field(trimmed);
            const rawVal: string = f.rawValue.trim();
            const fVal: string = ProxyChainConfig.scalar(rawVal);

            if (f.key === 'proxies') {
              if (rawVal.startsWith('[') && rawVal.endsWith(']')) {
                try {
                  const inner: string = rawVal.substring(1, rawVal.length - 1);
                  const items: string[] = ProxyChainConfig.splitFlow(inner);
                  for (let k = 0; k < items.length; k++) {
                    const pName: string = YamlProfileParser.stripQuotes(items[k]);
                    if (pName.length > 0) {
                      currentGroup.nodeNames.push(pName);
                    }
                  }
                } catch (error) {
                  result.valid = false;
                  result.errorMessage = (error as Error).message;
                  return result;
                }
                inGroupProxiesList = false;
              } else {
                inGroupProxiesList = true;
              }
            } else {
              inGroupProxiesList = false;
              if (f.key === 'name') currentGroup.name = fVal;
              else if (f.key === 'type') currentGroup.typeStr = fVal;
              else if (f.key === 'include-all' || f.key === 'include-all-proxies') {
                if (fVal === 'true') {
                  currentGroup.includeAll = true;
                }
              } else if (f.key === 'filter') {
                currentGroup.filterRegex = fVal;
              } else if (f.key === 'exclude-filter') {
                currentGroup.excludeFilterRegex = fVal;
              }
            }
          }
        }
      } else if (currentSection === 'rules') {
        if (trimmed.startsWith('-')) {
          result.rulesCount += 1;
        }
      }
    }

    flushCurrentNode();
    flushCurrentGroup();

    // 3. Resolve rawGroups (expand include-all / empty provider groups with parsedNodes)
    const allParsedNodeNames: string[] = [];
    for (let i = 0; i < result.parsedNodes.length; i++) {
      allParsedNodeNames.push(result.parsedNodes[i].name);
    }

    for (let gIdx = 0; gIdx < rawGroups.length; gIdx++) {
      const rg: TempProxyGroupFields = rawGroups[gIdx];
      const finalMembers: string[] = rg.nodeNames.slice();

      if ((rg.includeAll || finalMembers.length === 0) && allParsedNodeNames.length > 0) {
        for (let nIdx = 0; nIdx < allParsedNodeNames.length; nIdx++) {
          const candidate: string = allParsedNodeNames[nIdx];
          if (finalMembers.includes(candidate)) {
            continue;
          }
          if (rg.filterRegex.length > 0) {
            try {
              const re: RegExp = new RegExp(rg.filterRegex, 'i');
              if (!re.test(candidate)) {
                continue;
              }
            } catch (e) {
              // ignore invalid regex
            }
          }
          if (rg.excludeFilterRegex.length > 0) {
            try {
              const exRe: RegExp = new RegExp(rg.excludeFilterRegex, 'i');
              if (exRe.test(candidate)) {
                continue;
              }
            } catch (e) {
              // ignore
            }
          }
          finalMembers.push(candidate);
        }
      }

      if (finalMembers.length === 0) {
        finalMembers.push('DIRECT');
      }

      result.parsedGroups.push({
        id: `grp_${gIdx + 1}_${rg.name}`,
        name: rg.name,
        groupType: YamlProfileParser.formatGroupKind(rg.typeStr),
        iconText: rg.name.substring(0, 1).toUpperCase(),
        selectedName: YamlProfileParser.pickDefaultSelected(finalMembers),
        fixedName: '',
        testUrl: 'https://www.gstatic.com/generate_204',
        isTestingGroup: false,
        nodeNames: finalMembers,
        hidden: false
      });
    }

    // If proxies were parsed but no proxy-groups existed, build a default Selector group
    if (result.parsedNodes.length > 0 && result.parsedGroups.length === 0) {
      const names: string[] = allParsedNodeNames.slice();
      names.push('DIRECT');
      result.parsedGroups.push({
        id: 'grp_proxy',
        name: 'Proxy',
        groupType: 'Selector',
        iconText: 'P',
        selectedName: YamlProfileParser.pickDefaultSelected(names),
        fixedName: '',
        testUrl: 'https://www.gstatic.com/generate_204',
        isTestingGroup: false,
        nodeNames: names,
        hidden: false
      });
    }

    result.groupsCount = result.parsedGroups.length;

    if (
      result.proxiesCount === 0 &&
      result.groupsCount === 0 &&
      result.rulesCount === 0 &&
      !content.includes('mixed-port') &&
      !content.includes('proxies:') &&
      !content.includes('rules:')
    ) {
      result.valid = false;
      result.errorMessage = '未能识别有效的 Clash/mihomo 配置字段或节点链接';
    }

    return result;
  }

  static pickDefaultSelected(members: string[]): string {
    if (members.length === 0) {
      return 'DIRECT';
    }
    for (let i: number = 0; i < members.length; i++) {
      const cand: string = members[i];
      if (
        !cand.includes('剩余流量') &&
        !cand.includes('距离下次') &&
        !cand.includes('套餐到期') &&
        !cand.includes('官网') &&
        !cand.includes('过期时间')
      ) {
        return cand;
      }
    }
    return members[0];
  }

  static formatGroupKind(raw: string): ProxyGroupKind {
    const lower: string = raw.toLowerCase();
    if (lower === 'url-test' || lower === 'urltest') {
      return 'URLTest';
    }
    if (lower === 'fallback') {
      return 'Fallback';
    }
    if (lower === 'load-balance' || lower === 'loadbalance') {
      return 'LoadBalance';
    }
    return 'Selector';
  }

  static formatProtocolLabel(raw: string): string {
    const lower: string = raw.toLowerCase();
    if (lower === 'ss' || lower === 'shadowsocks') return 'Shadowsocks';
    if (lower === 'ssr') return 'ShadowsocksR';
    if (lower === 'vmess') return 'VMess';
    if (lower === 'vless') return 'VLess';
    if (lower === 'trojan') return 'Trojan';
    if (lower === 'hysteria2' || lower === 'hy2') return 'Hysteria2';
    if (lower === 'hysteria') return 'Hysteria';
    if (lower === 'tuic') return 'TUIC';
    if (lower === 'wireguard' || lower === 'wg') return 'WireGuard';
    if (lower === 'anytls') return 'AnyTLS';
    return raw.toUpperCase();
  }

  static inferRegionFromName(name: string): string {
    const upper: string = name.toUpperCase();
    if (name.includes('🇺🇸') || upper.includes('UNITED STATES') || upper.includes('USA') || name.includes('美国')) return 'US';
    if (name.includes('🇭🇰') || upper.includes('HONG KONG') || upper.includes('HK') || name.includes('香港')) return 'HK';
    if (name.includes('🇯🇵') || upper.includes('JAPAN') || upper.includes('JP') || name.includes('日本') || name.includes('东京') || name.includes('大阪')) return 'JP';
    if (name.includes('🇸🇬') || upper.includes('SINGAPORE') || upper.includes('SG') || name.includes('狮城') || name.includes('新加坡')) return 'SG';
    if (name.includes('🇹🇼') || upper.includes('TAIWAN') || upper.includes('TW') || name.includes('台湾') || name.includes('台北')) return 'TW';
    if (name.includes('🇩🇪') || upper.includes('GERMANY') || upper.includes('DE') || name.includes('德国') || name.includes('法兰克福')) return 'DE';
    if (name.includes('🇬🇧') || upper.includes('UNITED KINGDOM') || upper.includes('UK') || name.includes('英国') || name.includes('伦敦')) return 'UK';
    if (name.includes('🇰🇷') || upper.includes('KOREA') || upper.includes('KR') || name.includes('韩国') || name.includes('首尔')) return 'KR';
    return 'GL';
  }
}

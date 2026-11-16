// Lossless edits to the top-level proxies sequence. Credentials and nested transport options stay intact.
export interface LexiChainBuildResult {
  yamlContent: string;
  errorMessage: string;
}

export interface LexiYamlField {
  key: string;
  rawValue: string;
}

interface LexiChainProxyBlock {
  name: string;
  lines: string[];
  fields: string[];
  flow: boolean;
  indent: number;
}

export class ProxyChainConfig {
  static stripComment(raw: string): string {
    let quote: string = '';
    for (let i: number = 0; i < raw.length; i++) {
      const ch: string = raw[i];
      if (quote === '"' && ch === '\\') { i++; continue; }
      if (ch === quote) {
        if (quote === "'" && raw[i + 1] === "'") { i++; continue; }
        quote = '';
      } else if (quote.length === 0 && (ch === '"' || ch === "'")) {
        quote = ch;
      } else if (quote.length === 0 && ch === '#' && (i === 0 || /\s/.test(raw[i - 1]))) {
        return raw.substring(0, i).trimEnd();
      }
    }
    return raw.trimEnd();
  }

  static scalar(raw: string): string {
    const clean: string = ProxyChainConfig.stripComment(raw).trim();
    if (clean.startsWith('"') && clean.endsWith('"')) {
      try { return JSON.parse(clean) as string; } catch (error) { return ''; }
    }
    if (clean.startsWith("'") && clean.endsWith("'")) {
      return clean.substring(1, clean.length - 1).replace(/''/g, "'");
    }
    return clean;
  }

  // Split only at the current collection depth, respecting quoted commas and nested maps/lists.
  static splitFlow(raw: string): string[] {
    const items: string[] = [];
    let depth: number = 0;
    let quote: string = '';
    let start: number = 0;
    for (let i: number = 0; i < raw.length; i++) {
      const ch: string = raw[i];
      if (quote === '"' && ch === '\\') { i++; continue; }
      if (quote.length > 0) {
        if (ch === quote) {
          if (quote === "'" && raw[i + 1] === "'") { i++; continue; }
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; }
      else if (ch === '{' || ch === '[') { depth++; }
      else if (ch === '}' || ch === ']') { depth--; }
      else if (ch === ',' && depth === 0) {
        items.push(raw.substring(start, i).trim()); start = i + 1;
      }
      if (depth < 0) { throw new Error('YAML 流式集合括号不匹配'); }
    }
    if (depth !== 0 || quote.length > 0) { throw new Error('YAML 引号或集合未闭合'); }
    const last: string = raw.substring(start).trim();
    if (last.length > 0) { items.push(last); }
    return items;
  }

  static field(raw: string): LexiYamlField {
    let quote: string = '';
    for (let i: number = 0; i < raw.length; i++) {
      const ch: string = raw[i];
      if (quote === '"' && ch === '\\') { i++; continue; }
      if (quote.length > 0) {
        if (ch === quote) {
          if (quote === "'" && raw[i + 1] === "'") { i++; continue; }
          quote = '';
        }
      } else if (ch === '"' || ch === "'") { quote = ch; }
      else if (ch === ':') {
        return { key: ProxyChainConfig.scalar(raw.substring(0, i)), rawValue: raw.substring(i + 1).trim() };
      }
    }
    return { key: '', rawValue: '' };
  }

  private static readBlock(lines: string[], indent: number): LexiChainProxyBlock {
    const first: string = ProxyChainConfig.stripComment(lines[0].trim().substring(1).trim());
    const joined: string = lines.map((line: string): string => ProxyChainConfig.stripComment(line)).join('\n');
    const flow: boolean = first.startsWith('{');
    const fields: string[] = [];
    let name: string = '';
    if (flow) {
      const mapping: string = joined.trim().substring(1).trim();
      if (!mapping.endsWith('}')) { throw new Error('不支持的代理节点 YAML 格式'); }
      const entries: string[] = ProxyChainConfig.splitFlow(mapping.substring(1, mapping.length - 1));
      for (let i: number = 0; i < entries.length; i++) {
        const f: LexiYamlField = ProxyChainConfig.field(entries[i]);
        if (f.key === '<<') { throw new Error('含 YAML 合并键的节点请先展开后再使用链式代理'); }
        if (f.key === 'name') { name = ProxyChainConfig.scalar(f.rawValue); }
        fields.push(entries[i]);
      }
    } else {
      for (let i: number = 0; i < lines.length; i++) {
        const entry: string = i === 0 ? first : lines[i].trim();
        if (i !== 0 && lines[i].search(/\S/) !== indent + 2) { continue; }
        const f: LexiYamlField = ProxyChainConfig.field(entry);
        if (f.key === '<<') { throw new Error('含 YAML 合并键的节点请先展开后再使用链式代理'); }
        if (f.key === 'name') { name = ProxyChainConfig.scalar(f.rawValue); }
      }
    }
    if (name.length === 0 || first.startsWith('*') || first.startsWith('&')) {
      throw new Error('链式代理需要具有明确名称的节点，暂不支持 YAML 锚点或别名');
    }
    return { name: name, lines: lines, fields: fields, flow: flow, indent: indent };
  }

  private static extractDialerFromBlock(block: LexiChainProxyBlock): string {
    if (block.flow) {
      for (let i: number = 0; i < block.fields.length; i++) {
        const f: LexiYamlField = ProxyChainConfig.field(block.fields[i]);
        if (f.key === 'dialer-proxy') {
          return ProxyChainConfig.scalar(f.rawValue);
        }
      }
      return '';
    }
    for (let i: number = 0; i < block.lines.length; i++) {
      const line: string = block.lines[i];
      if (i !== 0 && line.search(/\S/) !== block.indent + 2) { continue; }
      const entry: string = i === 0 ? ProxyChainConfig.stripComment(line.trim().substring(1).trim()) : line.trim();
      const f: LexiYamlField = ProxyChainConfig.field(entry);
      if (f.key === 'dialer-proxy') {
        return ProxyChainConfig.scalar(f.rawValue);
      }
    }
    return '';
  }

  private static parseBlocksFromYaml(profileYaml: string): LexiChainProxyBlock[] {
    const lines: string[] = profileYaml.replace(/^\uFEFF/, '').split(/\r?\n/);
    let sectionStart: number = -1;
    let sectionEnd: number = lines.length;
    for (let i: number = 0; i < lines.length; i++) {
      const scanned: string = ProxyChainConfig.stripComment(lines[i]);
      if (scanned.trim().length === 0 || scanned.trim() === '---') { continue; }
      if (scanned.trim() === '...') {
        if (sectionStart !== -1 && sectionEnd === lines.length) { sectionEnd = i; }
        continue;
      }
      if (/^proxies\s*:/.test(scanned)) { sectionStart = i; }
      else if (sectionStart !== -1 && sectionEnd === lines.length && /^\S[^\n]*:/.test(scanned) && !scanned.startsWith('-')) {
        sectionEnd = i;
      }
    }
    if (sectionStart < 0) { return []; }
    const inline: string = ProxyChainConfig.stripComment(lines[sectionStart].substring(lines[sectionStart].indexOf(':') + 1)).trim();
    const blocks: LexiChainProxyBlock[] = [];
    if (inline.startsWith('[') && inline.endsWith(']')) {
      const items: string[] = ProxyChainConfig.splitFlow(inline.substring(1, inline.length - 1));
      for (let i: number = 0; i < items.length; i++) { blocks.push(ProxyChainConfig.readBlock(['  - ' + items[i]], 2)); }
    } else if (inline.length === 0) {
      let pending: string[] = [];
      let listIndent: number = -1;
      for (let i: number = sectionStart + 1; i < sectionEnd; i++) {
        const line: string = lines[i];
        const indent: number = line.search(/\S/);
        if (/^\s*-\s/.test(line) && (listIndent === -1 || indent === listIndent)) {
          if (pending.length > 0) { blocks.push(ProxyChainConfig.readBlock(pending, listIndent)); }
          listIndent = indent; pending = [line];
        } else if (pending.length > 0) { pending.push(line); }
      }
      if (pending.length > 0) { blocks.push(ProxyChainConfig.readBlock(pending, listIndent)); }
    }
    return blocks;
  }

  /**
   * Reconstructs the ordered chain [entry, ..., exitNode] from `dialer-proxy` links in YAML,
   * matching clash-verge-rev's `get_runtime_proxy_chain_config`.
   */
  static readChain(profileYaml: string, exitNode: string): string[] {
    if (exitNode.length === 0) { return []; }
    try {
      const blocks: LexiChainProxyBlock[] = ProxyChainConfig.parseBlocksFromYaml(profileYaml);
      const dialerByName: Map<string, string> = new Map<string, string>();
      const validNames: Set<string> = new Set<string>();
      for (let i: number = 0; i < blocks.length; i++) {
        validNames.add(blocks[i].name);
        const dialer: string = ProxyChainConfig.extractDialerFromBlock(blocks[i]);
        if (dialer.length > 0) {
          dialerByName.set(blocks[i].name, dialer);
        }
      }
      const reversed: string[] = [];
      const visited: Set<string> = new Set<string>();
      let cursor: string = exitNode;
      while (cursor.length > 0 && dialerByName.has(cursor) && !visited.has(cursor)) {
        visited.add(cursor);
        reversed.push(cursor);
        cursor = dialerByName.get(cursor) ?? '';
      }
      if (reversed.length > 0 && cursor.length > 0 && validNames.has(cursor) && !visited.has(cursor)) {
        reversed.push(cursor);
      } else if (reversed.length === 0) {
        return [];
      }
      reversed.reverse();
      return reversed.length >= 2 ? reversed : [];
    } catch (_err) {
      return [];
    }
  }

  static build(profileYaml: string, chainNames: string[]): LexiChainBuildResult {
    try {
      const lines: string[] = profileYaml.replace(/^\uFEFF/, '').split(/\r?\n/);
      let sectionStart: number = -1;
      let sectionEnd: number = lines.length;
      let documentStarted: boolean = false;
      let documentEnded: boolean = false;
      for (let i: number = 0; i < lines.length; i++) {
        const scanned: string = ProxyChainConfig.stripComment(lines[i]);
        if (scanned.trim().length === 0) { continue; }
        if (scanned.trim() === '---') {
          if (documentStarted) { throw new Error('链式代理不支持多文档 YAML 配置'); }
          documentStarted = true; continue;
        }
        if (scanned.trim() === '...') {
          documentEnded = true;
          if (sectionStart !== -1 && sectionEnd === lines.length) { sectionEnd = i; }
          continue;
        }
        if (documentEnded) { throw new Error('YAML 文档结束符后存在额外内容'); }
        documentStarted = true;
        if (/^proxies\s*:/.test(scanned)) {
          if (sectionStart !== -1) { throw new Error('配置包含重复的 proxies 字段'); }
          sectionStart = i;
        } else if (sectionStart !== -1 && sectionEnd === lines.length && /^\S[^\n]*:/.test(scanned) && !scanned.startsWith('-')) {
          sectionEnd = i;
        }
      }
      if (sectionStart < 0) { throw new Error('配置中没有可用于链式代理的 proxies 节点'); }
      const inline: string = ProxyChainConfig.stripComment(lines[sectionStart].substring(lines[sectionStart].indexOf(':') + 1)).trim();
      const blocks: LexiChainProxyBlock[] = [];
      if (inline.startsWith('[')) {
        if (!inline.endsWith(']')) { throw new Error('请将跨行的 proxies 流式数组转换为块式列表'); }
        const items: string[] = ProxyChainConfig.splitFlow(inline.substring(1, inline.length - 1));
        for (let i: number = 0; i < items.length; i++) { blocks.push(ProxyChainConfig.readBlock(['  - ' + items[i]], 2)); }
      } else {
        if (inline.length > 0) { throw new Error('请将 proxies 锚点展开为节点列表'); }
        let pending: string[] = [];
        let listIndent: number = -1;
        for (let i: number = sectionStart + 1; i < sectionEnd; i++) {
          const line: string = lines[i];
          const indent: number = line.search(/\S/);
          if (/^\s*-\s/.test(line) && (listIndent === -1 || indent === listIndent)) {
            if (pending.length > 0) { blocks.push(ProxyChainConfig.readBlock(pending, listIndent)); }
            listIndent = indent; pending = [line];
          } else if (pending.length > 0) { pending.push(line); }
        }
        if (pending.length > 0) { blocks.push(ProxyChainConfig.readBlock(pending, listIndent)); }
      }
      const available: string[] = blocks.map((block: LexiChainProxyBlock): string => block.name);
      if (new Set<string>(available).size !== available.length) { throw new Error('配置包含同名节点，无法确定链式代理的节点'); }
      if (new Set<string>(chainNames).size !== chainNames.length) { throw new Error('不能重复添加同一个节点'); }
      for (let i: number = 0; i < chainNames.length; i++) {
        if (chainNames[i] === 'DIRECT' || chainNames[i] === 'REJECT' || !available.includes(chainNames[i])) {
          throw new Error('节点已失效或不是独立代理节点：' + chainNames[i]);
        }
      }
      const output: string[] = ['proxies:'];
      for (let i: number = 0; i < blocks.length; i++) {
        const block: LexiChainProxyBlock = blocks[i];
        const chainIndex: number = chainNames.indexOf(block.name);
        const dialer: string = chainIndex > 0 ? chainNames[chainIndex - 1] : '';
        if (block.flow) {
          const fields: string[] = block.fields.filter((entry: string): boolean => ProxyChainConfig.field(entry).key !== 'dialer-proxy');
          if (dialer.length > 0) { fields.push('dialer-proxy: ' + JSON.stringify(dialer)); }
          output.push(' '.repeat(block.indent) + '- {' + fields.join(', ') + '}');
        } else {
          const pad: string = ' '.repeat(block.indent + 2);
          for (let j: number = 0; j < block.lines.length; j++) {
            const line: string = block.lines[j];
            const direct: boolean = j === 0 || line.search(/\S/) === block.indent + 2;
            const f: LexiYamlField = ProxyChainConfig.field(j === 0 ? line.trim().substring(1).trim() : line.trim());
            if (direct && f.key === 'dialer-proxy') {
              if (j === 0) { output.push(' '.repeat(block.indent) + '- name: ' + JSON.stringify(block.name)); }
              continue;
            }
            // A name already emitted above must not be repeated.
            if (j > 0 && direct && f.key === 'name' && ProxyChainConfig.field(block.lines[0].trim().substring(1)).key === 'dialer-proxy') { continue; }
            output.push(line);
          }
          if (dialer.length > 0) {
            // Insert before trailing blank lines, keeping it inside this mapping.
            while (output.length > 0 && output[output.length - 1].trim().length === 0) { output.pop(); }
            output.push(pad + 'dialer-proxy: ' + JSON.stringify(dialer));
          }
        }
      }
      const result: string[] = lines.slice(0, sectionStart).concat(output).concat(lines.slice(sectionEnd));
      return { yamlContent: result.join('\n'), errorMessage: '' };
    } catch (error) {
      return { yamlContent: '', errorMessage: (error as Error).message };
    }
  }
}

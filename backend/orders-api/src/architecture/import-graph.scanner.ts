import { readdirSync, readFileSync, statSync } from 'fs';
import { dirname, extname, join, normalize, relative, resolve } from 'path';
import type { DomainKey } from './domain-id';
import { DomainId } from './domain-id';

const SRC = join(process.cwd(), 'src');

/** Known approved cross-domain edges in the current monolith (event handlers, gateway, health, etc.). */
const ALLOWED_EDGES: ReadonlyArray<{ from: DomainKey; to: DomainKey }> = [
  { from: DomainId.Gateway, to: DomainId.Events },
  { from: DomainId.Gateway, to: DomainId.Identity },
  { from: DomainId.Events, to: DomainId.Gateway },
  { from: DomainId.Events, to: DomainId.Search },
  { from: DomainId.Events, to: DomainId.Identity },
  { from: DomainId.Search, to: DomainId.Gateway },
  { from: DomainId.Search, to: DomainId.Identity },
  { from: DomainId.Search, to: DomainId.Events },
  { from: DomainId.Orders, to: DomainId.Gateway },
  { from: DomainId.Orders, to: DomainId.Events },
  { from: DomainId.Orders, to: DomainId.Identity },
  { from: DomainId.Identity, to: DomainId.Gateway },
  { from: DomainId.Platform, to: DomainId.Orders },
  { from: DomainId.Platform, to: DomainId.Search },
  { from: DomainId.Platform, to: DomainId.Gateway },
  { from: DomainId.Platform, to: DomainId.Identity },
  { from: DomainId.Platform, to: DomainId.Events },
];

function filePathToDomain(absPath: string): DomainKey {
  const rel = relative(SRC, absPath).replace(/\\/g, '/');
  if (rel.startsWith('..')) return 'unknown';
  const seg = rel.split('/')[0];
  switch (seg) {
    case 'orders':
      return DomainId.Orders;
    case 'search':
      return DomainId.Search;
    case 'events':
      return DomainId.Events;
    case 'identity':
      return DomainId.Identity;
    case 'gateway':
      return DomainId.Gateway;
    case 'health':
    case 'metrics':
    case 'ops-dashboard':
      return DomainId.Platform;
    case 'architecture':
      return DomainId.Platform;
    default:
      return 'unknown';
  }
}

function walkTsFiles(dir: string, out: string[]): void {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const name of entries) {
    if (name === 'node_modules' || name === 'dist') continue;
    const p = join(dir, name);
    let st: ReturnType<typeof statSync>;
    try {
      st = statSync(p);
    } catch {
      continue;
    }
    if (st.isDirectory()) {
      walkTsFiles(p, out);
    } else if (extname(p) === '.ts' && !p.endsWith('.d.ts')) {
      out.push(p);
    }
  }
}

function resolveRelativeImport(fromFile: string, spec: string): string | null {
  if (!spec.startsWith('.')) return null;
  const base = dirname(fromFile);
  const resolved = normalize(resolve(base, spec));
  if (!resolved.startsWith(SRC)) return null;
  return resolved;
}

const IMPORT_RE = /from\s+['"]([^'"]+)['"]/g;

export interface ImportEdge {
  fromFile: string;
  toFile: string | null;
  spec: string;
  fromDomain: DomainKey;
  toDomain: DomainKey;
}

export function scanImportEdges(): ImportEdge[] {
  const files: string[] = [];
  walkTsFiles(SRC, files);
  const edges: ImportEdge[] = [];

  for (const file of files) {
    const fromDomain = filePathToDomain(file);
    let content: string;
    try {
      content = readFileSync(file, 'utf8');
    } catch {
      continue;
    }
    let m: RegExpExecArray | null;
    IMPORT_RE.lastIndex = 0;
    while ((m = IMPORT_RE.exec(content)) !== null) {
      const spec = m[1];
      const resolved = resolveRelativeImport(file, spec);
      const toDomain: DomainKey = resolved ? filePathToDomain(resolved) : 'unknown';
      edges.push({
        fromFile: file,
        toFile: resolved,
        spec,
        fromDomain,
        toDomain,
      });
    }
  }
  return edges;
}

function edgeAllowed(from: DomainKey, to: DomainKey): boolean {
  if (from === to) return true;
  if (from === 'unknown' || to === 'unknown') return true;
  return ALLOWED_EDGES.some((e) => e.from === from && e.to === to);
}

export interface CouplingMap {
  [from: string]: { [to: string]: number };
}

export function buildCouplingMap(edges: ImportEdge[]): CouplingMap {
  const map: CouplingMap = {};
  for (const e of edges) {
    if (e.fromDomain === 'unknown' || e.toDomain === 'unknown') continue;
    if (!map[e.fromDomain]) map[e.fromDomain] = {};
    const row = map[e.fromDomain]!;
    row[e.toDomain] = (row[e.toDomain] ?? 0) + 1;
  }
  return map;
}

export interface ScanViolation {
  file: string;
  from: DomainKey;
  to: DomainKey;
  spec: string;
  message: string;
}

export function findCrossDomainViolations(edges: ImportEdge[]): ScanViolation[] {
  const out: ScanViolation[] = [];
  for (const e of edges) {
    if (!e.toFile) continue;
    if (e.fromDomain === e.toDomain) continue;
    if (edgeAllowed(e.fromDomain, e.toDomain)) continue;
    out.push({
      file: e.fromFile,
      from: e.fromDomain,
      to: e.toDomain,
      spec: e.spec,
      message: `Cross-domain import ${e.fromDomain} → ${e.toDomain} not in allowlist`,
    });
  }
  return out;
}

const REPO_LEAK_PATTERNS = [
  /-pg\.service['"]/i,
  /\.repository['"]/i,
  /repository\.service['"]/i,
];

export interface RepoLeakViolation {
  file: string;
  line: number;
  text: string;
}

export function findRepositoryLeakHints(files: string[]): RepoLeakViolation[] {
  const violations: RepoLeakViolation[] = [];
  for (const file of files) {
    const fromDomain = filePathToDomain(file);
    let lines: string[];
    try {
      lines = readFileSync(file, 'utf8').split(/\r?\n/);
    } catch {
      continue;
    }
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]!;
      if (!line.includes('from ')) continue;
      for (const re of REPO_LEAK_PATTERNS) {
        if (!re.test(line)) continue;
        const target = line.match(/from\s+['"]([^'"]+)['"]/)?.[1];
        if (!target || !target.startsWith('.')) continue;
        const resolved = resolveRelativeImport(file, target);
        if (!resolved) continue;
        const toDomain = filePathToDomain(resolved);
        if (fromDomain === toDomain || fromDomain === 'unknown' || toDomain === 'unknown')
          continue;
        if (edgeAllowed(fromDomain, toDomain)) continue;
        violations.push({
          file,
          line: i + 1,
          text: line.trim(),
        });
        break;
      }
    }
  }
  return violations;
}

export function listAllTsFilesUnderSrc(): string[] {
  const files: string[] = [];
  walkTsFiles(SRC, files);
  return files;
}

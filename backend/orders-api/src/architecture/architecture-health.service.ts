import { Injectable } from '@nestjs/common';
import { isArchitectureStrictMode } from './architecture.config';
import {
  buildCouplingMap,
  findCrossDomainViolations,
  findRepositoryLeakHints,
  listAllTsFilesUnderSrc,
  scanImportEdges,
} from './import-graph.scanner';

export interface ArchitectureHealthReport {
  score: number;
  strictMode: boolean;
  scannedFiles: number;
  importEdgeCount: number;
  violations: Array<{
    kind: 'import' | 'repository_leak';
    file: string;
    line?: number;
    message: string;
    from?: string;
    to?: string;
  }>;
  couplingMap: Record<string, Record<string, number>>;
}

@Injectable()
export class ArchitectureHealthService {
  getReport(): ArchitectureHealthReport {
    const files = listAllTsFilesUnderSrc();
    const edges = scanImportEdges();
    const importViolations = findCrossDomainViolations(edges);
    const repoHints = findRepositoryLeakHints(files);
    const couplingMap = buildCouplingMap(edges);

    const violations: ArchitectureHealthReport['violations'] = [
      ...importViolations.map((v) => ({
        kind: 'import' as const,
        file: v.file,
        message: v.message,
        from: String(v.from),
        to: String(v.to),
      })),
      ...repoHints.map((v) => ({
        kind: 'repository_leak' as const,
        file: v.file,
        line: v.line,
        message: `Possible cross-domain repository import: ${v.text}`,
      })),
    ];

    const penalty = violations.length * 3;
    const score = Math.max(0, Math.min(100, 100 - penalty));

    return {
      score,
      strictMode: isArchitectureStrictMode(),
      scannedFiles: files.length,
      importEdgeCount: edges.length,
      violations,
      couplingMap,
    };
  }
}

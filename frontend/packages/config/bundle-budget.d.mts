export interface CriticalJs {
  bytes: number;
  files: string[];
}
export function criticalJs(distDir: string): CriticalJs;
export function checkBudget(report: CriticalJs, limitKiB: number): { ok: boolean; message: string };

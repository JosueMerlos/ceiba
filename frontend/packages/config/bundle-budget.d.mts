export interface CriticalJs {
  bytes: number;
  files: string[];
}
export function criticalJs(distDir: string): CriticalJs;
export function checkBudget(report: CriticalJs, limitKiB: number): { ok: boolean; message: string };
export interface BudgetConfig {
  [app: string]: { dist: string; limitKiB: number };
}
export function checkBudgets(
  config: BudgetConfig,
  root: string,
): { name: string; ok: boolean; message: string }[];

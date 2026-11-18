export function parseIgnoredAdvisories(output: string): string[];
export function auditIgnoreViolations(
  workspaceYaml: string,
  ignoredAdvisories: string[],
  today: string,
): string[];

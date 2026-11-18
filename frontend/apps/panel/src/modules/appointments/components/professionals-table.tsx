import { useTranslation } from "@ceiba/i18n";
import {
  Badge,
  Button,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@ceiba/ui";
import type { Professional } from "../api/professionals";

interface ProfessionalsTableProps {
  professionals: readonly Professional[];
  /** Id -> name of the branches the user can see; an unknown id (a branch the user does not read) is not shown. */
  branchNames: ReadonlyMap<string, string>;
  selectedId: string | null;
  /** Archiving needs `appointments.professional.manage`; the caller decides. */
  canManage: boolean;
  onSelect(id: string): void;
  onArchive(professional: Professional): void;
}

export function ProfessionalsTable({
  professionals,
  branchNames,
  selectedId,
  canManage,
  onSelect,
  onArchive,
}: ProfessionalsTableProps) {
  const { t } = useTranslation("appointments");
  return (
    <Table>
      <TableHeader>
        <TableRow className="border-b">
          <TableHead>{t("catalog.professionals.columns.name")}</TableHead>
          <TableHead>{t("catalog.professionals.columns.branches")}</TableHead>
          <TableHead>{t("catalog.professionals.columns.services")}</TableHead>
          <TableHead>{t("catalog.professionals.columns.status")}</TableHead>
          {canManage ? (
            <TableHead className="text-right">
              {t("catalog.professionals.columns.actions")}
            </TableHead>
          ) : null}
        </TableRow>
      </TableHeader>
      <TableBody>
        {professionals.map((professional) => {
          const names = professional.branch_ids.flatMap((id) => branchNames.get(id) ?? []);
          return (
            <TableRow
              key={professional.id}
              aria-current={professional.id === selectedId ? "true" : undefined}
              data-state={professional.id === selectedId ? "selected" : undefined}
            >
              <TableCell className="font-medium">
                <button
                  type="button"
                  aria-label={t("catalog.professionals.selectLabel", {
                    name: professional.display_name,
                  })}
                  onClick={() => onSelect(professional.id)}
                  className="rounded-sm text-left hover:underline focus-visible:ring-3 focus-visible:ring-ring/30 focus-visible:outline-none"
                >
                  {professional.display_name}
                </button>
              </TableCell>
              <TableCell>
                {professional.branch_ids.length === 0 ? (
                  <span className="text-muted-foreground">
                    {t("catalog.professionals.noBranches")}
                  </span>
                ) : (
                  names.join(", ")
                )}
              </TableCell>
              <TableCell className="tabular-nums">
                {t("catalog.professionals.servicesCount", {
                  count: professional.service_ids.length,
                })}
              </TableCell>
              <TableCell>
                <Badge variant={professional.active ? "default" : "muted"}>
                  {t(`catalog.professionals.status.${professional.active ? "active" : "paused"}`)}
                </Badge>
              </TableCell>
              {canManage ? (
                <TableCell className="text-right">
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    aria-label={t("catalog.professionals.archiveLabel", {
                      name: professional.display_name,
                    })}
                    onClick={() => onArchive(professional)}
                  >
                    {t("catalog.professionals.archive")}
                  </Button>
                </TableCell>
              ) : null}
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}

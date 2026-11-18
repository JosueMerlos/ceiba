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
import type { Resource } from "../api/resources";

interface ResourcesTableProps {
  resources: readonly Resource[];
  selectedId: string | null;
  /** Archiving needs `appointments.resource.manage`; the caller decides. */
  canManage: boolean;
  onSelect(id: string): void;
  onArchive(resource: Resource): void;
}

export function ResourcesTable({
  resources,
  selectedId,
  canManage,
  onSelect,
  onArchive,
}: ResourcesTableProps) {
  const { t } = useTranslation("appointments");
  return (
    <Table>
      <TableHeader>
        <TableRow className="border-b">
          <TableHead>{t("catalog.resources.columns.name")}</TableHead>
          <TableHead>{t("catalog.resources.columns.kind")}</TableHead>
          <TableHead>{t("catalog.resources.columns.status")}</TableHead>
          {canManage ? (
            <TableHead className="text-right">{t("catalog.resources.columns.actions")}</TableHead>
          ) : null}
        </TableRow>
      </TableHeader>
      <TableBody>
        {resources.map((resource) => (
          <TableRow
            key={resource.id}
            aria-current={resource.id === selectedId ? "true" : undefined}
            data-state={resource.id === selectedId ? "selected" : undefined}
          >
            <TableCell className="font-medium">
              <button
                type="button"
                aria-label={t("catalog.resources.selectLabel", { name: resource.name })}
                onClick={() => onSelect(resource.id)}
                className="rounded-sm text-left hover:underline focus-visible:ring-3 focus-visible:ring-ring/30 focus-visible:outline-none"
              >
                {resource.name}
              </button>
            </TableCell>
            <TableCell>{t(`catalog.resources.kinds.${resource.kind}`)}</TableCell>
            <TableCell>
              <Badge variant={resource.active ? "default" : "muted"}>
                {t(`catalog.resources.status.${resource.active ? "active" : "paused"}`)}
              </Badge>
            </TableCell>
            {canManage ? (
              <TableCell className="text-right">
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  aria-label={t("catalog.resources.archiveLabel", { name: resource.name })}
                  onClick={() => onArchive(resource)}
                >
                  {t("catalog.resources.archive")}
                </Button>
              </TableCell>
            ) : null}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

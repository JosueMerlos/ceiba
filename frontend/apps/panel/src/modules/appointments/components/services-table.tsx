import { formatCurrency, useTranslation } from "@ceiba/i18n";
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
import type { Service } from "../api/catalog";

interface ServicesTableProps {
  services: readonly Service[];
  selectedId: string | null;
  /** Archive and restore need `appointments.service.manage`; the caller decides. */
  canManage: boolean;
  onSelect(id: string): void;
  onArchive(service: Service): void;
  onRestore(service: Service): void;
}

const statusOf = (service: Service) =>
  service.archived_at ? "archived" : service.active ? "active" : "paused";

const BADGE = { active: "default", paused: "muted", archived: "outline" } as const;

export function ServicesTable({
  services,
  selectedId,
  canManage,
  onSelect,
  onArchive,
  onRestore,
}: ServicesTableProps) {
  const { t } = useTranslation("appointments");
  return (
    <Table>
      <TableHeader>
        <TableRow className="border-b">
          <TableHead>{t("catalog.services.columns.name")}</TableHead>
          <TableHead>{t("catalog.services.columns.duration")}</TableHead>
          <TableHead>{t("catalog.services.columns.price")}</TableHead>
          <TableHead>{t("catalog.services.columns.status")}</TableHead>
          {canManage ? (
            <TableHead className="text-right">{t("catalog.services.columns.actions")}</TableHead>
          ) : null}
        </TableRow>
      </TableHeader>
      <TableBody>
        {services.map((service) => {
          const status = statusOf(service);
          return (
            <TableRow
              key={service.id}
              aria-current={service.id === selectedId ? "true" : undefined}
              data-state={service.id === selectedId ? "selected" : undefined}
            >
              <TableCell className="font-medium">
                <button
                  type="button"
                  aria-label={t("catalog.services.selectLabel", { name: service.name })}
                  onClick={() => onSelect(service.id)}
                  className="rounded-sm text-left hover:underline focus-visible:ring-3 focus-visible:ring-ring/30 focus-visible:outline-none"
                >
                  {service.name}
                </button>
              </TableCell>
              <TableCell className="tabular-nums">
                {t("catalog.services.minutes", { count: service.duration_minutes })}
              </TableCell>
              <TableCell className="tabular-nums">
                {formatCurrency(service.price_minor / 100, service.currency)}
              </TableCell>
              <TableCell>
                <Badge variant={BADGE[status]}>{t(`catalog.services.status.${status}`)}</Badge>
              </TableCell>
              {canManage ? (
                <TableCell className="text-right">
                  {status === "archived" ? (
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      aria-label={t("catalog.services.restoreLabel", { name: service.name })}
                      onClick={() => onRestore(service)}
                    >
                      {t("catalog.services.restore")}
                    </Button>
                  ) : (
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      aria-label={t("catalog.services.archiveLabel", { name: service.name })}
                      onClick={() => onArchive(service)}
                    >
                      {t("catalog.services.archive")}
                    </Button>
                  )}
                </TableCell>
              ) : null}
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}

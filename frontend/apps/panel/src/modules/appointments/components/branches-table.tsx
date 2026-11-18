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
import { Link } from "react-router";
import type { Branch } from "../api/catalog";

/** `null` while the schedule is unknown (loading, or the user cannot read it): no badge is better than a wrong one. */
export type BranchScheduleStatus = "configured" | "closed" | null;

export function BranchesTable({
  branches,
  scheduleStatuses,
}: {
  branches: readonly Branch[];
  /** One entry per branch, in the same order. */
  scheduleStatuses: readonly BranchScheduleStatus[];
}) {
  const { t } = useTranslation("appointments");
  return (
    <Table>
      <TableHeader>
        <TableRow className="border-b">
          <TableHead>{t("catalog.branches.columns.name")}</TableHead>
          <TableHead>{t("catalog.branches.columns.timeZone")}</TableHead>
          <TableHead>{t("catalog.branches.columns.schedule")}</TableHead>
          <TableHead className="text-right">
            <span className="sr-only">{t("catalog.branches.scheduleLink")}</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {branches.map((branch, index) => {
          const status = scheduleStatuses[index];
          return (
            <TableRow key={branch.id}>
              <TableCell className="font-medium">{branch.name}</TableCell>
              <TableCell className="text-muted-foreground">{branch.time_zone}</TableCell>
              <TableCell>
                {status ? (
                  <Badge variant={status === "closed" ? "muted" : undefined}>
                    {t(`catalog.branches.scheduleStatus.${status}`)}
                  </Badge>
                ) : null}
              </TableCell>
              <TableCell className="text-right">
                <Button asChild variant="outline" size="sm">
                  <Link
                    to={`/branches/${branch.id}/schedule`}
                    aria-label={t("catalog.branches.scheduleLinkLabel", { name: branch.name })}
                  >
                    {t("catalog.branches.scheduleLink")}
                  </Link>
                </Button>
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}

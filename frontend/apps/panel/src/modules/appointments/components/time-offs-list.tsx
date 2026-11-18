import { useTranslation } from "@ceiba/i18n";
import { Button } from "@ceiba/ui";
import { Trash2 } from "lucide-react";
import type { TimeOff } from "../api/professionals";
import { formatInZone } from "../lib/zoned-time";

interface TimeOffsListProps {
  timeOffs: readonly TimeOff[];
  /** IANA zone the ranges are shown in: the branch's, not the browser's. */
  timeZone: string;
  /** Removing needs `appointments.time_off.manage`; the caller decides. */
  canManage: boolean;
  onDelete(timeOff: TimeOff): void;
}

export function TimeOffsList({ timeOffs, timeZone, canManage, onDelete }: TimeOffsListProps) {
  const { t } = useTranslation("appointments");
  if (timeOffs.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("catalog.timeOffs.empty")}</p>;
  }
  return (
    <ul className="grid gap-2">
      {timeOffs.map((timeOff) => {
        const start = formatInZone(timeOff.starts_at, timeZone);
        return (
          <li
            key={timeOff.id}
            className="flex items-start justify-between gap-3 rounded-lg border bg-card px-3.5 py-2.5"
          >
            <div className="grid gap-0.5 text-sm">
              <p className="font-medium tabular-nums">
                {t("catalog.timeOffs.range", {
                  start,
                  end: formatInZone(timeOff.ends_at, timeZone),
                })}
              </p>
              {timeOff.reason ? <p className="text-muted-foreground">{timeOff.reason}</p> : null}
            </div>
            {canManage ? (
              <Button
                type="button"
                variant="ghost"
                size="icon"
                aria-label={t("catalog.timeOffs.removeLabel", { start })}
                onClick={() => onDelete(timeOff)}
              >
                <Trash2 aria-hidden="true" />
              </Button>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

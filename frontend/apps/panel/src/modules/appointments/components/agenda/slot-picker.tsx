import { formatTime, useTranslation } from "@ceiba/i18n";
import { Button, Label, LoadingState } from "@ceiba/ui";

interface SlotPickerProps {
  starts: readonly string[];
  value: string | null;
  onChange(startsAt: string): void;
  timeZone: string;
  isLoading: boolean;
  failed: boolean;
  /** Shown instead of the times when the choice cannot be made yet. */
  hint?: string;
}

/** The free start times of one day, in the branch's zone. */
export function SlotPicker({
  starts,
  value,
  onChange,
  timeZone,
  isLoading,
  failed,
  hint,
}: SlotPickerProps) {
  const { t } = useTranslation(["appointments", "common"]);
  let content;
  if (hint) content = <p className="text-sm text-muted-foreground">{hint}</p>;
  else if (isLoading) content = <LoadingState label={t("common:loading")} />;
  else if (failed)
    content = <p className="text-sm text-destructive">{t("agenda.form.slotsFailed")}</p>;
  else if (starts.length === 0)
    content = <p className="text-sm text-muted-foreground">{t("agenda.form.noSlots")}</p>;
  else
    content = (
      <div className="grid max-h-48 grid-cols-3 gap-1.5 overflow-y-auto">
        {starts.map((start) => (
          <Button
            key={start}
            type="button"
            size="sm"
            variant={start === value ? "default" : "outline"}
            aria-pressed={start === value}
            onClick={() => onChange(start)}
          >
            {formatTime(start, timeZone)}
          </Button>
        ))}
      </div>
    );
  return (
    <div className="grid gap-1.5">
      <Label asChild>
        <span>{t("agenda.form.time")}</span>
      </Label>
      {content}
    </div>
  );
}

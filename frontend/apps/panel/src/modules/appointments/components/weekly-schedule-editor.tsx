import type { components } from "@ceiba/api-client";
import { formatClock, useTranslation } from "@ceiba/i18n";
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Input,
} from "@ceiba/ui";
import { Plus, Trash2 } from "lucide-react";
import { useRef, useState } from "react";
import {
  toDrafts,
  toPayload,
  validateSlots,
  WEEK_ORDER,
  type SchedulePayload,
  type SlotDraft,
  type SlotProblem,
} from "../lib/schedule";

interface WeeklyScheduleEditorProps {
  slots: readonly components["schemas"]["WeeklyScheduleSlot"][];
  onSave(payload: SchedulePayload): void;
  readOnly?: boolean;
  saving?: boolean;
  /**
   * Turn off the overlap and range checks so the request goes out and the server decides. Only for cases the client
   * cannot see (hours in other branches) and for tests that prove the 422 is displayed.
   */
  validateClient?: boolean;
  /** Already user-facing messages from a failed save (the 422 on `slots`). */
  serverMessages?: readonly string[];
}

const DEFAULT_START = "09:00";
const DEFAULT_LENGTH_MINUTES = 240;
const LAST_MINUTE = 23 * 60 + 59;

const toMinutes = (hhmm: string) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));
const toHHMM = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;

/** Weekly hours as a list of slots per weekday, in the branch's local time. Saving sends the whole week at once. */
export function WeeklyScheduleEditor({
  slots,
  onSave,
  readOnly = false,
  saving = false,
  validateClient = true,
  serverMessages = [],
}: WeeklyScheduleEditorProps) {
  const { t } = useTranslation(["appointments", "common"]);
  const [drafts, setDrafts] = useState<SlotDraft[]>(() => toDrafts(slots));
  const [attempted, setAttempted] = useState(false);
  const [confirmingClosed, setConfirmingClosed] = useState(false);
  const nextKey = useRef(0);

  const problems = validateClient ? validateSlots(drafts) : new Map<string, SlotProblem>();

  const update = (key: string, change: Partial<SlotDraft>) =>
    setDrafts((current) =>
      current.map((slot) => (slot.key === key ? { ...slot, ...change } : slot)),
    );

  function addSlot(weekday: number) {
    setDrafts((current) => {
      const ends = current
        .filter((slot) => slot.weekday === weekday && /^\d{2}:\d{2}$/.test(slot.end))
        .map((slot) => toMinutes(slot.end));
      const start = ends.length > 0 ? Math.max(...ends) : toMinutes(DEFAULT_START);
      const end = Math.min(start + DEFAULT_LENGTH_MINUTES, LAST_MINUTE);
      nextKey.current += 1;
      return [
        ...current,
        { key: `new-${nextKey.current}`, weekday, start: toHHMM(start), end: toHHMM(end) },
      ];
    });
  }

  function save() {
    setAttempted(true);
    if (problems.size > 0) return;
    if (drafts.length === 0) return setConfirmingClosed(true);
    onSave(toPayload(drafts));
  }

  return (
    <div className="grid gap-4">
      <div className="grid gap-2">
        {WEEK_ORDER.map((weekday) => {
          const daySlots = drafts.filter((slot) => slot.weekday === weekday);
          const label = t(`catalog.schedule.days.${weekday}`);
          return (
            <div
              key={weekday}
              role="group"
              aria-label={label}
              className="grid gap-2 rounded-xl border bg-card px-4 py-3 sm:grid-cols-[7rem_minmax(0,1fr)] sm:items-start"
            >
              <p className="pt-2 text-sm font-semibold">{label}</p>
              <div className="grid min-w-0 gap-2">
                {daySlots.length === 0 ? (
                  <p className="pt-2 text-sm text-muted-foreground">
                    {t("catalog.schedule.closedDay")}
                  </p>
                ) : null}
                {daySlots.map((slot) => {
                  const problem = attempted ? problems.get(slot.key) : undefined;
                  return readOnly ? (
                    <p key={slot.key} className="pt-2 text-sm tabular-nums">
                      {t("catalog.schedule.slotRange", {
                        start: formatClock(slot.start),
                        end: formatClock(slot.end),
                      })}
                    </p>
                  ) : (
                    <div key={slot.key} className="grid min-w-0 gap-1">
                      <div className="flex min-w-0 items-center gap-2">
                        <Input
                          type="time"
                          aria-label={t("catalog.schedule.start")}
                          aria-invalid={problem ? true : undefined}
                          value={slot.start}
                          onChange={(event) => update(slot.key, { start: event.target.value })}
                          className="min-w-0 flex-1 sm:w-32 sm:flex-none"
                        />
                        <span aria-hidden="true" className="text-muted-foreground">
                          –
                        </span>
                        <Input
                          type="time"
                          aria-label={t("catalog.schedule.end")}
                          aria-invalid={problem ? true : undefined}
                          value={slot.end}
                          onChange={(event) => update(slot.key, { end: event.target.value })}
                          className="min-w-0 flex-1 sm:w-32 sm:flex-none"
                        />
                        <Button
                          type="button"
                          variant="ghost"
                          size="icon"
                          aria-label={t("catalog.schedule.removeSlot")}
                          onClick={() =>
                            setDrafts((current) => current.filter((item) => item.key !== slot.key))
                          }
                        >
                          <Trash2 aria-hidden="true" />
                        </Button>
                      </div>
                      {problem ? (
                        <p role="alert" className="text-sm font-medium text-destructive">
                          {t(`catalog.schedule.errors.${problem}`)}
                        </p>
                      ) : null}
                    </div>
                  );
                })}
                {readOnly ? null : (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="w-fit text-muted-foreground"
                    onClick={() => addSlot(weekday)}
                  >
                    <Plus aria-hidden="true" />
                    {t("catalog.schedule.addSlot")}
                  </Button>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {serverMessages.length > 0 ? (
        <div
          role="alert"
          className="grid gap-1 rounded-lg border border-destructive/30 bg-destructive/5 px-3.5 py-2.5 text-sm font-medium text-destructive"
        >
          {serverMessages.map((message) => (
            <p key={message}>{t("catalog.schedule.errors.server", { message })}</p>
          ))}
        </div>
      ) : null}

      {readOnly ? null : (
        <div>
          <Button type="button" loading={saving} onClick={save}>
            {t("catalog.schedule.save")}
          </Button>
        </div>
      )}

      <Dialog open={confirmingClosed} onOpenChange={setConfirmingClosed}>
        <DialogContent closeLabel={t("common:close")}>
          <DialogHeader>
            <DialogTitle>{t("catalog.schedule.closeConfirm.title")}</DialogTitle>
            <DialogDescription>{t("catalog.schedule.closeConfirm.description")}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setConfirmingClosed(false)}>
              {t("common:cancel")}
            </Button>
            <Button
              type="button"
              onClick={() => {
                setConfirmingClosed(false);
                onSave(toPayload([]));
              }}
            >
              {t("catalog.schedule.closeConfirm.confirm")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

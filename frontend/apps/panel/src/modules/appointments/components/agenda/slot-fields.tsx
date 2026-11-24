import { formatPlainDate, useTranslation } from "@ceiba/i18n";
import {
  DatePicker,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ceiba/ui";
import { useId, useMemo, useState } from "react";
import { useFreeSlots } from "../../api/agenda-availability";
import type { AgendaProfessional } from "../../api/agenda";
import { todayInZone, type PlainDate } from "../../lib/agenda-time";
import { SlotPicker } from "./slot-picker";

interface SlotSelectionOptions {
  branchId: string;
  serviceIds: readonly string[];
  initial: { professionalId: string | null; day: PlainDate; startsAt?: string | null };
}

/** Who, which day and at what time: changing the person or the day discards the chosen time. */
export function useSlotSelection({ branchId, serviceIds, initial }: SlotSelectionOptions) {
  const [professionalId, setProfessionalId] = useState(initial.professionalId);
  const [day, setDay] = useState(initial.day);
  const [wanted, setWanted] = useState(initial.startsAt ?? null);
  const availability = useFreeSlots({ branchId, serviceIds, professionalId, date: day });
  const free = availability.data?.data;

  // Only what the engine offers: a start over the appointment itself, outside hours or over another booking is not free.
  const starts = useMemo(() => (free ?? []).map((slot) => slot.starts_at), [free]);

  const startsAt = starts.find((start) => Date.parse(start) === Date.parse(wanted ?? "")) ?? null;
  return {
    professionalId,
    day,
    starts,
    startsAt,
    availability,
    freeSlot: free?.find((slot) => Date.parse(slot.starts_at) === Date.parse(wanted ?? "")),
    choose: setWanted,
    changeProfessional(next: string) {
      setProfessionalId(next);
      setWanted(null);
    },
    changeDay(next: string) {
      if (next) setDay(next);
      setWanted(null);
    },
  };
}

export type SlotSelection = ReturnType<typeof useSlotSelection>;

export function ProfessionalField({
  selection,
  professionals,
  onChange,
}: {
  selection: SlotSelection;
  professionals: readonly AgendaProfessional[];
  onChange?(id: string): void;
}) {
  const { t } = useTranslation("appointments");
  const id = useId();
  return (
    <div className="grid gap-1.5">
      <Label htmlFor={id}>{t("agenda.form.professional")}</Label>
      <Select
        value={selection.professionalId ?? undefined}
        onValueChange={(value) => {
          selection.changeProfessional(value);
          onChange?.(value);
        }}
      >
        <SelectTrigger id={id}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {professionals.map((person) => (
            <SelectItem key={person.id} value={person.id}>
              {person.display_name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}

export function DayAndTimeFields({
  selection,
  timeZone,
  dayLabel,
  hint,
}: {
  selection: SlotSelection;
  timeZone: string;
  dayLabel: string;
  hint?: string;
}) {
  const { t } = useTranslation("common");
  const id = useId();
  return (
    <>
      <div className="grid gap-1.5">
        <Label htmlFor={id}>{dayLabel}</Label>
        <DatePicker
          id={id}
          value={selection.day}
          onChange={selection.changeDay}
          today={todayInZone(timeZone)}
          formatDate={formatPlainDate}
          placeholder={t("fields.pickDate")}
          calendarLabel={t("fields.calendar")}
          previousMonthLabel={t("fields.previousMonth")}
          nextMonthLabel={t("fields.nextMonth")}
        />
      </div>
      <SlotPicker
        starts={selection.starts}
        value={selection.startsAt}
        onChange={selection.choose}
        timeZone={timeZone}
        isLoading={selection.availability.isPending}
        failed={selection.availability.isError}
        hint={hint}
      />
    </>
  );
}

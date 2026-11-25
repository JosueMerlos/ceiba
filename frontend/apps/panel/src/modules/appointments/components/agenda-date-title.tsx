import { useTranslation } from "@ceiba/i18n";
import { DatePicker } from "@ceiba/ui";
import type { PlainDate } from "../lib/agenda-time";

// The date is a calendar day, so it is formatted in UTC: no zone may move it to the neighboring day.
const dayFormat = new Intl.DateTimeFormat("es-NI", {
  weekday: "long",
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});
const longDay = (day: PlainDate) => dayFormat.format(new Date(`${day}T12:00:00Z`)).replace(",", "");

interface AgendaDateTitleProps {
  date: PlainDate;
  /** Today in the branch's zone. */
  today: PlainDate;
  onChange(day: PlainDate): void;
}

/**
 * The day's title, which is also the button that opens the calendar. Screen readers hear "Agenda del …"; the screen
 * shows only the date.
 */
export function AgendaDateTitle({ date, today, onChange }: AgendaDateTitleProps) {
  const { t } = useTranslation(["appointments", "common"]);
  return (
    <>
      <span className="sr-only">{t("agenda.dayTitlePrefix")} </span>
      <DatePicker
        value={date}
        onChange={(day) => {
          if (day) onChange(day);
        }}
        today={today}
        formatDate={longDay}
        placeholder={t("common:fields.pickDate")}
        calendarLabel={t("common:fields.calendar")}
        previousMonthLabel={t("common:fields.previousMonth")}
        nextMonthLabel={t("common:fields.nextMonth")}
        loadErrorLabel={t("common:fields.calendarError")}
        retryLabel={t("common:retry")}
        className="-ml-2 h-auto w-auto max-w-full gap-2 border-0 bg-transparent px-2 py-0.5 font-display text-[length:inherit] font-[inherit] shadow-none hover:bg-muted md:text-[length:inherit] [&>span]:overflow-visible [&>span]:first-letter:uppercase [&>svg]:size-5"
      />
    </>
  );
}

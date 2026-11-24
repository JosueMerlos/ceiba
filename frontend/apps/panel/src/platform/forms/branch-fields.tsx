import { formatClock, formatPlainDate, useTranslation } from "@ceiba/i18n";
import {
  DatePicker,
  TimeField,
  TimeRangeField,
  type DatePickerProps,
  type TimeFieldProps,
  type TimeRangeFieldProps,
} from "@ceiba/ui";

// The panel's date and time fields with their texts and formats bound once: callers pass only value, labels and zone.

type BoundDateProps =
  | "today"
  | "formatDate"
  | "placeholder"
  | "calendarLabel"
  | "previousMonthLabel"
  | "nextMonthLabel"
  | "loadErrorLabel"
  | "retryLabel";

/** Today in the branch's zone, "yyyy-MM-dd" (en-CA writes ISO dates). */
const todayIn = (timeZone: string) =>
  new Intl.DateTimeFormat("en-CA", { timeZone }).format(new Date());

export function BranchDatePicker({
  timeZone,
  ...props
}: Omit<DatePickerProps, BoundDateProps> & { timeZone: string }) {
  const { t } = useTranslation("common");
  return (
    <DatePicker
      {...props}
      today={todayIn(timeZone)}
      formatDate={formatPlainDate}
      placeholder={t("fields.pickDate")}
      calendarLabel={t("fields.calendar")}
      previousMonthLabel={t("fields.previousMonth")}
      nextMonthLabel={t("fields.nextMonth")}
      loadErrorLabel={t("fields.calendarError")}
      retryLabel={t("retry")}
    />
  );
}

export function BranchTimeField(props: Omit<TimeFieldProps, "formatClock" | "listLabel">) {
  const { t } = useTranslation("common");
  return <TimeField {...props} formatClock={formatClock} listLabel={t("fields.timeList")} />;
}

export function BranchTimeRangeField(
  props: Omit<TimeRangeFieldProps, "formatClock" | "listLabel">,
) {
  const { t } = useTranslation("common");
  return <TimeRangeField {...props} formatClock={formatClock} listLabel={t("fields.timeList")} />;
}

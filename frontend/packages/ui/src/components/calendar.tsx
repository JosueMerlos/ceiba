import { DayPicker, type DateRange as DayRange } from "react-day-picker";
import { es } from "react-day-picker/locale";
import { cn } from "../lib/cn";

/** A calendar day, "2026-12-14". */
type PlainDate = string;

// Calendar days travel as local noon: no browser zone (UTC-12..UTC+14) can move noon to another day.
const toDate = (day: PlainDate) => {
  const [year = 1970, month = 1, date = 1] = day.split("-").map(Number);
  return new Date(year, month - 1, date, 12);
};
const pad = (value: number) => String(value).padStart(2, "0");
const toPlainDate = (date: Date): PlainDate =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

interface CalendarProps {
  mode: "single" | "range";
  /** single: one day; range: start and end (end may be missing). */
  from: PlainDate | null;
  to?: PlainDate | null;
  today: PlainDate;
  min?: PlainDate;
  max?: PlainDate;
  previousMonthLabel: string;
  nextMonthLabel: string;
  onPick(day: PlainDate): void;
}

const CLASS_NAMES = {
  root: "relative w-fit",
  months: "grid",
  month: "grid gap-2",
  nav: "absolute inset-x-0 top-0 flex items-center justify-between",
  button_previous:
    "grid size-8 place-items-center rounded-lg text-muted-foreground hover:bg-accent hover:text-accent-foreground focus-visible:outline-2 focus-visible:outline-ring disabled:opacity-40 [&_svg]:size-4 [&_svg]:fill-current",
  button_next:
    "grid size-8 place-items-center rounded-lg text-muted-foreground hover:bg-accent hover:text-accent-foreground focus-visible:outline-2 focus-visible:outline-ring disabled:opacity-40 [&_svg]:size-4 [&_svg]:fill-current",
  month_caption: "flex h-8 items-center justify-center",
  caption_label: "font-display text-sm font-semibold capitalize",
  month_grid: "border-collapse",
  weekdays: "",
  weekday: "size-9 text-xs font-medium text-muted-foreground",
  week: "",
  day: "size-9 p-0 text-center text-sm tabular-nums",
  day_button:
    "size-9 rounded-lg transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-ring",
  today: "[&>button]:font-bold [&>button]:ring-1 [&>button]:ring-primary [&>button]:ring-inset",
  selected:
    "[&>button]:bg-primary [&>button]:font-semibold [&>button]:text-primary-foreground [&>button]:hover:bg-primary/90",
  range_start: "",
  range_end: "",
  range_middle:
    "bg-accent [&>button]:rounded-none [&>button]:bg-transparent [&>button]:font-normal [&>button]:text-accent-foreground",
  outside: "text-muted-foreground/50",
  disabled: "pointer-events-none opacity-40",
  hidden: "invisible",
};

/** The month grid (react-day-picker). Loaded on demand: never import it from the package's entry. */
export default function Calendar({
  mode,
  from,
  to = null,
  today,
  min,
  max,
  previousMonthLabel,
  nextMonthLabel,
  onPick,
}: CalendarProps) {
  const disabled = [
    ...(min ? [{ before: toDate(min) }] : []),
    ...(max ? [{ after: toDate(max) }] : []),
  ];
  const shared = {
    locale: es,
    weekStartsOn: 1 as const,
    showOutsideDays: true,
    autoFocus: true,
    today: toDate(today),
    defaultMonth: toDate(from ?? today),
    startMonth: min ? toDate(min) : undefined,
    endMonth: max ? toDate(max) : undefined,
    disabled,
    labels: {
      labelPrevious: () => previousMonthLabel,
      labelNext: () => nextMonthLabel,
    },
    classNames: CLASS_NAMES,
    className: cn("text-popover-foreground"),
  };

  if (mode === "range") {
    const selected: DayRange | undefined = from
      ? { from: toDate(from), to: to ? toDate(to) : undefined }
      : undefined;
    return (
      <DayPicker
        {...shared}
        mode="range"
        selected={selected}
        onSelect={(_range, triggerDate) => onPick(toPlainDate(triggerDate))}
      />
    );
  }
  return (
    <DayPicker
      {...shared}
      mode="single"
      required
      selected={from ? toDate(from) : undefined}
      onSelect={(_day, triggerDate) => onPick(toPlainDate(triggerDate))}
    />
  );
}

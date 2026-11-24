import { CalendarDays } from "lucide-react";
import { Popover as PopoverPrimitive } from "radix-ui";
import { Component, lazy, Suspense, useId, useState, type ReactNode, type Ref } from "react";
import { cn } from "../lib/cn";
import { usePortalContainer } from "../lib/portal-container";
import { Button } from "./button";

// The calendar library only downloads when a calendar opens; the field itself stays in the caller's chunk.
// React.lazy remembers a failed import, so retrying needs a fresh lazy component.
const loadCalendar = () => lazy(() => import("./calendar"));
const calendar = { Component: loadCalendar() };

interface BoundaryProps {
  errorLabel: string;
  retryLabel: string;
  children: ReactNode;
}

/** Keeps a failed calendar download (a deploy replaced the chunk, the network dropped) inside the popover. */
class CalendarBoundary extends Component<BoundaryProps, { failed: boolean }> {
  override state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  retry = () => {
    calendar.Component = loadCalendar();
    this.setState({ failed: false });
  };

  override render() {
    if (!this.state.failed) return this.props.children;
    return (
      <div role="alert" className="grid w-[17rem] gap-3 p-2 text-sm">
        <p>{this.props.errorLabel}</p>
        <Button type="button" variant="outline" size="sm" onClick={this.retry}>
          {this.props.retryLabel}
        </Button>
      </div>
    );
  }
}

/** A range of calendar days; `to` is null while only the start is chosen. */
interface DateRange {
  from: string | null;
  to: string | null;
}

interface DateFieldBaseProps {
  /** Today in the branch's zone ("yyyy-MM-dd"); the app computes it, never the browser. */
  today: string;
  /** How a "yyyy-MM-dd" reads in the panel ("lun 14 dic 2026"); the app passes the one from its i18n package. */
  formatDate(day: string): string;
  placeholder: string;
  calendarLabel: string;
  previousMonthLabel: string;
  nextMonthLabel: string;
  /** Shown in the popover when the calendar cannot be downloaded. */
  loadErrorLabel: string;
  retryLabel: string;
  min?: string;
  max?: string;
  disabled?: boolean;
  id?: string;
  "aria-label"?: string;
  "aria-labelledby"?: string;
  "aria-describedby"?: string;
  "aria-invalid"?: boolean | "true" | "false";
  className?: string;
  ref?: Ref<HTMLButtonElement>;
}

interface DatePickerProps extends DateFieldBaseProps {
  /** "yyyy-MM-dd"; "" when empty. */
  value: string;
  onChange(day: string): void;
}

interface DateRangePickerProps extends DateFieldBaseProps {
  value: DateRange;
  onChange(range: DateRange): void;
}

/** First click starts, second click ends; a second click before the start becomes the new start. */
function nextRange({ from, to }: DateRange, day: string): DateRange {
  if (!from || to || day < from) return { from: day, to: null };
  return { from, to: day };
}

interface ShellProps extends DateFieldBaseProps {
  mode: "single" | "range";
  from: string | null;
  to?: string | null;
  text: ReactNode;
  /** Receives the clicked day; returns whether the pick is complete, which closes the calendar. */
  onPick(day: string): boolean;
}

function DateFieldShell({
  mode,
  from,
  to,
  text,
  onPick,
  today,
  min,
  max,
  previousMonthLabel,
  nextMonthLabel,
  loadErrorLabel,
  retryLabel,
  calendarLabel,
  placeholder,
  disabled,
  id,
  className,
  ref,
  "aria-describedby": describedBy,
  "aria-invalid": ariaInvalid,
  "aria-label": ariaLabel,
  "aria-labelledby": labelledBy,
}: ShellProps) {
  const [open, setOpen] = useState(false);
  const portalContainer = usePortalContainer();
  const fallbackId = useId();
  const triggerId = id ?? fallbackId;
  const valueId = `${triggerId}-value`;
  const empty = !from;
  return (
    <PopoverPrimitive.Root open={open} onOpenChange={setOpen}>
      <PopoverPrimitive.Trigger asChild>
        <button
          ref={ref}
          id={triggerId}
          type="button"
          disabled={disabled}
          aria-label={ariaLabel}
          aria-labelledby={labelledBy}
          aria-describedby={[valueId, describedBy].filter(Boolean).join(" ")}
          aria-invalid={ariaInvalid || undefined}
          data-slot="date-field"
          className={cn(
            "flex h-(--input-height) w-full min-w-0 items-center gap-2 rounded-(--input-radius) border border-(--input-border) bg-card px-3 text-left text-base shadow-xs transition-colors outline-none md:text-sm",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/30",
            "aria-invalid:border-destructive aria-invalid:ring-destructive/20",
            className,
          )}
        >
          <CalendarDays aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
          <span
            id={valueId}
            className={cn("min-w-0 flex-1 truncate tabular-nums", empty && "text-muted-foreground")}
          >
            {empty ? placeholder : text}
          </span>
        </button>
      </PopoverPrimitive.Trigger>
      <PopoverPrimitive.Portal container={portalContainer}>
        <PopoverPrimitive.Content
          aria-label={calendarLabel}
          align="start"
          sideOffset={6}
          data-slot="date-field-calendar"
          className="z-50 rounded-xl border bg-popover p-3 text-popover-foreground shadow-lg outline-none"
        >
          <CalendarBoundary errorLabel={loadErrorLabel} retryLabel={retryLabel}>
            <Suspense fallback={<div aria-busy="true" className="h-72 w-[17rem]" />}>
              <calendar.Component
                mode={mode}
                from={from}
                to={to}
                today={today}
                min={min}
                max={max}
                previousMonthLabel={previousMonthLabel}
                nextMonthLabel={nextMonthLabel}
                onPick={(day) => {
                  if (onPick(day)) setOpen(false);
                }}
              />
            </Suspense>
          </CalendarBoundary>
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  );
}

/** A calendar day picked from a month grid. Value and output are "yyyy-MM-dd", never a browser Date. */
function DatePicker({ value, onChange, ...props }: DatePickerProps) {
  return (
    <DateFieldShell
      {...props}
      mode="single"
      from={value || null}
      text={value ? props.formatDate(value) : null}
      onPick={(day) => {
        if (day !== value) onChange(day);
        return true;
      }}
    />
  );
}

/** A range of calendar days in one month grid: first click start, second click end. */
function DateRangePicker({ value, onChange, ...props }: DateRangePickerProps) {
  const text = value.from ? (
    <>
      {props.formatDate(value.from)}
      {value.to ? (
        <>
          <span aria-hidden="true"> – </span>
          {props.formatDate(value.to)}
        </>
      ) : null}
    </>
  ) : null;
  return (
    <DateFieldShell
      {...props}
      mode="range"
      from={value.from}
      to={value.to}
      text={text}
      onPick={(day) => {
        const range = nextRange(value, day);
        onChange(range);
        return range.to !== null;
      }}
    />
  );
}

export { DatePicker, DateRangePicker };
export type { DatePickerProps, DateRange, DateRangePickerProps };

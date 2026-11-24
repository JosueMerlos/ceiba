import { cn } from "../lib/cn";
import { TimeField, type TimeFieldProps } from "./time-field";

/** Two branch wall-clock times, "HH:mm". */
interface TimeRange {
  start: string;
  end: string;
}

interface TimeRangeFieldProps extends Pick<
  TimeFieldProps,
  "formatClock" | "listLabel" | "min" | "max" | "step" | "disabled"
> {
  value: TimeRange;
  onChange(range: TimeRange): void;
  startLabel: string;
  endLabel: string;
  "aria-label"?: string;
  "aria-labelledby"?: string;
  "aria-invalid"?: boolean | "true" | "false";
  /** The row's error, announced on both times. */
  "aria-describedby"?: string;
  className?: string;
  /** Width of each of the two times, e.g. responsive widths of a schedule row. */
  fieldClassName?: string;
}

/**
 * Compact "from – to" pill for schedule rows. It does not reorder an inverted range: the form validates it and says
 * why, which is clearer than silently swapping the hours.
 */
function TimeRangeField({
  value,
  onChange,
  startLabel,
  endLabel,
  className,
  fieldClassName = "w-36",
  "aria-invalid": ariaInvalid,
  "aria-label": ariaLabel,
  "aria-labelledby": labelledBy,
  ...field
}: TimeRangeFieldProps) {
  return (
    <div
      // Without a name of its own it is just layout: the surrounding group (a weekday) already names it.
      role={ariaLabel || labelledBy ? "group" : undefined}
      aria-label={ariaLabel}
      aria-labelledby={labelledBy}
      data-slot="time-range-field"
      className={cn("flex min-w-0 items-center gap-1.5", className)}
    >
      <TimeField
        {...field}
        aria-label={startLabel}
        aria-invalid={ariaInvalid}
        value={value.start}
        onChange={(start) => onChange({ ...value, start })}
        className={fieldClassName}
      />
      <span aria-hidden="true" className="text-muted-foreground">
        –
      </span>
      <TimeField
        {...field}
        aria-label={endLabel}
        aria-invalid={ariaInvalid}
        value={value.end}
        onChange={(end) => onChange({ ...value, end })}
        className={fieldClassName}
      />
    </div>
  );
}

export { TimeRangeField };
export type { TimeRange, TimeRangeFieldProps };

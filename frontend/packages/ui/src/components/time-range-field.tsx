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
  className?: string;
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
  "aria-invalid": ariaInvalid,
  "aria-label": ariaLabel,
  "aria-labelledby": labelledBy,
  ...field
}: TimeRangeFieldProps) {
  return (
    <div
      role="group"
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
        className="w-36"
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
        className="w-36"
      />
    </div>
  );
}

export { TimeRangeField };
export type { TimeRange, TimeRangeFieldProps };

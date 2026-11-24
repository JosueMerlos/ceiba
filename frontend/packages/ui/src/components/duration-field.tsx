import { Minus, Plus } from "lucide-react";
import type { Ref } from "react";
import { cn } from "../lib/cn";

interface DurationFieldProps {
  /** Minutes. */
  value: number;
  onChange(minutes: number): void;
  /** "45 min", "1 h 30 min": the app passes the formatter from its i18n package. */
  formatDuration(minutes: number): string;
  decreaseLabel: string;
  increaseLabel: string;
  presetsLabel: string;
  min?: number;
  max?: number;
  step?: number;
  presets?: readonly number[];
  disabled?: boolean;
  id?: string;
  "aria-label"?: string;
  "aria-labelledby"?: string;
  "aria-describedby"?: string;
  "aria-invalid"?: boolean | "true" | "false";
  className?: string;
  ref?: Ref<HTMLDivElement>;
}

const DEFAULT_PRESETS = [15, 30, 45, 60, 90] as const;

/** Duration without typing minutes: −/+ by `step` and one-tap shortcuts. Never leaves [min, max]. */
function DurationField({
  value,
  onChange,
  formatDuration,
  decreaseLabel,
  increaseLabel,
  presetsLabel,
  min = 5,
  max = 480,
  step = 5,
  presets = DEFAULT_PRESETS,
  disabled,
  className,
  ref,
  "aria-invalid": ariaInvalid,
  ...aria
}: DurationFieldProps) {
  const change = (minutes: number) => {
    const next = Math.min(max, Math.max(min, minutes));
    if (next !== value) onChange(next);
  };
  const stepper =
    "grid size-9 place-items-center rounded-full text-foreground transition-colors hover:bg-accent focus-visible:outline-2 focus-visible:outline-ring disabled:pointer-events-none disabled:opacity-40 [&_svg]:size-4";

  return (
    <div
      ref={ref}
      role="group"
      data-slot="duration-field"
      aria-invalid={ariaInvalid || undefined}
      className={cn("flex flex-wrap items-center gap-3", className)}
      {...aria}
    >
      <div className="flex h-(--input-height) items-center gap-1 rounded-full border border-(--input-border) bg-card px-1 shadow-xs">
        <button
          type="button"
          className={stepper}
          aria-label={decreaseLabel}
          disabled={disabled || value <= min}
          onClick={() => change(value - step)}
        >
          <Minus aria-hidden="true" />
        </button>
        <output
          role="status"
          className="min-w-20 text-center text-sm font-semibold tabular-nums"
          aria-live="polite"
        >
          {formatDuration(value)}
        </output>
        <button
          type="button"
          className={stepper}
          aria-label={increaseLabel}
          disabled={disabled || value >= max}
          onClick={() => change(value + step)}
        >
          <Plus aria-hidden="true" />
        </button>
      </div>
      <div role="group" aria-label={presetsLabel} className="flex flex-wrap gap-1.5">
        {presets
          .filter((minutes) => minutes >= min && minutes <= max)
          .map((minutes) => {
            const pressed = minutes === value;
            return (
              <button
                key={minutes}
                type="button"
                aria-pressed={pressed}
                disabled={disabled}
                onClick={() => change(minutes)}
                className={cn(
                  "h-8 rounded-full border px-3 text-sm font-semibold tabular-nums transition-colors focus-visible:outline-2 focus-visible:outline-ring disabled:opacity-50",
                  pressed
                    ? "border-foreground bg-foreground text-background"
                    : "border-border bg-card text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                )}
              >
                {formatDuration(minutes)}
              </button>
            );
          })}
      </div>
    </div>
  );
}

export { DurationField };
export type { DurationFieldProps };

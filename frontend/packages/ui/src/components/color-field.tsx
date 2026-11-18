import type { ComponentProps } from "react";
import { cn } from "../lib/cn";
import { Input } from "./input";

const HEX = /^#[0-9a-fA-F]{6}$/;

interface ColorFieldProps extends Omit<ComponentProps<"input">, "type" | "value" | "onChange"> {
  value: string;
  onValueChange: (value: string) => void;
  /** Accessible name of the native picker (the hex field is named by the surrounding label). */
  pickerLabel: string;
}

/**
 * A color as a hex text field plus the native picker. The text field is the source of truth (it accepts partial input
 * while typing); the picker only mirrors it when it holds a complete #RRGGBB. Props such as `id` and `aria-*` go to
 * the text field, so it composes with `FormControl`.
 */
function ColorField({
  value,
  onValueChange,
  pickerLabel,
  className,
  disabled,
  ...props
}: ColorFieldProps) {
  const valid = HEX.test(value);
  return (
    <div data-slot="color-field" className={cn("flex items-center gap-2", className)}>
      <input
        type="color"
        aria-label={pickerLabel}
        value={valid ? value.toLowerCase() : "#000000"}
        disabled={disabled}
        onChange={(event) => onValueChange(event.target.value.toUpperCase())}
        className={cn(
          "size-(--input-height) shrink-0 cursor-pointer rounded-(--input-radius) border border-(--input-border) bg-card p-1 disabled:cursor-not-allowed disabled:opacity-50",
          !valid && "opacity-40",
        )}
      />
      <Input
        {...props}
        value={value}
        disabled={disabled}
        onChange={(event) => onValueChange(event.target.value)}
        maxLength={7}
        spellCheck={false}
        autoCapitalize="characters"
        autoComplete="off"
        className="font-mono tracking-wide"
      />
    </div>
  );
}

export { ColorField };
export type { ColorFieldProps };

import { Toggle as TogglePrimitive } from "radix-ui";
import { createContext, useContext, type ComponentProps } from "react";
import { cn } from "../lib/cn";

interface ToggleGroupState {
  value: string;
  onValueChange(value: string): void;
}

const ToggleGroupContext = createContext<ToggleGroupState | null>(null);

type ToggleGroupProps = Omit<ComponentProps<"div">, "onChange"> & ToggleGroupState;

/**
 * Chip-style single-choice filter. Each chip is a button with `aria-pressed` (Radix's single ToggleGroup exposes radio
 * semantics instead). Pressing the active chip keeps it selected: a filter always has exactly one value.
 */
function ToggleGroup({ value, onValueChange, className, ...props }: ToggleGroupProps) {
  return (
    <ToggleGroupContext.Provider value={{ value, onValueChange }}>
      <div
        role="group"
        data-slot="toggle-group"
        className={cn("flex flex-wrap gap-1.5", className)}
        {...props}
      />
    </ToggleGroupContext.Provider>
  );
}

function ToggleGroupItem({
  value,
  className,
  ...props
}: Omit<ComponentProps<typeof TogglePrimitive.Root>, "pressed" | "onPressedChange" | "value"> & {
  value: string;
}) {
  const group = useContext(ToggleGroupContext);
  if (!group) throw new Error("ToggleGroupItem debe usarse dentro de <ToggleGroup>");
  return (
    <TogglePrimitive.Root
      data-slot="toggle-group-item"
      pressed={group.value === value}
      onPressedChange={() => {
        if (group.value !== value) group.onValueChange(value);
      }}
      className={cn(
        "inline-flex h-8 items-center gap-1.5 rounded-full border bg-card px-3.5 text-sm font-semibold text-muted-foreground transition-colors outline-none",
        "hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/30 disabled:pointer-events-none disabled:opacity-50",
        "data-[state=on]:border-foreground data-[state=on]:bg-foreground data-[state=on]:text-background",
        className,
      )}
      {...props}
    />
  );
}

export { ToggleGroup, ToggleGroupItem };

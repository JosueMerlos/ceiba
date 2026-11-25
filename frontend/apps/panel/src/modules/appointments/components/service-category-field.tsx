import { Input, cn } from "@ceiba/ui";
import { useId, useState, type ComponentProps, type KeyboardEvent, type Ref } from "react";

interface ServiceCategoryFieldProps extends Omit<
  ComponentProps<"input">,
  "value" | "onChange" | "ref" | "role"
> {
  value: string;
  onChange(value: string): void;
  /** Categories already in use; the list shows the ones containing what is typed. */
  suggestions: readonly string[];
  listLabel: string;
  ref?: Ref<HTMLInputElement>;
}

const normalize = (text: string) => text.trim().toLocaleLowerCase("es");

/**
 * Free text with the categories already in use offered underneath, so the same category is not typed two ways. A
 * styled listbox instead of a native <datalist>, which browsers draw (and filter) each in their own way.
 */
export function ServiceCategoryField({
  value,
  onChange,
  suggestions,
  listLabel,
  onBlur,
  onFocus,
  className,
  ref,
  ...props
}: ServiceCategoryFieldProps) {
  const listId = useId();
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);

  const typed = normalize(value);
  const matches = suggestions.filter((item) => {
    const candidate = normalize(item);
    return candidate.includes(typed) && candidate !== typed;
  });
  const showing = open && matches.length > 0;
  const optionId = (index: number) => `${listId}-${index}`;

  function choose(category: string) {
    onChange(category);
    setOpen(false);
    setActive(-1);
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!showing) return setOpen(true);
      const step = event.key === "ArrowDown" ? 1 : -1;
      setActive((current) => (current + step + matches.length) % matches.length);
    } else if (event.key === "Enter" && showing && active >= 0) {
      // Picking a suggestion must not submit the form.
      event.preventDefault();
      choose(matches[active]!);
    } else if (event.key === "Escape" && showing) {
      setOpen(false);
      setActive(-1);
    }
  }

  return (
    <div className="relative">
      <Input
        {...props}
        ref={ref}
        role="combobox"
        aria-autocomplete="list"
        aria-expanded={showing}
        aria-controls={showing ? listId : undefined}
        aria-activedescendant={showing && active >= 0 ? optionId(active) : undefined}
        // While the list is open Escape closes it, not the modal around the field.
        data-editing={showing ? "" : undefined}
        autoComplete="off"
        value={value}
        className={className}
        onChange={(event) => {
          onChange(event.target.value);
          setOpen(true);
          setActive(-1);
        }}
        onFocus={(event) => {
          setOpen(true);
          onFocus?.(event);
        }}
        onBlur={(event) => {
          setOpen(false);
          setActive(-1);
          onBlur?.(event);
        }}
        onKeyDown={onKeyDown}
      />
      {showing ? (
        <ul
          id={listId}
          role="listbox"
          aria-label={listLabel}
          className="absolute inset-x-0 top-full z-10 mt-1 grid max-h-48 gap-0.5 overflow-y-auto rounded-xl border bg-popover p-1 text-popover-foreground shadow-md"
        >
          {matches.map((category, index) => (
            <li
              key={category}
              id={optionId(index)}
              role="option"
              aria-selected={index === active}
              // Keeps the focus in the input, so choosing does not blur (and close) first.
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => choose(category)}
              className={cn(
                "cursor-pointer rounded-lg px-3 py-2 text-sm",
                index === active ? "bg-accent text-accent-foreground" : "hover:bg-muted",
              )}
            >
              {category}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

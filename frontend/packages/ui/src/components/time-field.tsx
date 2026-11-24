import { Check, Clock } from "lucide-react";
import { Popover as PopoverPrimitive } from "radix-ui";
import { flushSync } from "react-dom";
import {
  useEffect,
  useEffectEvent,
  useId,
  useMemo,
  useState,
  type ComponentProps,
  type KeyboardEvent,
  type Ref,
} from "react";
import { clockOptions, clockToMinutes, parseClock } from "../lib/clock";
import { cn } from "../lib/cn";
import { usePortalContainer } from "../lib/portal-container";

const optionIdOf = (inputId: string, clock: string) => `${inputId}-${clock.replace(":", "")}`;

interface TimeFieldProps extends Pick<
  ComponentProps<"input">,
  "id" | "name" | "disabled" | "aria-label" | "aria-describedby" | "aria-labelledby"
> {
  /** Branch wall-clock time, "HH:mm"; "" when empty. */
  value: string;
  onChange(value: string): void;
  onBlur?(): void;
  /** How a "HH:mm" reads in the panel ("9:00 a. m."); the app passes the one from its i18n package. */
  formatClock(clock: string): string;
  /** Accessible name of the list of times. */
  listLabel: string;
  min?: string;
  max?: string;
  /** Minutes between the listed times; anything in range can still be typed. */
  step?: number;
  "aria-invalid"?: boolean | "true" | "false";
  className?: string;
  ref?: Ref<HTMLInputElement>;
}

/**
 * Time input: type it ("9", "930p", "2:15 p. m.") or pick it from a list every `step` minutes. Implements the
 * WAI-ARIA combobox: arrows move the active option, Enter or leaving the field commits. Invalid or out-of-range text
 * stays on screen, marked, and empties the value so the form's validation blocks the save; Escape restores the time
 * there was before typing.
 */
function TimeField({
  value,
  onChange,
  onBlur,
  formatClock,
  listLabel,
  min = "00:00",
  max = "23:59",
  step = 15,
  id,
  className,
  disabled,
  ref,
  "aria-invalid": ariaInvalid,
  ...aria
}: TimeFieldProps) {
  const fallbackId = useId();
  const inputId = id ?? fallbackId;
  const listId = `${inputId}-list`;
  const options = useMemo(() => clockOptions(min, max, step), [min, max, step]);
  const [draft, setDraft] = useState<string | null>(null);
  const [invalid, setInvalid] = useState(false);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  // The last value this field emitted: any other change of `value` comes from outside (a form reset) and drops the draft.
  const [emitted, setEmitted] = useState<string | null>(null);
  const [synced, setSynced] = useState(value);
  // The value when typing started: what Escape goes back to.
  const [beforeDraft, setBeforeDraft] = useState(value);
  const portalContainer = usePortalContainer();

  if (value !== synced) {
    setSynced(value);
    if (value !== emitted) {
      setDraft(null);
      setInvalid(false);
    }
    // Only the echo of the latest emission is ours; a later equal value comes from outside.
    setEmitted(null);
  }
  // The list can shrink (a new min/max) while an option far down is active.
  const activeOption = open && active >= 0 ? options[active] : undefined;

  const optionId = (clock: string) => optionIdOf(inputId, clock);
  // The current value, or the first listed time after it when it falls between steps.
  const anchorIndex = () => {
    if (!value) return -1;
    const minutes = clockToMinutes(value);
    return options.findIndex((option) => clockToMinutes(option) >= minutes);
  };

  useEffect(() => {
    if (!activeOption) return;
    document
      .getElementById(optionIdOf(inputId, activeOption))
      ?.scrollIntoView({ block: "nearest" });
  }, [activeOption, inputId]);

  function emit(next: string) {
    setEmitted(next);
    onChange(next);
  }

  function choose(clock: string) {
    setDraft(null);
    setInvalid(false);
    setOpen(false);
    if (clock !== value) emit(clock);
  }

  function commitDraft() {
    if (draft === null) return;
    if (draft.trim() === "") {
      setDraft(null);
      setInvalid(false);
      if (value !== "") emit("");
      return;
    }
    const clock = parseClock(draft);
    const inRange =
      clock !== null &&
      clockToMinutes(clock) >= clockToMinutes(min) &&
      clockToMinutes(clock) <= clockToMinutes(max);
    if (!inRange) {
      // The text stays on screen to be fixed, but the form must not keep the previous time while the field shows
      // something else: an empty value fails its validation and blocks the save.
      setInvalid(true);
      if (value !== "") emit("");
      return;
    }
    choose(clock);
  }

  // A click elsewhere commits what is typed BEFORE anything reacts to that click (a modal deciding whether it may
  // close without asking checks its dirty state on the same pointerdown, earlier than this input's blur).
  const commitOnOutsidePointer = useEffectEvent((event: PointerEvent) => {
    const target = event.target;
    if (!(target instanceof Node)) return;
    const field = document.getElementById(inputId)?.parentElement;
    if (field?.contains(target) || document.getElementById(listId)?.contains(target)) return;
    flushSync(commitDraft);
  });
  const editing = draft !== null;
  useEffect(() => {
    if (!editing) return;
    document.addEventListener("pointerdown", commitOnOutsidePointer, true);
    return () => document.removeEventListener("pointerdown", commitOnOutsidePointer, true);
  }, [editing]);

  function openAt(index: number) {
    setOpen(true);
    setActive(Math.max(0, Math.min(options.length - 1, index)));
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp": {
        event.preventDefault();
        const delta = event.key === "ArrowDown" ? 1 : -1;
        if (activeOption) {
          openAt(active + delta);
        } else {
          // Clamped by openAt: with no value (-1) either arrow lands on the first option.
          openAt(anchorIndex() + delta);
        }
        break;
      }
      case "Enter":
        if (activeOption) {
          event.preventDefault();
          choose(activeOption);
        } else if (draft !== null) {
          event.preventDefault();
          commitDraft();
        }
        break;
      case "Escape":
        // Closes the list first, then cancels what was typed; a dialog around the field must stay open meanwhile.
        if (open) {
          event.preventDefault();
          event.stopPropagation();
          setOpen(false);
        } else if (draft !== null) {
          event.preventDefault();
          event.stopPropagation();
          setDraft(null);
          setInvalid(false);
          if (value !== beforeDraft) emit(beforeDraft);
        }
        break;
    }
  }

  const shown = draft ?? (value ? formatClock(value) : "");
  const markedInvalid = invalid || ariaInvalid === true || ariaInvalid === "true";

  return (
    <PopoverPrimitive.Root open={open} onOpenChange={setOpen}>
      <PopoverPrimitive.Anchor asChild>
        <div data-slot="time-field" className={cn("relative min-w-0", className)}>
          <Clock
            aria-hidden="true"
            className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
          />
          <input
            ref={ref}
            id={inputId}
            type="text"
            autoComplete="off"
            role="combobox"
            aria-autocomplete="none"
            aria-expanded={open}
            aria-controls={listId}
            aria-activedescendant={activeOption ? optionId(activeOption) : undefined}
            data-editing={editing || undefined}
            aria-invalid={markedInvalid || undefined}
            disabled={disabled}
            value={shown}
            onChange={(event) => {
              if (draft === null) setBeforeDraft(value);
              setDraft(event.target.value);
              setInvalid(false);
              // What is typed wins over the highlighted option until the arrows are used again.
              setActive(-1);
            }}
            onClick={() => {
              if (!open) openAt(anchorIndex());
            }}
            onKeyDown={onKeyDown}
            onBlur={() => {
              commitDraft();
              setOpen(false);
              onBlur?.();
            }}
            className={cn(
              "flex h-(--input-height) w-full min-w-0 rounded-(--input-radius) border border-(--input-border) bg-card pr-3 pl-9 text-base tabular-nums shadow-xs transition-colors outline-none md:text-sm",
              "disabled:cursor-not-allowed disabled:opacity-50",
              "focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/30",
              "aria-invalid:border-destructive aria-invalid:ring-destructive/20",
            )}
            {...aria}
          />
        </div>
      </PopoverPrimitive.Anchor>
      <PopoverPrimitive.Portal container={portalContainer}>
        <PopoverPrimitive.Content
          asChild
          align="start"
          sideOffset={6}
          onOpenAutoFocus={(event) => event.preventDefault()}
          onCloseAutoFocus={(event) => event.preventDefault()}
          onInteractOutside={(event) => {
            if (event.target === document.getElementById(inputId)) event.preventDefault();
          }}
        >
          <ul
            id={listId}
            role="listbox"
            aria-label={listLabel}
            data-slot="time-field-list"
            className="z-50 grid max-h-64 w-(--radix-popover-trigger-width) min-w-40 gap-0.5 overflow-y-auto rounded-xl border bg-popover p-1.5 text-popover-foreground shadow-lg outline-none"
          >
            {options.map((clock, index) => {
              const selected = clock === value;
              return (
                <li
                  key={clock}
                  id={optionId(clock)}
                  role="option"
                  aria-selected={selected}
                  data-active={index === active || undefined}
                  // Keeps focus in the input, so its blur does not commit the typed text first.
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => choose(clock)}
                  className={cn(
                    "flex h-8 cursor-pointer items-center justify-between gap-3 rounded-lg px-2.5 text-sm tabular-nums",
                    "data-active:bg-accent data-active:text-accent-foreground",
                    selected && "font-semibold text-primary",
                  )}
                >
                  {formatClock(clock)}
                  <Check
                    aria-hidden="true"
                    className={cn("size-4", selected ? "visible" : "invisible")}
                  />
                </li>
              );
            })}
          </ul>
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  );
}

export { TimeField };
export type { TimeFieldProps };

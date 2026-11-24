import { X } from "lucide-react";
import { useEffect, type KeyboardEvent, type ReactNode } from "react";
import { cn } from "../lib/cn";
import { Button } from "./button";

interface ContextPanelProps {
  /** Also the target of the close button's `aria-controls`. */
  id: string;
  open: boolean;
  onOpenChange(open: boolean): void;
  title: ReactNode;
  /** Accessible text of the close button (already translated by the app). */
  closeLabel: string;
  /** Pinned under the content, e.g. save / discard. */
  footer?: ReactNode;
  /** `floating` (default) overlays the sheet without taking its width; `docked` is a column beside it from `lg`. */
  variant?: "floating" | "docked";
  className?: string;
  children: ReactNode;
}

/**
 * Non-modal side panel for the context of the current screen (upcoming arrivals, an appointment's detail). It never
 * traps focus and leaves the sheet usable. Pass it to `AppLayout` as `aside`: it floats over the sheet's right edge so
 * the screen keeps its width; `docked` is for editors that need to see the screen and the panel side by side.
 * Closing returns focus to whatever opened it.
 */
function ContextPanel({
  id,
  open,
  onOpenChange,
  title,
  closeLabel,
  footer,
  variant = "floating",
  className,
  children,
}: ContextPanelProps) {
  const titleId = `${id}-title`;

  useEffect(() => {
    if (!open) return;
    // Runs after the click that opened the panel, so the opener still holds focus.
    const active = document.activeElement;
    const opener = active instanceof HTMLElement && active !== document.body ? active : null;
    // The cleanup also runs on unmount: callers usually drop the panel instead of passing `open={false}`.
    return () => {
      if (opener?.isConnected) opener.focus();
    };
  }, [open]);

  if (!open) return null;

  function onKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.key === "Escape" && !event.defaultPrevented) {
      event.stopPropagation();
      onOpenChange(false);
    }
  }

  return (
    <aside
      id={id}
      aria-labelledby={titleId}
      data-slot="context-panel"
      data-variant={variant}
      onKeyDown={onKeyDown}
      className={cn(
        "z-40 flex flex-col rounded-2xl border bg-background",
        variant === "floating"
          ? "absolute inset-y-2 right-2 w-[min(22rem,calc(100%-1rem))] shadow-lg"
          : [
              "fixed inset-y-2 right-2 w-[min(22rem,calc(100vw-1rem))] shadow-lg",
              "lg:static lg:inset-y-auto lg:right-auto lg:z-auto lg:h-full lg:w-80 lg:shrink-0 lg:shadow-none",
            ],
        className,
      )}
    >
      <div className="flex items-center gap-2 px-5 pt-5">
        <h2 id={titleId} className="min-w-0 flex-1 truncate font-display text-lg font-semibold">
          {title}
        </h2>
        <Button
          variant="ghost"
          size="icon"
          className="size-8 bg-sidebar"
          aria-label={closeLabel}
          aria-expanded="true"
          aria-controls={id}
          onClick={() => onOpenChange(false)}
        >
          <X aria-hidden="true" />
        </Button>
      </div>
      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">{children}</div>
      {footer ? <div className="flex gap-2 border-t px-5 py-4">{footer}</div> : null}
    </aside>
  );
}

export { ContextPanel };
export type { ContextPanelProps };

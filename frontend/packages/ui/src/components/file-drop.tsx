import { ImageIcon } from "lucide-react";
import type { ChangeEvent, ComponentProps } from "react";
import { cn } from "../lib/cn";
import { Button, buttonVariants } from "./button";

interface FileDropProps extends Pick<
  ComponentProps<"input">,
  "id" | "accept" | "disabled" | "aria-describedby" | "aria-invalid"
> {
  /** URL of what is currently chosen or saved (an object URL or a stored image); null = nothing. */
  previewUrl: string | null;
  previewAlt: string;
  chooseLabel: string;
  replaceLabel: string;
  removeLabel: string;
  emptyLabel: string;
  onSelect: (file: File) => void;
  onRemove: () => void;
  className?: string;
}

/**
 * Image chooser with a thumbnail. The native file input stays in the tab order (visually hidden) and the visible
 * label shows its focus, so it works by keyboard without a custom widget.
 */
function FileDrop({
  previewUrl,
  previewAlt,
  chooseLabel,
  replaceLabel,
  removeLabel,
  emptyLabel,
  onSelect,
  onRemove,
  className,
  disabled,
  ...inputProps
}: FileDropProps) {
  const handleChange = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    // Cleared so choosing the same file again (e.g. after removing it) still fires a change.
    event.target.value = "";
    if (file) onSelect(file);
  };

  return (
    <div
      data-slot="file-drop"
      className={cn(
        "flex items-center gap-3 rounded-lg border border-dashed bg-card p-3",
        className,
      )}
    >
      <div className="grid size-16 shrink-0 place-items-center overflow-hidden rounded-md border bg-muted text-muted-foreground">
        {previewUrl ? (
          <img src={previewUrl} alt={previewAlt} className="size-full object-contain" />
        ) : (
          <>
            <ImageIcon className="size-5" aria-hidden="true" />
            <span className="sr-only">{emptyLabel}</span>
          </>
        )}
      </div>
      <div className="flex min-w-0 flex-wrap items-center gap-2">
        <label
          className={cn(
            buttonVariants({ variant: "outline", size: "sm" }),
            "cursor-pointer has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-ring",
            disabled && "pointer-events-none opacity-50",
          )}
        >
          <input
            {...inputProps}
            type="file"
            disabled={disabled}
            onChange={handleChange}
            className="sr-only"
          />
          {previewUrl ? replaceLabel : chooseLabel}
        </label>
        {previewUrl ? (
          <Button type="button" variant="ghost" size="sm" disabled={disabled} onClick={onRemove}>
            {removeLabel}
          </Button>
        ) : null}
      </div>
    </div>
  );
}

export { FileDrop };
export type { FileDropProps };

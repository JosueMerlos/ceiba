import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
  RailTooltip,
} from "@ceiba/ui";
import { ChevronsUpDown } from "lucide-react";
import { Fragment } from "react";
import { initials } from "../shell/initials";

export interface ContextOption {
  value: string;
  label: string;
  disabled?: boolean;
}

export interface ContextLevel {
  key: "organization" | "company" | "branch";
  label: string;
  /** Chosen value ("" = none, e.g. "all branches"). */
  value: string;
  options: ContextOption[];
}

interface ContextMenuProps {
  triggerLabel: string;
  /** Company name: the monogram and the main line of the trigger. */
  summary: string;
  /** Branch name, under the company; omitted when the user works across all branches. */
  detail?: string;
  levels: ContextLevel[];
  onSelect(level: ContextLevel["key"], value: string): void;
}

/**
 * Context selector (organization -> company -> branch). Shows only levels with more than one option and hides entirely
 * when there is nothing to choose.
 */
export function ContextMenu({ triggerLabel, summary, detail, levels, onSelect }: ContextMenuProps) {
  const choosable = levels.filter((level) => level.options.length > 1);
  if (choosable.length === 0) return null;

  return (
    <DropdownMenu>
      <RailTooltip label={[summary, detail].filter(Boolean).join(" · ")}>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            className="flex w-full min-w-0 items-center gap-2.5 rounded-xl border bg-card p-1.5 text-left text-sm transition-colors outline-none hover:bg-sidebar-accent focus-visible:ring-3 focus-visible:ring-ring/30 max-sm:w-auto md:group-data-[collapsed=true]/frame:mx-auto md:group-data-[collapsed=true]/frame:w-auto"
          >
            <span
              aria-hidden="true"
              className="grid size-8 shrink-0 place-items-center rounded-lg bg-accent text-xs font-bold text-accent-foreground"
            >
              {initials(summary)}
            </span>
            <span className="sr-only">{triggerLabel}: </span>
            {/* Below sm and in the rail only the monogram shows; the accessible name keeps the company. */}
            <span className="grid min-w-0 flex-1 leading-tight max-sm:sr-only md:group-data-[collapsed=true]/frame:sr-only">
              <span className="truncate font-semibold">{summary}</span>
              {detail ? (
                <span className="truncate text-xs text-muted-foreground">{detail}</span>
              ) : null}
            </span>
            <ChevronsUpDown
              className="mr-1 size-3.5 shrink-0 text-muted-foreground max-sm:hidden md:group-data-[collapsed=true]/frame:hidden"
              aria-hidden="true"
            />
          </button>
        </DropdownMenuTrigger>
      </RailTooltip>
      <DropdownMenuContent align="start" className="w-72">
        {choosable.map((level, index) => (
          <Fragment key={level.key}>
            {index > 0 ? <DropdownMenuSeparator /> : null}
            <DropdownMenuLabel>{level.label}</DropdownMenuLabel>
            <DropdownMenuRadioGroup
              value={level.value}
              onValueChange={(value) => onSelect(level.key, value)}
            >
              {level.options.map((option) => (
                <DropdownMenuRadioItem
                  key={option.value}
                  value={option.value}
                  disabled={option.disabled}
                >
                  {option.label}
                </DropdownMenuRadioItem>
              ))}
            </DropdownMenuRadioGroup>
          </Fragment>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

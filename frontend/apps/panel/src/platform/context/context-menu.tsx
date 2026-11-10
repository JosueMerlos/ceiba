import {
  Button,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@ceiba/ui";
import { Building2, ChevronsUpDown } from "lucide-react";
import { Fragment } from "react";

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
  summary: string;
  levels: ContextLevel[];
  onSelect(level: ContextLevel["key"], value: string): void;
}

/**
 * Context selector (organization -> company -> branch). Shows only levels with more than one option and hides entirely
 * when there is nothing to choose.
 */
export function ContextMenu({ triggerLabel, summary, levels, onSelect }: ContextMenuProps) {
  const choosable = levels.filter((level) => level.options.length > 1);
  if (choosable.length === 0) return null;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          className="min-w-0 shrink justify-between gap-2 max-sm:px-2.5 md:max-w-xs"
        >
          <Building2 className="text-muted-foreground" aria-hidden="true" />
          <span className="sr-only">{triggerLabel}: </span>
          {/* Below sm only the icon shows; the accessible name keeps the company. */}
          <span className="truncate max-sm:sr-only">{summary}</span>
          <ChevronsUpDown className="text-muted-foreground" aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-72">
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

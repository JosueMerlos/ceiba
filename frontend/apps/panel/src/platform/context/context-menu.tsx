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
  /** Valor elegido ("" = ninguno, p. ej. «todas las sucursales»). */
  value: string;
  options: ContextOption[];
}

interface ContextMenuProps {
  triggerLabel: string;
  /** Resumen visible de dónde se trabaja (empresa y sucursal). */
  summary: string;
  levels: ContextLevel[];
  onSelect(level: ContextLevel["key"], value: string): void;
}

/**
 * Selector de contexto (organización -> empresa -> sucursal). Solo muestra los niveles con más de una opción y se
 * oculta por completo cuando no hay nada que elegir (criterio 1 de M0.12).
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
          {/* Bajo sm solo se ve el icono; el nombre accesible conserva la empresa. */}
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

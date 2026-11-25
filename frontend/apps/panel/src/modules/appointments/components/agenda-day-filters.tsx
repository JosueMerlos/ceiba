import { useTranslation } from "@ceiba/i18n";
import { ToggleGroup, ToggleGroupItem } from "@ceiba/ui";
import { Rows2, Rows4 } from "lucide-react";
import type { useStatusFilter } from "../lib/use-status-filter";
import { AgendaStatusChips } from "./agenda-status-chips";
import type { AgendaDensity } from "./agenda-view/types";

const DENSITY_ITEM =
  "size-8 justify-center rounded-[calc(var(--button-radius)-2px)] border-0 bg-transparent p-0 text-muted-foreground data-[state=on]:bg-background data-[state=on]:text-foreground data-[state=on]:shadow-xs [&_svg]:size-4";

interface AgendaDayFiltersProps {
  filter: ReturnType<typeof useStatusFilter>;
  /** Null hides the density choice (a phone draws a list, where it means nothing). */
  density: AgendaDensity | null;
  onDensityChange(density: AgendaDensity): void;
}

/** The day's second row: the status chips and, on a wide screen, the density. */
export function AgendaDayFilters({ filter, density, onDensityChange }: AgendaDayFiltersProps) {
  const { t } = useTranslation("appointments");
  return (
    <div className="-mt-2 mb-3 flex flex-wrap items-center gap-2">
      <AgendaStatusChips
        counts={filter.counts}
        hidden={filter.hidden}
        onToggle={filter.toggle}
        onShowAll={filter.showAll}
        className="max-md:w-full max-md:flex-nowrap max-md:overflow-x-auto max-md:[scrollbar-width:none]"
      />
      {density ? (
        <ToggleGroup
          value={density}
          onValueChange={(value) => {
            if (value === "comfortable" || value === "compact") onDensityChange(value);
          }}
          aria-label={t("agenda.density.label")}
          className="ml-auto flex-nowrap gap-0.5 rounded-[var(--button-radius)] bg-sidebar p-0.5"
        >
          <ToggleGroupItem
            value="comfortable"
            aria-label={t("agenda.density.comfortable")}
            title={t("agenda.density.comfortable")}
            className={DENSITY_ITEM}
          >
            <Rows2 aria-hidden="true" />
          </ToggleGroupItem>
          <ToggleGroupItem
            value="compact"
            aria-label={t("agenda.density.compact")}
            title={t("agenda.density.compact")}
            className={DENSITY_ITEM}
          >
            <Rows4 aria-hidden="true" />
          </ToggleGroupItem>
        </ToggleGroup>
      ) : null}
    </div>
  );
}

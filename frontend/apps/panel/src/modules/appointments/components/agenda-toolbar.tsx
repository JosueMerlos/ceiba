import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  ToggleGroup,
  ToggleGroupItem,
} from "@ceiba/ui";
import { ChevronLeft, ChevronRight, Clock, Plus } from "lucide-react";
import { AGENDA_MODES, type AgendaMode } from "../lib/agenda-lens";

interface AgendaToolbarProps {
  mode: AgendaMode;
  onModeChange(mode: AgendaMode): void;
  canViewResources: boolean;
  onPrevious(): void;
  onToday(): void;
  onNext(): void;
  arrivalsCount: number;
  arrivalsOpen: boolean;
  onToggleArrivals(): void;
  arrivalsPanelId: string;
  onNewAppointment?(): void;
}

export function AgendaToolbar({
  mode,
  onModeChange,
  canViewResources,
  onPrevious,
  onToday,
  onNext,
  arrivalsCount,
  arrivalsOpen,
  onToggleArrivals,
  arrivalsPanelId,
  onNewAppointment,
}: AgendaToolbarProps) {
  const { t } = useTranslation("appointments");
  const isWeek = mode === "week";
  return (
    <div className="flex flex-wrap items-center gap-2">
      <ToggleGroup
        value={mode}
        aria-label={t("agenda.viewLabel")}
        onValueChange={(value) => {
          const next = AGENDA_MODES.find((item) => item === value);
          if (next) onModeChange(next);
        }}
      >
        <ToggleGroupItem value="professionals">{t("agenda.viewProfessionals")}</ToggleGroupItem>
        {canViewResources ? (
          <ToggleGroupItem value="resources">{t("agenda.viewResources")}</ToggleGroupItem>
        ) : null}
        <ToggleGroupItem value="week">{t("agenda.viewWeek")}</ToggleGroupItem>
      </ToggleGroup>

      <div className="flex items-center rounded-[var(--button-radius)] bg-sidebar p-0.5">
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="size-9"
          aria-label={t(isWeek ? "agenda.previousWeek" : "agenda.previousDay")}
          onClick={onPrevious}
        >
          <ChevronLeft aria-hidden="true" />
        </Button>
        <Button type="button" variant="ghost" size="sm" onClick={onToday}>
          {t("agenda.today")}
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="size-9"
          aria-label={t(isWeek ? "agenda.nextWeek" : "agenda.nextDay")}
          onClick={onNext}
        >
          <ChevronRight aria-hidden="true" />
        </Button>
      </div>

      <Button
        type="button"
        variant="outline"
        aria-expanded={arrivalsOpen}
        aria-controls={arrivalsPanelId}
        onClick={onToggleArrivals}
      >
        <Clock aria-hidden="true" />
        {t("agenda.upcoming.title")}
        <span className="grid h-5 min-w-5 place-items-center rounded-full bg-primary px-1.5 text-xs font-bold text-primary-foreground">
          {arrivalsCount}
        </span>
      </Button>

      {onNewAppointment ? (
        <Button type="button" onClick={onNewAppointment}>
          <Plus aria-hidden="true" />
          {t("agenda.newAppointment")}
        </Button>
      ) : null}
    </div>
  );
}

interface WeekProfessionalPickerProps {
  professionals: readonly { id: string; display_name: string }[];
  value: string | null;
  onChange(id: string): void;
}

/** The week shows one person at a time: seven days of everyone would not read. */
export function WeekProfessionalPicker({
  professionals,
  value,
  onChange,
}: WeekProfessionalPickerProps) {
  const { t } = useTranslation("appointments");
  return (
    <Select value={value ?? undefined} onValueChange={onChange}>
      <SelectTrigger className="w-60 rounded-full" aria-label={t("agenda.weekProfessional")}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {professionals.map((person) => (
          <SelectItem key={person.id} value={person.id}>
            {person.display_name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

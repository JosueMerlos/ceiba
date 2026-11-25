import { formatCurrency, formatDuration, useTranslation } from "@ceiba/i18n";
import { Button, Checkbox, cn, Input } from "@ceiba/ui";
import { ChevronRight, Search } from "lucide-react";
import { useEffect, useId, useMemo, useState, type FormEvent } from "react";
import type { Service } from "../api/catalog";
import { describeError } from "../../../platform/errors/global-errors";
import { FormAlert } from "./form-alert";

interface ServicePickerProps {
  /** The form has no button: the modal's footer submits it through `form={id}`. */
  id: string;
  /** Services that can be given (the whole active catalog, every page). */
  services: readonly Service[];
  selectedIds: readonly string[];
  /** Receives the COMPLETE set: the API replaces what the professional provides. */
  onSubmit(serviceIds: string[]): Promise<unknown>;
  onDirtyChange?(dirty: boolean): void;
}

interface Group {
  key: string;
  label: string;
  services: Service[];
}

// Uncategorized services go last, whatever their label sorts as.
const NO_CATEGORY = "";

const fold = (text: string) =>
  text
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();

/**
 * The services a professional provides, grouped by category: each group folds, counts what is chosen and selects or
 * clears all of it at once. The whole catalog is on one scrolling list, with the search pinned above it.
 */
export function ServicePicker({
  id,
  services,
  selectedIds,
  onSubmit,
  onDirtyChange,
}: ServicePickerProps) {
  const { t } = useTranslation(["appointments", "errors"]);
  const [selected, setSelected] = useState<string[]>(() => [...selectedIds]);
  const [query, setQuery] = useState("");
  const [onlySelected, setOnlySelected] = useState(false);
  const [collapsed, setCollapsed] = useState<ReadonlySet<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const chosen = useMemo(() => new Set(selected), [selected]);

  const [baseline, setBaseline] = useState(() => [...selectedIds].sort().join(","));
  const dirty = [...selected].sort().join(",") !== baseline;
  useEffect(() => onDirtyChange?.(dirty), [dirty, onDirtyChange]);

  const groups = useMemo(() => {
    const byKey = new Map<string, Service[]>();
    for (const service of services) {
      const key = service.category ?? NO_CATEGORY;
      byKey.set(key, [...(byKey.get(key) ?? []), service]);
    }
    return [...byKey.entries()]
      .sort(([a], [b]) =>
        a === NO_CATEGORY ? 1 : b === NO_CATEGORY ? -1 : a.localeCompare(b, "es"),
      )
      .map<Group>(([key, list]) => ({
        key,
        label: key === NO_CATEGORY ? t("catalog.services.detail.noCategory") : key,
        services: list,
      }));
  }, [services, t]);

  if (services.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">{t("catalog.professionalServices.empty")}</p>
    );
  }

  const needle = fold(query.trim());
  const visible = groups
    .map((group) => ({
      ...group,
      shown: group.services.filter(
        (service) =>
          (!onlySelected || chosen.has(service.id)) &&
          (!needle || fold(service.name).includes(needle)),
      ),
    }))
    .filter((group) => group.shown.length > 0);
  const isOpen = (key: string) => onlySelected || needle !== "" || !collapsed.has(key);
  const anyOpen = visible.some((group) => isOpen(group.key));

  const setMany = (ids: readonly string[], on: boolean) =>
    setSelected((current) =>
      on
        ? [...current, ...ids.filter((item) => !current.includes(item))]
        : current.filter((item) => !ids.includes(item)),
    );

  function toggleGroup(key: string) {
    setCollapsed((current) => {
      const next = new Set(current);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  function toggleAll() {
    setOnlySelected(false);
    setCollapsed(anyOpen ? new Set(groups.map((group) => group.key)) : new Set());
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      await onSubmit(selected);
      setBaseline([...selected].sort().join(","));
    } catch (failure) {
      setError(describeError(failure, t));
    }
  }

  return (
    <form id={id} onSubmit={(event) => void submit(event)} noValidate className="grid gap-3">
      {/* Pinned to the top of the modal's scrolling body: the search stays at hand on a long catalog. */}
      <div className="sticky -top-5 z-10 -mx-6 -mt-5 flex flex-wrap items-center gap-2 border-b bg-popover px-6 py-3">
        <label className="relative min-w-48 flex-1">
          <Search
            aria-hidden="true"
            className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
          />
          <Input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            aria-label={t("catalog.professionalServices.search")}
            placeholder={t("catalog.professionalServices.search")}
            className="pl-9"
          />
        </label>
        <Button
          type="button"
          size="sm"
          variant={onlySelected ? "default" : "outline"}
          aria-pressed={onlySelected}
          className="rounded-full"
          onClick={() => setOnlySelected((current) => !current)}
        >
          {t("catalog.professionalServices.onlySelected", { count: selected.length })}
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={toggleAll}>
          {anyOpen
            ? t("catalog.professionalServices.collapseAll")
            : t("catalog.professionalServices.expandAll")}
        </Button>
      </div>

      {visible.map((group) => (
        <ServiceGroup
          key={group.key}
          group={group}
          shown={group.shown}
          chosen={chosen}
          open={isOpen(group.key)}
          onToggleOpen={() => toggleGroup(group.key)}
          onSetMany={setMany}
        />
      ))}

      {visible.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted-foreground">
          {onlySelected && !needle
            ? t("catalog.professionalServices.noneSelected")
            : t("catalog.professionalServices.noMatches")}
        </p>
      ) : null}

      <FormAlert>{error}</FormAlert>
    </form>
  );
}

function ServiceGroup({
  group,
  shown,
  chosen,
  open,
  onToggleOpen,
  onSetMany,
}: {
  group: Group;
  shown: readonly Service[];
  chosen: ReadonlySet<string>;
  open: boolean;
  onToggleOpen(): void;
  onSetMany(ids: readonly string[], on: boolean): void;
}) {
  const { t } = useTranslation("appointments");
  const listId = useId();
  const ids = group.services.map((service) => service.id);
  const count = ids.filter((item) => chosen.has(item)).length;
  const allOn = count === ids.length;

  return (
    <div role="group" aria-label={group.label} className="rounded-xl border">
      <div className="flex items-center gap-2 px-3 py-2">
        <button
          type="button"
          aria-expanded={open}
          aria-controls={listId}
          onClick={onToggleOpen}
          className="flex min-w-0 flex-1 items-center gap-2 rounded-sm text-left text-sm font-semibold focus-visible:outline-2 focus-visible:outline-ring"
        >
          <ChevronRight
            aria-hidden="true"
            className={cn("size-4 shrink-0 transition-transform", open && "rotate-90")}
          />
          <span className="truncate">{group.label}</span>
          <span
            className={cn(
              "shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold tabular-nums",
              count > 0 ? "bg-primary/10 text-foreground" : "bg-muted text-muted-foreground",
            )}
          >
            {t("catalog.professionalServices.groupCount", { selected: count, total: ids.length })}
          </span>
        </button>
        <Button type="button" size="sm" variant="ghost" onClick={() => onSetMany(ids, !allOn)}>
          {allOn
            ? t("catalog.professionalServices.removeAll")
            : t("catalog.professionalServices.selectAll")}
        </Button>
      </div>
      {open ? (
        <ul id={listId} className="grid gap-1.5 border-t p-3 sm:grid-cols-2">
          {shown.map((service) => (
            <ServiceOption
              key={service.id}
              service={service}
              checked={chosen.has(service.id)}
              onChange={(on) => onSetMany([service.id], on)}
            />
          ))}
        </ul>
      ) : null}
    </div>
  );
}

function ServiceOption({
  service,
  checked,
  onChange,
}: {
  service: Service;
  checked: boolean;
  onChange(on: boolean): void;
}) {
  const id = useId();
  const nameId = useId();
  return (
    <li
      className={cn(
        "flex min-w-0 items-center gap-2.5 rounded-lg border px-2.5 py-2 transition-colors",
        checked ? "border-primary/40 bg-primary/5" : "bg-card",
      )}
    >
      <Checkbox
        id={id}
        aria-labelledby={nameId}
        checked={checked}
        onCheckedChange={(next) => onChange(next === true)}
      />
      <label htmlFor={id} className="grid min-w-0 flex-1 cursor-pointer">
        <span id={nameId} className="truncate text-sm font-medium">
          {service.name}
        </span>
        <span className="truncate text-xs text-muted-foreground tabular-nums">
          {formatDuration(service.duration_minutes)} ·{" "}
          {formatCurrency(service.price_minor / 100, service.currency)}
        </span>
      </label>
    </li>
  );
}

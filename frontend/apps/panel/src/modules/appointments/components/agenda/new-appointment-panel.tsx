import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  Checkbox,
  ContextPanel,
  Input,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Textarea,
  toast,
} from "@ceiba/ui";
import { useId, useState } from "react";
import { apiErrorMessages } from "../../../../platform/forms/api-error-messages";
import { AsidePortal } from "../../../../platform/shell/aside-slot";
import type { AgendaProfessional, AgendaResource } from "../../api/agenda";
import { useAvailabilityQuery, useBookAppointment } from "../../api/agenda-mutations";
import { useServicesQuery, type Branch } from "../../api/catalog";
import { toWallClock, type PlainDate } from "../../lib/agenda-time";
import { createIdempotencyKeys } from "../../lib/idempotency-keys";
import type { AgendaSlot } from "../agenda-view/types";
import { FormAlert } from "../form-alert";
import { CustomerPicker, type PickedCustomer } from "./customer-picker";
import { SlotPicker } from "./slot-picker";

interface NewAppointmentPanelProps {
  id: string;
  branch: Branch;
  professionals: readonly AgendaProfessional[];
  resources: readonly AgendaResource[];
  date: PlainDate;
  /** The grid slot that opened the panel, if any. */
  slot: AgendaSlot | null;
  onClose(): void;
}

export function NewAppointmentPanel({
  id,
  branch,
  professionals,
  resources,
  date,
  slot,
  onClose,
}: NewAppointmentPanelProps) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const timeZone = branch.time_zone;
  const [keys] = useState(() => createIdempotencyKeys());
  const clicked = professionals.find((person) => person.id === slot?.resourceId);
  const [professionalId, setProfessionalId] = useState(clicked?.id ?? professionals[0]?.id ?? null);
  const [day, setDay] = useState(slot ? toWallClock(slot.startsAt, timeZone).slice(0, 10) : date);
  const [serviceIds, setServiceIds] = useState<string[]>([]);
  const [startsAt, setStartsAt] = useState(slot?.startsAt ?? null);
  const [customer, setCustomer] = useState<PickedCustomer | null>(null);
  const [notes, setNotes] = useState("");

  const services = useServicesQuery("active");
  const professional = professionals.find((person) => person.id === professionalId);
  const offered = (services.data?.data ?? []).filter((service) =>
    professional?.service_ids.includes(service.id),
  );
  const availability = useAvailabilityQuery({
    branchId: branch.id,
    serviceIds,
    professionalId,
    date: day,
  });
  const book = useBookAppointment(branch.id);

  const slots = availability.data?.data ?? [];
  const chosen = slots.find((item) => Date.parse(item.starts_at) === Date.parse(startsAt ?? ""));
  const resourceName = resources.find((item) => item.id === chosen?.resource_id)?.name;

  function changeProfessional(next: string) {
    setProfessionalId(next);
    setServiceIds([]);
    setStartsAt(null);
  }

  function toggleService(serviceId: string, checked: boolean) {
    setServiceIds((current) =>
      checked ? [...current, serviceId] : current.filter((item) => item !== serviceId),
    );
  }

  async function confirm() {
    if (!chosen || !customer || !professionalId) return;
    const body = {
      customer_id: customer.id,
      service_ids: serviceIds,
      professional_id: professionalId,
      starts_at: chosen.starts_at,
      ...(notes.trim() ? { notes: notes.trim() } : {}),
    };
    await book.mutateAsync({ body, key: keys.keyFor(body) });
    keys.settle();
    toast.success(t("agenda.form.created"));
    onClose();
  }

  // A 409 or a server failure is announced by the global toast; only a 422 belongs to this form.
  const invalid =
    book.error && "status" in book.error && book.error.status === 422
      ? apiErrorMessages(book.error, t).join(" ")
      : null;

  return (
    <AsidePortal>
      <ContextPanel
        id={id}
        open
        onOpenChange={(open) => {
          if (!open) onClose();
        }}
        title={t("agenda.newAppointment")}
        closeLabel={t("agenda.form.close")}
        footer={
          <Button
            type="button"
            className="flex-1"
            loading={book.isPending}
            disabled={!chosen || !customer}
            onClick={() => void confirm().catch(() => {})}
          >
            {t("agenda.form.confirm")}
          </Button>
        }
      >
        <div className="grid gap-1.5">
          <Label htmlFor={`${fieldId}-professional`}>{t("agenda.form.professional")}</Label>
          <Select value={professionalId ?? undefined} onValueChange={changeProfessional}>
            <SelectTrigger id={`${fieldId}-professional`}>
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
        </div>

        <fieldset className="grid gap-1.5">
          <legend className="mb-1 text-sm font-medium">{t("agenda.form.services")}</legend>
          {services.isSuccess && offered.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("agenda.form.noServices")}</p>
          ) : null}
          {offered.map((service) => {
            const checkboxId = `${fieldId}-service-${service.id}`;
            return (
              <div key={service.id} className="flex items-center gap-2">
                <Checkbox
                  id={checkboxId}
                  checked={serviceIds.includes(service.id)}
                  onCheckedChange={(checked) => toggleService(service.id, checked === true)}
                />
                <Label htmlFor={checkboxId} className="font-normal">
                  {service.name}
                </Label>
              </div>
            );
          })}
        </fieldset>

        <div className="grid gap-1.5">
          <Label htmlFor={`${fieldId}-date`}>{t("agenda.form.date")}</Label>
          <Input
            id={`${fieldId}-date`}
            type="date"
            value={day}
            onChange={(event) => {
              if (event.target.value) setDay(event.target.value);
              setStartsAt(null);
            }}
          />
        </div>

        <SlotPicker
          starts={slots.map((item) => item.starts_at)}
          value={chosen?.starts_at ?? null}
          onChange={setStartsAt}
          timeZone={timeZone}
          isLoading={availability.isPending}
          failed={availability.isError}
          hint={serviceIds.length === 0 ? t("agenda.form.pickServicesFirst") : undefined}
        />
        {resourceName ? (
          <p className="text-sm text-muted-foreground">
            {t("agenda.form.assignedResource", { resource: resourceName })}
          </p>
        ) : null}

        <CustomerPicker branchId={branch.id} value={customer} onChange={setCustomer} />

        <div className="grid gap-1.5">
          <Label htmlFor={`${fieldId}-notes`}>{t("agenda.form.notes")}</Label>
          <Textarea
            id={`${fieldId}-notes`}
            maxLength={500}
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
          />
        </div>
        {invalid ? <FormAlert>{invalid}</FormAlert> : null}
      </ContextPanel>
    </AsidePortal>
  );
}

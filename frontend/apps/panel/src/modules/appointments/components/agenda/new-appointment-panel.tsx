import { useTranslation } from "@ceiba/i18n";
import { Button, Checkbox, Label, Textarea, toast } from "@ceiba/ui";
import { useId, useState } from "react";
import { validationMessage } from "../../../../platform/forms/api-error-messages";
import type { AgendaProfessional, AgendaResource } from "../../api/agenda";
import { useBookAppointment } from "../../api/agenda-mutations";
import { useServicesQuery, type Branch } from "../../api/catalog";
import { dayInZone, type PlainDate } from "../../lib/agenda-time";
import { createIdempotencyKeys } from "../../lib/idempotency-keys";
import type { AgendaSlot } from "../agenda-view/types";
import { FormAlert } from "../form-alert";
import { AgendaSidePanel } from "./agenda-side-panel";
import { CustomerPicker, type PickedCustomer } from "./customer-picker";
import { DayAndTimeFields, ProfessionalField, useSlotSelection } from "./slot-fields";

interface NewAppointmentPanelProps {
  id: string;
  branch: Branch;
  professionals: readonly AgendaProfessional[];
  resources: readonly AgendaResource[];
  date: PlainDate;
  initialProfessionalId: string | null;
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
  initialProfessionalId,
  slot,
  onClose,
}: NewAppointmentPanelProps) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const timeZone = branch.time_zone;
  const [keys] = useState(() => createIdempotencyKeys());
  const [serviceIds, setServiceIds] = useState<string[]>([]);
  const [customer, setCustomer] = useState<PickedCustomer | null>(null);
  const [notes, setNotes] = useState("");
  const selection = useSlotSelection({
    branchId: branch.id,
    serviceIds,
    initial: {
      professionalId: initialProfessionalId,
      day: slot ? dayInZone(slot.startsAt, timeZone) : date,
      startsAt: slot?.startsAt,
    },
  });
  const services = useServicesQuery("active");
  const book = useBookAppointment(branch.id);

  const professional = professionals.find((person) => person.id === selection.professionalId);
  const offered = (services.data?.data ?? []).filter((service) =>
    professional?.service_ids.includes(service.id),
  );
  const chosen = selection.freeSlot;
  const resourceName = resources.find((item) => item.id === chosen?.resource_id)?.name;
  const invalid = validationMessage(book.error, t);

  function toggleService(serviceId: string, checked: boolean) {
    setServiceIds((current) =>
      checked ? [...current, serviceId] : current.filter((item) => item !== serviceId),
    );
  }

  async function confirm() {
    if (!chosen || !customer || !selection.professionalId) return;
    const body = {
      customer_id: customer.id,
      service_ids: serviceIds,
      professional_id: selection.professionalId,
      starts_at: chosen.starts_at,
      ...(notes.trim() ? { notes: notes.trim() } : {}),
    };
    await book.mutateAsync({ body, key: keys.keyFor(body) });
    keys.settle();
    toast.success(t("agenda.form.created"));
    onClose();
  }

  return (
    <AgendaSidePanel
      id={id}
      onClose={onClose}
      title={t("agenda.newAppointment")}
      closeLabel={t("agenda.form.close")}
      footer={
        <Button
          type="button"
          className="flex-1"
          loading={book.isPending}
          disabled={!chosen || !customer}
          // A failure is shown by the form (422) or by the global toast.
          onClick={() => void confirm().catch(() => {})}
        >
          {t("agenda.form.confirm")}
        </Button>
      }
    >
      <ProfessionalField
        selection={selection}
        professionals={professionals}
        onChange={() => setServiceIds([])}
      />

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

      <DayAndTimeFields
        selection={selection}
        timeZone={timeZone}
        dayLabel={t("agenda.form.date")}
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
    </AgendaSidePanel>
  );
}

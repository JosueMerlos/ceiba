import { useTranslation } from "@ceiba/i18n";
import { Button, Checkbox, Label } from "@ceiba/ui";
import { useId, useState } from "react";
import type { Service } from "../api/catalog";

interface ProfessionalServicesProps {
  /** Services offered for selection (the active catalog). */
  services: readonly Service[];
  selectedIds: readonly string[];
  /** `appointments.professional.manage`; the caller decides. */
  canManage: boolean;
  /** Receives the COMPLETE set: the API replaces what the professional provides. */
  onSave(serviceIds: string[]): Promise<unknown>;
}

export function ProfessionalServices({
  services,
  selectedIds,
  canManage,
  onSave,
}: ProfessionalServicesProps) {
  const { t } = useTranslation("appointments");
  const groupId = useId();
  const [selected, setSelected] = useState<string[]>([...selectedIds]);
  const [saving, setSaving] = useState(false);

  if (services.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">{t("catalog.professionalServices.empty")}</p>
    );
  }

  const toggle = (id: string, checked: boolean) =>
    setSelected((current) =>
      checked
        ? [...current.filter((item) => item !== id), id]
        : current.filter((item) => item !== id),
    );

  async function save() {
    setSaving(true);
    try {
      await onSave(selected);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="grid gap-3">
      <div className="grid gap-2">
        {services.map((service) => {
          const id = `${groupId}-${service.id}`;
          return (
            <div key={service.id} className="flex items-center gap-2.5">
              <Checkbox
                id={id}
                checked={selected.includes(service.id)}
                disabled={!canManage}
                onCheckedChange={(checked) => toggle(service.id, checked === true)}
              />
              <Label htmlFor={id} className="font-normal">
                {service.name}
              </Label>
            </div>
          );
        })}
      </div>
      {canManage ? (
        <div>
          <Button type="button" variant="outline" loading={saving} onClick={() => void save()}>
            {t("catalog.professionalServices.save")}
          </Button>
        </div>
      ) : null}
    </div>
  );
}

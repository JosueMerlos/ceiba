import { useTranslation } from "@ceiba/i18n";
import { Button, FormDialog, toast } from "@ceiba/ui";
import { useId } from "react";
import { useCreateService, useUpdateService, type Service } from "../api/catalog";
import { ServiceForm, type ServiceFormValues } from "./service-form";

interface ServiceDialogProps {
  open: boolean;
  onOpenChange(open: boolean): void;
  /** Absent = create. */
  service?: Service;
  currency: "NIO" | "USD";
  categories: readonly string[];
}

/** Create or edit a service in one step, with the single save button in the footer. */
export function ServiceDialog({
  open,
  onOpenChange,
  service,
  currency,
  categories,
}: ServiceDialogProps) {
  const { t } = useTranslation(["appointments", "common"]);
  const formId = useId();
  const create = useCreateService();
  const update = useUpdateService();

  async function save(values: ServiceFormValues) {
    if (service) {
      await update.mutateAsync({ id: service.id, body: values });
      toast.success(t("catalog.services.updated"));
    } else {
      await create.mutateAsync({ ...values, position: 0 });
      toast.success(t("catalog.services.created"));
    }
    onOpenChange(false);
  }

  return (
    <FormDialog
      open={open}
      onOpenChange={onOpenChange}
      title={service ? t("catalog.services.edit") : t("catalog.services.panelNewTitle")}
      description={service?.name}
      closeLabel={t("common:close")}
      footer={
        <Button type="submit" form={formId} loading={create.isPending || update.isPending}>
          {service ? t("catalog.serviceForm.save") : t("catalog.serviceForm.create")}
        </Button>
      }
    >
      <ServiceForm
        key={service ? `${service.id}:${service.updated_at}` : "new"}
        id={formId}
        service={service}
        currency={service?.currency ?? currency}
        categories={categories}
        onSubmit={save}
      />
    </FormDialog>
  );
}

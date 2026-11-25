import { useTranslation } from "@ceiba/i18n";
import { Button, FormDialog } from "@ceiba/ui";
import { useId } from "react";
import type { Customer, CustomerPatch } from "./api";
import { CustomerForm } from "./customer-form";

interface CustomerDialogProps {
  open: boolean;
  onOpenChange(open: boolean): void;
  title: string;
  /** Absent = create. */
  customer?: Customer;
  pending: boolean;
  /** Rejects with the API error; the form shows it next to its field and the modal stays open. */
  onSubmit(values: CustomerPatch): Promise<unknown>;
}

/** Create or edit a customer in one step: the same fields in both cases and a single save in the footer. */
export function CustomerDialog({
  open,
  onOpenChange,
  title,
  customer,
  pending,
  onSubmit,
}: CustomerDialogProps) {
  const { t } = useTranslation(["customers", "common"]);
  const formId = useId();
  return (
    <FormDialog
      open={open}
      onOpenChange={onOpenChange}
      title={title}
      closeLabel={t("common:close")}
      className="sm:max-w-xl"
      footer={
        <Button type="submit" form={formId} loading={pending}>
          {t("form.save")}
        </Button>
      }
    >
      <CustomerForm
        key={customer?.updated_at ?? "new"}
        id={formId}
        customer={customer}
        onSubmit={onSubmit}
      />
    </FormDialog>
  );
}

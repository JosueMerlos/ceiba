import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  toast,
} from "@ceiba/ui";
import { useId, useState } from "react";
import { useCancelAppointment, type CancellationReason } from "../../api/agenda-mutations";

const REASONS: readonly CancellationReason[] = [
  "customer_request",
  "professional_unavailable",
  "business_decision",
  "other",
];

interface CancelFormProps {
  branchId: string;
  appointmentId: string;
  onBack(): void;
  onDone(): void;
}

export function CancelForm({ branchId, appointmentId, onBack, onDone }: CancelFormProps) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const cancel = useCancelAppointment(branchId);
  const [reason, setReason] = useState<CancellationReason | null>(null);

  function submit() {
    if (!reason) return;
    cancel.mutate(
      { id: appointmentId, reason },
      {
        onSuccess: () => {
          toast.success(t("agenda.detail.cancelled"));
          onDone();
        },
      },
    );
  }

  return (
    <div className="grid gap-2">
      <div className="grid gap-1.5">
        <Label htmlFor={fieldId}>{t("agenda.detail.reason")}</Label>
        <Select
          value={reason ?? undefined}
          onValueChange={(value) => setReason(REASONS.find((item) => item === value) ?? null)}
        >
          <SelectTrigger id={fieldId}>
            <SelectValue placeholder={t("agenda.detail.reasonPlaceholder")} />
          </SelectTrigger>
          <SelectContent>
            {REASONS.map((item) => (
              <SelectItem key={item} value={item}>
                {t(`agenda.detail.reasons.${item}`)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <Button
        type="button"
        variant="destructive"
        disabled={!reason}
        loading={cancel.isPending}
        onClick={submit}
      >
        {t("agenda.detail.confirmCancel")}
      </Button>
      <Button type="button" variant="ghost" onClick={onBack}>
        {t("agenda.detail.back")}
      </Button>
    </div>
  );
}

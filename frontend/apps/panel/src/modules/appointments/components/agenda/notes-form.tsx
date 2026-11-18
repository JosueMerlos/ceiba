import { useTranslation } from "@ceiba/i18n";
import { Button, Label, Textarea, toast } from "@ceiba/ui";
import { useId, useState } from "react";
import { useUpdateNotes } from "../../api/agenda-mutations";

interface NotesFormProps {
  branchId: string;
  appointmentId: string;
  notes: string;
  lockVersion: number;
}

export function NotesForm({ branchId, appointmentId, notes, lockVersion }: NotesFormProps) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const update = useUpdateNotes(branchId);
  const [value, setValue] = useState(notes);
  return (
    <div className="grid gap-1.5 border-t pt-4">
      <Label htmlFor={fieldId}>{t("agenda.detail.notes")}</Label>
      <Textarea
        id={fieldId}
        maxLength={500}
        value={value}
        onChange={(event) => setValue(event.target.value)}
      />
      <Button
        type="button"
        variant="outline"
        size="sm"
        disabled={value === notes}
        loading={update.isPending}
        onClick={() =>
          update.mutate(
            { id: appointmentId, notes: value.trim() || null, lockVersion },
            { onSuccess: () => toast.success(t("agenda.detail.notesSaved")) },
          )
        }
      >
        {t("agenda.detail.saveNotes")}
      </Button>
    </div>
  );
}

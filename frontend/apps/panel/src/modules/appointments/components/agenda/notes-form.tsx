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

/**
 * The appointment's notes. What the user typed is a draft that survives any refresh of the appointment (a status change,
 * someone else's edit): after a 409 the draft is still there and saving again applies it over the newer version.
 */
export function NotesForm({ branchId, appointmentId, notes, lockVersion }: NotesFormProps) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const update = useUpdateNotes(branchId);
  const [draft, setDraft] = useState<string | null>(null);
  const value = draft ?? notes;
  return (
    <div className="grid gap-1.5 border-t pt-4">
      <Label htmlFor={fieldId}>{t("agenda.detail.notes")}</Label>
      <Textarea
        id={fieldId}
        maxLength={500}
        value={value}
        onChange={(event) => setDraft(event.target.value)}
      />
      <Button
        type="button"
        variant="outline"
        size="sm"
        disabled={draft === null || draft === notes}
        loading={update.isPending}
        onClick={() =>
          update.mutate(
            { id: appointmentId, notes: value.trim() || null, lockVersion },
            {
              onSuccess: () => {
                setDraft(null);
                toast.success(t("agenda.detail.notesSaved"));
              },
            },
          )
        }
      >
        {t("agenda.detail.saveNotes")}
      </Button>
    </div>
  );
}

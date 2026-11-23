import { useTranslation } from "@ceiba/i18n";
import { Button, Label, Textarea, toast } from "@ceiba/ui";
import { useId, useState } from "react";
import { useUpdateNotes } from "../../api/agenda-mutations";
import { FormAlert } from "../form-alert";

interface NotesFormProps {
  branchId: string;
  appointmentId: string;
  notes: string;
  lockVersion: number;
}

/** What the user typed, and the notes it was written over. */
interface Draft {
  text: string;
  base: string;
}

/**
 * The appointment's notes. The draft survives any refresh of the appointment (a status change also moves its version), and
 * it is saved over the latest version only while the notes underneath are still the ones it was written over: when someone
 * else changed them, their text is shown and the user decides, so nothing is overwritten unseen.
 */
export function NotesForm({ branchId, appointmentId, notes, lockVersion }: NotesFormProps) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const update = useUpdateNotes(branchId);
  const [draft, setDraft] = useState<Draft | null>(null);
  const conflict = draft !== null && draft.base !== notes;
  const value = draft?.text ?? notes;

  function save() {
    if (!draft) return;
    update.mutate(
      { id: appointmentId, notes: draft.text.trim() || null, lockVersion },
      {
        onSuccess: () => {
          setDraft(null);
          toast.success(t("agenda.detail.notesSaved"));
        },
      },
    );
  }

  return (
    <div className="grid gap-1.5 border-t pt-4">
      <Label htmlFor={fieldId}>{t("agenda.detail.notes")}</Label>
      <Textarea
        id={fieldId}
        maxLength={500}
        value={value}
        // While saving, a keystroke would be lost when the saved text comes back.
        disabled={update.isPending}
        onChange={(event) => setDraft({ text: event.target.value, base: draft?.base ?? notes })}
      />
      {conflict ? (
        <FormAlert>
          <span className="grid gap-2">
            <span>
              {t("agenda.detail.notesChanged", { notes: notes || t("agenda.detail.noNotes") })}
            </span>
            <span className="flex flex-wrap gap-2">
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => setDraft({ text: draft.text, base: notes })}
              >
                {t("agenda.detail.keepMine")}
              </Button>
              <Button type="button" size="sm" variant="ghost" onClick={() => setDraft(null)}>
                {t("agenda.detail.discardMine")}
              </Button>
            </span>
          </span>
        </FormAlert>
      ) : null}
      <Button
        type="button"
        variant="outline"
        size="sm"
        disabled={!draft || conflict || draft.text === notes}
        loading={update.isPending}
        onClick={save}
      >
        {t("agenda.detail.saveNotes")}
      </Button>
    </div>
  );
}

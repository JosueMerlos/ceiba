import { useTranslation } from "@ceiba/i18n";
import { Plus } from "lucide-react";

/** "New appointment" on a phone: always within the thumb's reach, over the list. */
export function NewAppointmentFab({ onClick }: { onClick(): void }) {
  const { t } = useTranslation("appointments");
  return (
    <button
      type="button"
      aria-label={t("agenda.newAppointment")}
      onClick={onClick}
      className="fixed right-4 bottom-4 z-30 grid size-14 place-items-center rounded-2xl bg-primary text-primary-foreground shadow-lg outline-none focus-visible:ring-3 focus-visible:ring-ring/50 [&_svg]:size-6"
    >
      <Plus aria-hidden="true" />
    </button>
  );
}

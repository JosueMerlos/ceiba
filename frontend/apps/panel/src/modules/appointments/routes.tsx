import { useTranslation } from "@ceiba/i18n";
import { PageHeader } from "@ceiba/ui";
import { CalendarDays, ChartNoAxesColumn, type LucideIcon } from "lucide-react";

// Placeholders de F0: el dominio de citas llega en F1 y las pantallas de agenda en F2.
function Placeholder({ icon: Icon, children }: { icon: LucideIcon; children: string }) {
  return (
    <section
      data-module="appointments-placeholder"
      className="grid place-items-center gap-3 rounded-xl border border-dashed bg-card px-6 py-16 text-center"
    >
      <span className="grid size-12 place-items-center rounded-full bg-accent text-accent-foreground">
        <Icon className="size-6" aria-hidden="true" />
      </span>
      <p className="max-w-sm text-muted-foreground">{children}</p>
    </section>
  );
}

export function AgendaPage() {
  const { t } = useTranslation("appointments");
  return (
    <>
      <PageHeader title={t("agenda.title")} description={t("agenda.description")} />
      <Placeholder icon={CalendarDays}>{t("agenda.comingSoon")}</Placeholder>
    </>
  );
}

export function SummaryPage() {
  const { t } = useTranslation("appointments");
  return (
    <>
      <PageHeader title={t("summary.title")} description={t("summary.description")} />
      <Placeholder icon={ChartNoAxesColumn}>{t("summary.comingSoon")}</Placeholder>
    </>
  );
}

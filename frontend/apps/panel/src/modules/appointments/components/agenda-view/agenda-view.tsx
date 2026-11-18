import { useTranslation } from "@ceiba/i18n";
import { LoadingState } from "@ceiba/ui";
import { lazy, Suspense } from "react";
import type { AgendaViewProps } from "./types";

// The calendar library lives only in this chunk: the catalog pages share the module's chunk and must not download it.
const loadAdapter = () => import("./adapters/event-calendar");
const EventCalendarAdapter = lazy(loadAdapter);

/** Starts the download next to the page's data requests, instead of after them. */
export function preloadAgendaView() {
  void loadAdapter();
}

/** The page talks only to this component; which calendar library draws it is the adapter's business. */
export function AgendaView(props: AgendaViewProps) {
  const { t } = useTranslation("common");
  return (
    <Suspense fallback={<LoadingState label={t("loading")} />}>
      <EventCalendarAdapter {...props} />
    </Suspense>
  );
}

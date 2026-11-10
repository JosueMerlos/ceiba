import { CalendarDays, ChartNoAxesColumn } from "lucide-react";
import { lazyPage } from "../lazy-page";
import type { ModuleManifest } from "../types";

// Permissions and navigation routes mirror backend/packs/modules/appointments/manifest.rb.
// Pages live in ./routes (a single chunk per module, see vite.config.ts).
const load = () => import("./routes");

export const appointments: ModuleManifest = {
  key: "appointments",
  routes: [
    {
      path: "agenda",
      permission: "appointments.appointment.read",
      element: lazyPage(load, "AgendaPage"),
    },
    {
      path: "agenda/summary",
      permission: "appointments.appointment.count",
      element: lazyPage(load, "SummaryPage"),
    },
  ],
  navigation: [
    {
      key: "agenda",
      path: "/agenda",
      labelKey: "nav.agenda",
      permission: "appointments.appointment.read",
      icon: CalendarDays,
    },
    {
      key: "summary",
      path: "/agenda/summary",
      labelKey: "nav.summary",
      permission: "appointments.appointment.count",
      icon: ChartNoAxesColumn,
    },
  ],
};

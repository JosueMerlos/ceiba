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
      // The professional reads only their own appointments.
      permissions: ["appointments.appointment.read", "appointments.appointment.read_own"],
      element: lazyPage(load, "AgendaPage"),
    },
    {
      path: "agenda/summary",
      permissions: ["appointments.appointment.count"],
      element: lazyPage(load, "SummaryPage"),
    },
  ],
  navigation: [
    {
      key: "agenda",
      path: "/agenda",
      labelKey: "nav.agenda",
      permissions: ["appointments.appointment.read", "appointments.appointment.read_own"],
      icon: CalendarDays,
    },
    {
      key: "summary",
      path: "/agenda/summary",
      labelKey: "nav.summary",
      permissions: ["appointments.appointment.count"],
      icon: ChartNoAxesColumn,
    },
  ],
};

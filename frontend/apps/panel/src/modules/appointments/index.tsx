import {
  Armchair,
  Building2,
  CalendarDays,
  ChartNoAxesColumn,
  Scissors,
  UsersRound,
} from "lucide-react";
import { lazyPage } from "../lazy-page";
import type { ModuleManifest } from "../types";

// Permissions and navigation routes mirror backend/packs/modules/appointments/manifest.rb.
// Pages live in ./routes (a single chunk per module, see vite.config.ts).
const load = () => import("./routes");
const namespaces = ["appointments"] as const;

export const appointments: ModuleManifest = {
  key: "appointments",
  routes: [
    {
      path: "agenda",
      // The professional reads only their own appointments.
      permissions: ["appointments.appointment.read", "appointments.appointment.read_own"],
      element: lazyPage(load, "AgendaPage", namespaces),
    },
    {
      path: "agenda/summary",
      permissions: ["appointments.appointment.count"],
      element: lazyPage(load, "SummaryPage", namespaces),
    },
    {
      path: "services",
      permissions: ["appointments.service.read"],
      element: lazyPage(load, "ServicesPage", namespaces),
    },
    {
      path: "professionals",
      permissions: ["appointments.professional.read"],
      element: lazyPage(load, "ProfessionalsPage", namespaces),
    },
    {
      path: "resources",
      permissions: ["appointments.resource.read"],
      element: lazyPage(load, "ResourcesPage", namespaces),
    },
    {
      path: "branches",
      permissions: ["appointments.schedule.read"],
      element: lazyPage(load, "BranchesPage", namespaces),
    },
    {
      path: "branches/:branchId/schedule",
      permissions: ["appointments.schedule.read"],
      element: lazyPage(load, "BranchSchedulePage", namespaces),
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
    {
      key: "services",
      path: "/services",
      labelKey: "nav.services",
      permissions: ["appointments.service.read"],
      icon: Scissors,
    },
    {
      key: "professionals",
      path: "/professionals",
      labelKey: "nav.professionals",
      permissions: ["appointments.professional.read"],
      icon: UsersRound,
    },
    {
      key: "resources",
      path: "/resources",
      labelKey: "nav.resources",
      permissions: ["appointments.resource.read"],
      icon: Armchair,
    },
    {
      key: "branches",
      path: "/branches",
      labelKey: "nav.branches",
      permissions: ["appointments.schedule.read"],
      icon: Building2,
    },
  ],
};

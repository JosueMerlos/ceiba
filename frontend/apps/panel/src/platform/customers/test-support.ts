import type { components } from "@ceiba/api-client";
import { API, ids } from "../../test/fixtures";

export const CUSTOMER_PERMISSIONS = [
  "platform.customer.read",
  "platform.customer.create",
  "platform.customer.update",
  "platform.customer.archive",
];

export const customerId = "0198f0a0-0000-7000-8000-00000000c001";

export const customersUrl = (branchId = ids.branchA) =>
  `${API}/api/v1/organizations/${ids.orgA}/companies/${ids.companyA}/branches/${branchId}/customers`;

export const historyUrl = (id = customerId, branchId = ids.branchA) =>
  `${API}/api/v1/organizations/${ids.orgA}/companies/${ids.companyA}/appointments/branches/${branchId}/customers/${id}/appointments`;

export const customerFixture = (
  overrides: Partial<components["schemas"]["Customer"]> = {},
): components["schemas"]["Customer"] => ({
  id: customerId,
  full_name: "Fernanda Ruiz",
  phone_e164: "+50588123456",
  email: null,
  notes: null,
  archived_at: null,
  created_at: "2026-03-03T15:00:00.000Z",
  updated_at: "2026-03-03T15:00:00.000Z",
  ...overrides,
});

export const visitFixture = (
  overrides: Partial<components["schemas"]["CustomerAppointment"]> = {},
): components["schemas"]["CustomerAppointment"] => ({
  id: "0198f0a0-0000-7000-8000-00000000d001",
  status: "completed",
  starts_at: "2026-11-02T03:30:00.000Z",
  ends_at: "2026-11-02T04:00:00.000Z",
  professional: { id: "0198f0a0-0000-7000-8000-00000000e001", display_name: "Rosa Martínez" },
  services: [{ service_id: "0198f0a0-0000-7000-8000-00000000f001", name: "Corte de cabello" }],
  ...overrides,
});

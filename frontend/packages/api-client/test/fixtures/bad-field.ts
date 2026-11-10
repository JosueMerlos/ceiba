// Fixture for type-safety.test.ts: reads a field that does NOT exist in the contract; tsc must reject it (TS2339).
import type { components } from "../../src/schema";

type Organization = components["schemas"]["Organization"];

export const phone = (organization: Organization) => organization.phone_number;

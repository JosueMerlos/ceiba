// Fixture for type-safety.test.ts: reads ONLY fields that exist in the contract; tsc must accept it.
import type { components } from "../../src/schema";

type Organization = components["schemas"]["Organization"];

export const name = (organization: Organization): string => organization.name;
export const legalName = (organization: Organization): string | null => organization.legal_name;

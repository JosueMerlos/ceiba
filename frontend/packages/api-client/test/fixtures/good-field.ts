// Fixture de type-safety.test.ts: accede SOLO a campos que existen en el contrato; tsc debe aceptarlo.
import type { components } from "../../src/schema";

type Organization = components["schemas"]["Organization"];

export const name = (organization: Organization): string => organization.name;
export const legalName = (organization: Organization): string | null => organization.legal_name;

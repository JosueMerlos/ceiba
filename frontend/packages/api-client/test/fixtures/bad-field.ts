// Fixture de type-safety.test.ts: accede a un campo que NO existe en el contrato; tsc debe rechazarlo (TS2339).
import type { components } from "../../src/schema";

type Organization = components["schemas"]["Organization"];

export const phone = (organization: Organization) => organization.phone_number;

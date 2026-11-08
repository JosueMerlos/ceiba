// Criterio 5 de M0.06, versión "verde cuando falla": este archivo lo compila `pnpm typecheck` (tsc) en CI.
// Cada @ts-expect-error afirma que tsc RECHAZA esa línea. Si el cliente dejara de tipar la respuesta (p. ej. todo
// `any`) o el contrato ganara ese campo, el error esperado desaparece y tsc falla con "Unused '@ts-expect-error'".
import { createApiClient } from "../src";

const client = createApiClient({ baseUrl: "http://localhost" });

export async function organizationFields() {
  const { data } = await client.GET("/api/v1/organizations/{id}", { params: { path: { id: "x" } } });
  const organization = data?.data;

  // Campos que existen: compilan.
  const _name: string | undefined = organization?.name;
  const _status: "active" | "suspended" | undefined = organization?.status;

  // @ts-expect-error -- `phone_number` no existe en components.schemas.Organization
  const _phone = organization?.phone_number;

  // @ts-expect-error -- `status` es "active" | "suspended": un número no es asignable
  const _wrongType: number | undefined = organization?.status;

  // @ts-expect-error -- esa ruta no existe en el contrato
  await client.GET("/api/v1/no-existe", {});

  return [_name, _status, _phone, _wrongType];
}

// "Green when it fails" version: `pnpm typecheck` (tsc) compiles this file in CI. Each @ts-expect-error asserts that tsc
// REJECTS that line. If the client stopped typing the response (e.g. everything `any`) or the contract gained that field,
// the expected error disappears and tsc fails with "Unused '@ts-expect-error'".
import { createApiClient } from "../src";

const client = createApiClient({ baseUrl: "http://localhost" });

export async function organizationFields() {
  const { data } = await client.GET("/api/v1/organizations/{id}", {
    params: { path: { id: "x" } },
  });
  const organization = data?.data;

  const _name: string | undefined = organization?.name;
  const _status: "active" | "suspended" | undefined = organization?.status;

  // @ts-expect-error -- `phone_number` does not exist in components.schemas.Organization
  const _phone = organization?.phone_number;

  // @ts-expect-error -- `status` is "active" | "suspended": a number is not assignable
  const _wrongType: number | undefined = organization?.status;

  // @ts-expect-error -- that route does not exist in the contract
  await client.GET("/api/v1/no-existe", {});

  return [_name, _status, _phone, _wrongType];
}

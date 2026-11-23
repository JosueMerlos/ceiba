import { useMe } from "../me/me-provider";

/** Path parameters of a branch-scoped platform route: organization and company from the context, the branch given. */
export function useBranchScope(branchId: string) {
  const { context } = useMe();
  if (!context.organization || !context.company) {
    throw new Error("Esta pantalla necesita una organización y una empresa en el contexto");
  }
  return {
    organizationId: context.organization.id,
    companyId: context.company.id,
    path: {
      organization_id: context.organization.id,
      company_id: context.company.id,
      branch_id: branchId,
    },
  };
}

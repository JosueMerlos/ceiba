import { useBranchesQuery, useCompaniesQuery, useOrganizationsQuery } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import { useMe } from "../me/me-provider";
import { ContextMenu, type ContextLevel } from "./context-menu";
import { useContextSelection } from "./context-provider";

/** Contenedor: pide las opciones de cada nivel a la API y le pasa al menú lo que hay que mostrar. */
export function ContextSelector() {
  const { t } = useTranslation("shell");
  const { context } = useMe();
  const { switchContext } = useContextSelection();
  const organizationId = context.organization?.id;
  const companyId = context.company?.id;

  const organizations = useOrganizationsQuery();
  const companies = useCompaniesQuery(organizationId);
  const branches = useBranchesQuery(organizationId, companyId);

  // Mientras cargan las listas el selector reserva su sitio (sin parpadeo: aparecer de golpe movería la cabecera).
  if (organizations.isLoading || companies.isLoading || branches.isLoading) {
    return (
      <div
        data-slot="context-skeleton"
        aria-hidden="true"
        className="h-10 w-10 animate-pulse rounded-lg bg-muted sm:w-44"
      />
    );
  }

  // «Todas las sucursales» no cuenta como opción: con una sola sucursal real no hay nada que elegir.
  const realBranches = (branches.data?.data ?? []).map(({ id, name }) => ({
    value: id,
    label: name,
  }));
  const branchOptions =
    realBranches.length > 1
      ? [{ value: "", label: t("context.allBranches") }, ...realBranches]
      : realBranches;
  const levels: ContextLevel[] = [
    {
      key: "organization",
      label: t("context.organization"),
      value: organizationId ?? "",
      options: (organizations.data?.data ?? []).map((organization) => ({
        value: organization.id,
        label:
          organization.status === "suspended"
            ? t("context.suspended", { name: organization.name })
            : organization.name,
        // Una organización suspendida responde 403 en /me: elegirla dejaría al usuario sin pantalla.
        disabled: organization.status === "suspended",
      })),
    },
    {
      key: "company",
      label: t("context.company"),
      value: companyId ?? "",
      options: (companies.data?.data ?? []).map(({ id, name }) => ({ value: id, label: name })),
    },
    {
      key: "branch",
      label: t("context.branch"),
      value: context.branch?.id ?? "",
      options: branchOptions,
    },
  ];
  function onSelect(level: ContextLevel["key"], value: string) {
    if (!organizationId) return;
    if (level === "organization") {
      if (value !== organizationId) switchContext({ organization_id: value });
    } else if (level === "company") {
      if (value !== companyId)
        switchContext({ organization_id: organizationId, company_id: value });
    } else if (companyId && value !== (context.branch?.id ?? "")) {
      switchContext({
        organization_id: organizationId,
        company_id: companyId,
        ...(value ? { branch_id: value } : {}),
      });
    }
  }

  const summary = [context.company?.name, context.branch?.name].filter(Boolean).join(" · ");
  return (
    <ContextMenu
      triggerLabel={t("context.menuLabel")}
      summary={summary}
      levels={levels}
      onSelect={onSelect}
    />
  );
}

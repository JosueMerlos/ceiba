import { useTranslation } from "@ceiba/i18n";
import { PageHeader, StatusPage } from "@ceiba/ui";
import { Link } from "react-router";
import { navigationFor } from "../../modules/registry";
import { useMe } from "../me/me-provider";

export function HomePage() {
  const { t } = useTranslation("shell");
  const me = useMe();
  const items = navigationFor(me);
  const { company, branch } = me.context;

  return (
    <>
      <PageHeader
        title={t("home.greeting", { name: me.principal.name.split(" ")[0] ?? me.principal.name })}
        description={
          <>
            {t("home.workingIn", { company: company?.name ?? "" })}
            {branch ? ` · ${t("home.inBranch", { branch: branch.name })}` : null}
          </>
        }
      />
      {items.length === 0 ? (
        <p className="text-muted-foreground">{t("home.noModules")}</p>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {items.map(({ key, path, labelKey, icon: Icon }) => (
            <li key={key}>
              <Link
                to={path}
                className="group flex items-center gap-3 rounded-xl border bg-card p-4 transition-colors hover:border-primary/40 hover:bg-accent"
              >
                <span className="grid size-10 place-items-center rounded-lg bg-secondary text-secondary-foreground transition-colors group-hover:bg-card">
                  <Icon className="size-5" aria-hidden="true" />
                </span>
                <span className="font-medium">{t(labelKey)}</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

/** Usuario autenticado pero sin memberships: /me responde 200 con el contexto vacío. */
export function NoAccessPage() {
  const { t } = useTranslation("shell");
  return <StatusPage title={t("noContext.title")} description={t("noContext.description")} />;
}

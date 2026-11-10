import { useTranslation } from "@ceiba/i18n";
import { AppLayout, CeibaMark, NavItem } from "@ceiba/ui";
import { Link, NavLink, Outlet } from "react-router";
import { navigationFor } from "../../modules/registry";
import { ContextSelector } from "../context/context-selector";
import { useMe } from "../me/me-provider";
import { SilentBoundary } from "./silent-boundary";
import { UserMenu } from "./user-menu";

/** Layout del panel: la navegación sale SOLO de /me (módulos activos y permisos), nunca de una lista fija. */
export function AppShell() {
  const { t } = useTranslation(["shell", "common"]);
  const me = useMe();
  const items = navigationFor(me);

  return (
    <AppLayout
      skipLinkLabel={t("shell:skipLink")}
      navigationLabel={t("shell:navigation")}
      brand={
        <Link
          to="/"
          aria-label={t("shell:goHome")}
          className="flex items-center gap-2.5 rounded-md focus-visible:outline-offset-4"
        >
          <CeibaMark className="size-8" />
          <span className="font-display text-xl font-semibold tracking-tight">
            {t("common:appName")}
          </span>
        </Link>
      }
      navigation={
        items.length > 0
          ? items.map(({ key, path, labelKey, icon: Icon }) => (
              <NavItem key={key} asChild>
                <NavLink to={path} end>
                  <Icon aria-hidden="true" />
                  {t(labelKey, { ns: "shell" })}
                </NavLink>
              </NavItem>
            ))
          : null
      }
      actions={
        <>
          <SilentBoundary>
            <ContextSelector />
          </SilentBoundary>
          <UserMenu />
        </>
      }
    >
      <Outlet />
    </AppLayout>
  );
}

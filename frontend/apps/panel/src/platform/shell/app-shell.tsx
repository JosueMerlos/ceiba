import { useTranslation } from "@ceiba/i18n";
import { AppLayout, CeibaMark, NavItem } from "@ceiba/ui";
import { NavLink, Outlet } from "react-router";
import { navigationFor } from "../../modules/registry";
import { ContextSelector } from "../context/context-selector";
import { useMe } from "../me/me-provider";
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
        <>
          <CeibaMark className="size-8" />
          <span className="font-display text-xl font-semibold tracking-tight">
            {t("common:appName")}
          </span>
        </>
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
          <ContextSelector />
          <UserMenu />
        </>
      }
    >
      <Outlet />
    </AppLayout>
  );
}

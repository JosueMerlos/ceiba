import { useTranslation } from "@ceiba/i18n";
import { AppLayout, CeibaMark, NavItem } from "@ceiba/ui";
import { Palette, type LucideIcon } from "lucide-react";
import { Link, NavLink, Outlet } from "react-router";
import { navigationFor } from "../../modules/registry";
import type { ModuleNavigation } from "../../modules/types";
import { ContextSelector } from "../context/context-selector";
import { useMe } from "../me/me-provider";
import { useCan } from "../permissions/can";
import { SilentBoundary } from "./silent-boundary";
import { UserMenu } from "./user-menu";

interface ShellNavItem {
  key: string;
  path: string;
  labelKey: ModuleNavigation["labelKey"] | "nav.branding";
  icon: LucideIcon;
}

/** Platform screens are not module navigation (/me only offers modules): they show by permission. */
const platformNavigation = (can: (permission: string) => boolean): ShellNavItem[] =>
  can("platform.branding.update")
    ? [
        {
          key: "platform.branding",
          path: "/settings/branding",
          labelKey: "nav.branding",
          icon: Palette,
        },
      ]
    : [];

/** Panel layout: navigation comes ONLY from /me (active modules and permissions), never from a fixed list. */
export function AppShell() {
  const { t } = useTranslation(["shell", "common"]);
  const me = useMe();
  const can = useCan();
  const items: ShellNavItem[] = [...navigationFor(me), ...platformNavigation(can)];

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

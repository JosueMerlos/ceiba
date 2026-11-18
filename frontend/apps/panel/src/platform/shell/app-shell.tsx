import { useTranslation } from "@ceiba/i18n";
import { AppLayout, CeibaMark, NavItem } from "@ceiba/ui";
import { Palette, type LucideIcon } from "lucide-react";
import { useState } from "react";
import { Link, NavLink, Outlet } from "react-router";
import { navigationFor } from "../../modules/registry";
import type { ModuleNavigation } from "../../modules/types";
import { ContextSelector } from "../context/context-selector";
import { useMe } from "../me/me-provider";
import { useCan } from "../permissions/can";
import { AsideSlotProvider } from "./aside-slot";
import { SilentBoundary } from "./silent-boundary";
import { useSidebarCollapsed } from "./use-sidebar-collapsed";
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
  const [collapsed, setCollapsed] = useSidebarCollapsed(me.principal.id);
  const [asideSlot, setAsideSlot] = useState<HTMLElement | null>(null);

  return (
    <AsideSlotProvider value={asideSlot}>
      <AppLayout
        skipLinkLabel={t("shell:skipLink")}
        navigationLabel={t("shell:navigation")}
        collapsed={collapsed}
        onCollapsedChange={setCollapsed}
        collapseLabel={t("shell:sidebar.collapse")}
        expandLabel={t("shell:sidebar.expand")}
        brand={
          <Link
            to="/"
            aria-label={t("shell:goHome")}
            className="flex min-w-0 items-center gap-2.5 rounded-md focus-visible:outline-offset-4"
          >
            <CeibaMark className="size-7 shrink-0" />
            <span className="truncate font-display text-xl font-bold tracking-tight md:group-data-[collapsed=true]/frame:hidden">
              {t("common:appName")}
            </span>
          </Link>
        }
        context={
          <SilentBoundary>
            <ContextSelector />
          </SilentBoundary>
        }
        navigation={
          items.length > 0
            ? items.map(({ key, path, labelKey, icon: Icon }) => (
                <NavItem
                  key={key}
                  asChild
                  icon={<Icon aria-hidden="true" />}
                  label={t(labelKey, { ns: "shell" })}
                >
                  <NavLink to={path} end />
                </NavItem>
              ))
            : null
        }
        account={<UserMenu />}
        aside={<div ref={setAsideSlot} className="contents" />}
      >
        <Outlet />
      </AppLayout>
    </AsideSlotProvider>
  );
}

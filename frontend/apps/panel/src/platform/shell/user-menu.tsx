import { useLogoutAllMutation, useLogoutMutation } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
  RailTooltip,
} from "@ceiba/ui";
import { LogOut, ShieldOff } from "lucide-react";
import { lazy, Suspense, useState } from "react";
import { useNavigate } from "react-router";
import { useMe } from "../me/me-provider";
import { initials } from "./initials";

// The dialog loads the first time it is requested (it does not weigh on panel startup).
const LogoutAllDialog = lazy(() => import("./logout-all-dialog"));

export function UserMenu() {
  const { t } = useTranslation(["shell", "auth", "common"]);
  const { principal } = useMe();
  const navigate = useNavigate();
  const logout = useLogoutMutation();
  const logoutAll = useLogoutAllMutation();
  const [confirmOpen, setConfirmOpen] = useState(false);

  const goToLogin = () => navigate("/login", { replace: true });

  return (
    <>
      <DropdownMenu>
        <RailTooltip label={principal.name}>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              aria-label={t("shell:userMenu", { name: principal.name })}
              className="flex w-full min-w-0 items-center gap-2.5 rounded-xl p-1.5 text-left text-sm transition-colors outline-none hover:bg-sidebar-accent/70 focus-visible:ring-3 focus-visible:ring-ring/30 max-md:w-auto md:group-data-[collapsed=true]/frame:mx-auto md:group-data-[collapsed=true]/frame:w-auto"
            >
              <span
                aria-hidden="true"
                className="grid size-8 shrink-0 place-items-center rounded-full border bg-card text-xs font-bold"
              >
                {initials(principal.name)}
              </span>
              <span
                aria-hidden="true"
                className="grid min-w-0 leading-tight max-md:hidden md:group-data-[collapsed=true]/frame:hidden"
              >
                <span className="truncate font-semibold">{principal.name}</span>
                <span className="truncate text-xs text-muted-foreground">{principal.email}</span>
              </span>
            </button>
          </DropdownMenuTrigger>
        </RailTooltip>
        <DropdownMenuContent side="top" align="start" className="w-64">
          <DropdownMenuLabel className="grid gap-0.5 font-normal">
            <span className="text-sm font-medium text-foreground">{principal.name}</span>
            <span className="truncate">{principal.email}</span>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => logout.mutate(undefined, { onSuccess: goToLogin })}>
            <LogOut aria-hidden="true" />
            {t("auth:logout")}
          </DropdownMenuItem>
          <DropdownMenuItem variant="destructive" onSelect={() => setConfirmOpen(true)}>
            <ShieldOff aria-hidden="true" />
            {t("auth:logoutAll")}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      {confirmOpen ? (
        <Suspense fallback={null}>
          <LogoutAllDialog
            onOpenChange={setConfirmOpen}
            loading={logoutAll.isPending}
            onConfirm={() => logoutAll.mutate(undefined, { onSuccess: goToLogin })}
          />
        </Suspense>
      ) : null}
    </>
  );
}

import { useLogoutAllMutation, useLogoutMutation } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@ceiba/ui";
import { LogOut, ShieldOff } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router";
import { useMe } from "../me/me-provider";

const initials = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]!.toUpperCase())
    .join("");

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
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="rounded-full bg-secondary text-sm font-semibold"
            aria-label={t("shell:userMenu", { name: principal.name })}
          >
            <span aria-hidden="true">{initials(principal.name)}</span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-64">
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

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent closeLabel={t("common:close")}>
          <DialogHeader>
            <DialogTitle>{t("auth:logoutAllDialog.title")}</DialogTitle>
            <DialogDescription>{t("auth:logoutAllDialog.description")}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmOpen(false)}>
              {t("common:cancel")}
            </Button>
            <Button
              variant="destructive"
              loading={logoutAll.isPending}
              onClick={() => logoutAll.mutate(undefined, { onSuccess: goToLogin })}
            >
              {t("auth:logoutAllDialog.confirm")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

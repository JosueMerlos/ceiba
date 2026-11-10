import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@ceiba/ui";

interface LogoutAllDialogProps {
  onOpenChange(open: boolean): void;
  onConfirm(): void;
  loading: boolean;
}

/** Confirmación de «cerrar sesión en todos los dispositivos». Se monta abierto y se cierra desmontándolo. */
export default function LogoutAllDialog({
  onOpenChange,
  onConfirm,
  loading,
}: LogoutAllDialogProps) {
  const { t } = useTranslation(["auth", "common"]);
  return (
    <Dialog open onOpenChange={onOpenChange}>
      <DialogContent closeLabel={t("common:close")}>
        <DialogHeader>
          <DialogTitle>{t("auth:logoutAllDialog.title")}</DialogTitle>
          <DialogDescription>{t("auth:logoutAllDialog.description")}</DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            {t("common:cancel")}
          </Button>
          <Button variant="destructive" loading={loading} onClick={onConfirm}>
            {t("auth:logoutAllDialog.confirm")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

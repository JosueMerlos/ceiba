import { useTranslation } from "@ceiba/i18n";
import { ContextPanel } from "@ceiba/ui";
import type { ReactNode } from "react";
import { AsidePortal } from "../shell/aside-slot";

/** The side panel of the customer screens, in the shell's aside slot. Mount it only while it is open. */
export function CustomerAside({
  title,
  onClose,
  children,
}: {
  title: ReactNode;
  onClose(): void;
  children: ReactNode;
}) {
  const { t } = useTranslation("common");
  return (
    <AsidePortal>
      <ContextPanel
        id="customer-panel"
        open
        onOpenChange={(open) => {
          if (!open) onClose();
        }}
        title={title}
        closeLabel={t("close")}
      >
        {children}
      </ContextPanel>
    </AsidePortal>
  );
}

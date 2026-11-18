import { useTranslation } from "@ceiba/i18n";
import { ContextPanel } from "@ceiba/ui";
import type { ReactNode } from "react";
import { AsidePortal } from "../../../platform/shell/aside-slot";

/** The context panel of a catalog page, rendered in the shell's aside slot. Mount it only while it is open. */
export function CatalogAside({
  id,
  title,
  onClose,
  footer,
  children,
}: {
  id: string;
  title: ReactNode;
  onClose(): void;
  footer?: ReactNode;
  children: ReactNode;
}) {
  const { t } = useTranslation("appointments");
  return (
    <AsidePortal>
      <ContextPanel
        id={id}
        open
        onOpenChange={(open) => {
          if (!open) onClose();
        }}
        title={title}
        closeLabel={t("catalog.closePanel")}
        footer={footer}
      >
        {children}
      </ContextPanel>
    </AsidePortal>
  );
}

import { ContextPanel } from "@ceiba/ui";
import type { ComponentProps } from "react";
import { AsidePortal } from "../../../../platform/shell/aside-slot";

type AgendaSidePanelProps = Omit<ComponentProps<typeof ContextPanel>, "open" | "onOpenChange"> & {
  onClose(): void;
};

/** A panel of the agenda, in the shell's contextual slot. Mount it only while it is open. */
export function AgendaSidePanel({ onClose, ...panel }: AgendaSidePanelProps) {
  return (
    <AsidePortal>
      <ContextPanel
        {...panel}
        open
        onOpenChange={(open) => {
          if (!open) onClose();
        }}
      />
    </AsidePortal>
  );
}

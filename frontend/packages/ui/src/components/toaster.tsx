import type { ComponentProps } from "react";
import { Toaster as Sonner, toast } from "sonner";

// Avisos breves (shadcn/ui usa Sonner). Los colores salen de los tokens semánticos.
function Toaster(props: ComponentProps<typeof Sonner>) {
  return (
    <Sonner
      theme="light"
      position="bottom-right"
      style={
        {
          "--normal-bg": "var(--popover)",
          "--normal-text": "var(--popover-foreground)",
          "--normal-border": "var(--border)",
          "--border-radius": "var(--radius)",
        } as React.CSSProperties
      }
      {...props}
    />
  );
}

export { Toaster, toast };

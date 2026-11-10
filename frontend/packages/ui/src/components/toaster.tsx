import type { ComponentProps } from "react";
import { Toaster as Sonner, toast } from "sonner";

// Brief notices (shadcn/ui uses Sonner). Colors come from the semantic tokens.
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

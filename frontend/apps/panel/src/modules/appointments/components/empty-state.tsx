import { Button } from "@ceiba/ui";
import type { ReactNode } from "react";

interface EmptyStateProps {
  title: string;
  description: string;
  /** Rendered only when given: whoever uses the component decides, by permission, whether there is an action. */
  action?: { label: string; onClick(): void };
  children?: ReactNode;
}

/** An empty screen is an invitation: what is missing, why it matters and the one thing to do next. */
export function EmptyState({ title, description, action, children }: EmptyStateProps) {
  return (
    <section
      data-slot="empty-state"
      className="grid justify-items-center gap-3 rounded-xl border border-dashed bg-card px-6 py-14 text-center"
    >
      <h2 className="font-display text-xl font-semibold">{title}</h2>
      <p className="max-w-md text-muted-foreground">{description}</p>
      {children}
      {action ? (
        <Button type="button" onClick={action.onClick} className="mt-1">
          {action.label}
        </Button>
      ) : null}
    </section>
  );
}

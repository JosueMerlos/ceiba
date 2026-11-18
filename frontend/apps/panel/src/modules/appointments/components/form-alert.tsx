import type { ReactNode } from "react";

/** Form-level failure (403, 5xx, a 422 with no field of its own). Fields show their own messages. */
export function FormAlert({ children }: { children: ReactNode }) {
  if (!children) return null;
  return (
    <p
      role="alert"
      className="rounded-lg border border-destructive/30 bg-destructive/5 px-3.5 py-2.5 text-sm font-medium text-destructive"
    >
      {children}
    </p>
  );
}

/**
 * Stands in for a modal tab's form when there is nothing to send: the footer's button still has a target, and in a
 * creation flow submitting it just moves on.
 */
export function IdleForm({ id, onSubmit }: { id: string; onSubmit?(): void }) {
  return (
    <form
      id={id}
      hidden
      onSubmit={(event) => {
        event.preventDefault();
        onSubmit?.();
      }}
    />
  );
}

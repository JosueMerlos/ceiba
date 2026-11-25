import type { Branch } from "../api/catalog";
import type { OwnerReads, OwnerWrites } from "../api/owners";
import { ScheduleSection, TimeOffsSection } from "./owner-sections";

interface OwnerTabProps {
  /** Held by the modal, which shows their progress in the footer. */
  writes: OwnerWrites;
  onDirtyChange(dirty: boolean): void;
}

/**
 * The weekly hours of a professional or a resource in one branch, inside a modal. With `formId` the editor is the
 * modal's form and the footer saves it; without it the hours are only shown.
 */
export function OwnerScheduleTab({
  slots,
  writes,
  formId,
  onDirtyChange,
  onSaved,
}: OwnerTabProps & { slots: OwnerReads["schedule"]; formId?: string; onSaved?(): void }) {
  if (!formId) return <ScheduleSection slots={slots} />;
  return (
    <ScheduleSection
      slots={slots}
      save={writes.saveSchedule}
      formId={formId}
      onDirtyChange={onDirtyChange}
      onSaved={onSaved}
    />
  );
}

/** The absences of a professional or a resource in one branch: the footer adds the one typed in, removing is immediate. */
export function OwnerTimeOffsTab({
  timeOffs,
  branch,
  writes,
  formId,
  onDirtyChange,
  onAdded,
}: OwnerTabProps & {
  timeOffs: OwnerReads["timeOffs"];
  branch: Branch;
  formId: string;
  onAdded?(): void;
}) {
  return (
    <TimeOffsSection
      timeOffs={timeOffs}
      timeZone={branch.time_zone}
      canManage
      formId={formId}
      onDirtyChange={onDirtyChange}
      onCreate={async (values) => {
        await writes.createTimeOff.mutateAsync(values);
        onAdded?.();
      }}
      onDelete={(timeOff, options) => writes.deleteTimeOff.mutate(timeOff.id, options)}
    />
  );
}

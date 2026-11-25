import type { Branch } from "../api/catalog";
import type { OwnerApi, OwnerWrites } from "../api/owners";
import { ScheduleSection, TimeOffsSection } from "./owner-sections";

interface OwnerTabProps {
  api: OwnerApi;
  ownerId: string;
  branch: Branch;
  /** Held by the modal, which shows their progress in the footer. */
  writes: OwnerWrites;
  onDirtyChange(dirty: boolean): void;
}

/**
 * The weekly hours of a professional or a resource in one branch, inside a modal. With `formId` the editor is the
 * modal's form and the footer saves it; without it the hours are only shown.
 */
export function OwnerScheduleTab({
  api,
  ownerId,
  branch,
  writes,
  formId,
  onDirtyChange,
  onSaved,
}: OwnerTabProps & { formId?: string; onSaved?(): void }) {
  const slots = api.useSchedule(branch.id, ownerId);
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
  api,
  ownerId,
  branch,
  writes,
  formId,
  onDirtyChange,
  onAdded,
}: OwnerTabProps & { formId: string; onAdded?(): void }) {
  const timeOffs = api.useTimeOffs(branch.id, ownerId);
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

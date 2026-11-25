import { useTranslation } from "@ceiba/i18n";
import { toast } from "@ceiba/ui";
import type { UseQueryResult } from "@tanstack/react-query";
import { useId, useState, type ReactNode } from "react";
import { apiErrorMessages } from "../../../platform/forms/api-error-messages";
import { useCan } from "../../../platform/permissions/can";
import type { Branch } from "../api/catalog";
import type { OwnerApi, SaveSchedule } from "../api/owners";
import type { TimeOff, TimeOffInput, WeeklyScheduleSlot } from "../api/shared";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { TimeOffForm } from "./time-off-form";
import { TimeOffsList } from "./time-offs-list";
import { WeeklyScheduleEditor } from "./weekly-schedule-editor";

/** A titled block of a context panel; `region` + name makes it addressable for keyboard and screen-reader users. */
export function PanelSection({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: ReactNode;
}) {
  const headingId = useId();
  return (
    <section aria-labelledby={headingId} className="grid gap-3 border-t pt-4">
      <div className="grid gap-1">
        <h3 id={headingId} className="font-display text-base font-semibold">
          {title}
        </h3>
        {description ? <p className="text-sm text-muted-foreground">{description}</p> : null}
      </div>
      {children}
    </section>
  );
}

interface ScheduleSectionProps {
  slots: UseQueryResult<{ data: WeeklyScheduleSlot[] }>;
  /** Absent: the hours are only shown. */
  save?: SaveSchedule;
  /** Inside a modal: the editor is that form and the modal's footer saves it. */
  formId?: string;
  onDirtyChange?(dirty: boolean): void;
  onSaved?(): void;
}

/** Weekly hours of one owner (professional or resource) in one branch: loads, edits and shows the server's 422. */
export function ScheduleSection({
  slots,
  save,
  formId,
  onDirtyChange,
  onSaved,
}: ScheduleSectionProps) {
  const { t } = useTranslation(["appointments", "common", "errors"]);
  const [serverMessages, setServerMessages] = useState<string[]>([]);

  return (
    <QueryBoundary query={slots}>
      {({ data: slotList }) => (
        <WeeklyScheduleEditor
          // Re-seed the editor when the saved week changes (its drafts are local state).
          key={slotList.map((slot) => slot.id).join(",")}
          slots={slotList}
          readOnly={save === undefined}
          saving={save?.isPending}
          serverMessages={serverMessages}
          formId={formId}
          onDirtyChange={onDirtyChange}
          onSave={(payload) =>
            save?.mutate(payload, {
              onSuccess: () => {
                setServerMessages([]);
                toast.success(t("catalog.schedule.saved"));
                onSaved?.();
              },
              onError: (error) => setServerMessages(apiErrorMessages(error, t)),
            })
          }
        />
      )}
    </QueryBoundary>
  );
}

type TimeOffsSectionProps = {
  timeOffs: UseQueryResult<{ data: TimeOff[] }>;
  timeZone: string;
} & (
  | { canManage: false }
  | {
      canManage: true;
      onCreate(values: TimeOffInput): Promise<unknown>;
      onDelete(timeOff: TimeOff, options: { onSuccess(): void }): void;
      /** The modal's form: the footer adds the absence. */
      formId: string;
      onDirtyChange?(dirty: boolean): void;
    }
);

/** Absences of one owner in one branch: list, add and remove, always in the branch's zone. */
export function TimeOffsSection(props: TimeOffsSectionProps) {
  const { t } = useTranslation("appointments");
  const write = props.canManage ? props : null;

  return (
    <QueryBoundary query={props.timeOffs}>
      {({ data: list }) => (
        <div className="grid gap-4">
          <TimeOffsList
            timeOffs={list}
            timeZone={props.timeZone}
            canManage={write !== null}
            onDelete={(timeOff) =>
              write?.onDelete(timeOff, {
                onSuccess: () => toast.success(t("catalog.timeOffs.removed")),
              })
            }
          />
          {write ? (
            <TimeOffForm
              timeZone={props.timeZone}
              formId={write.formId}
              onDirtyChange={write.onDirtyChange}
              onSubmit={async (values) => {
                await write.onCreate(values);
                toast.success(t("catalog.timeOffs.added"));
              }}
            />
          ) : null}
        </div>
      )}
    </QueryBoundary>
  );
}

/** What the user may read and change of an owner's hours and absences; the queries stay off for what they cannot read. */
export function useOwnerAccess() {
  const can = useCan();
  return {
    scheduleRead: can("appointments.schedule.read"),
    scheduleManage: can("appointments.schedule.manage"),
    timeOffRead: can("appointments.time_off.read"),
    timeOffManage: can("appointments.time_off.manage"),
  };
}

/** Hours and absences of an owner in one branch, read only; each section shows only if its read permission is held. */
export function OwnerBranchReadSections({
  api,
  ownerId,
  branch,
}: {
  api: OwnerApi;
  ownerId: string;
  branch: Branch;
}) {
  const { t } = useTranslation("appointments");
  const { scheduleRead, timeOffRead } = useOwnerAccess();
  const schedule = api.useSchedule(branch.id, ownerId, { enabled: scheduleRead });
  const timeOffs = api.useTimeOffs(branch.id, ownerId, { enabled: timeOffRead });
  return (
    <>
      {scheduleRead ? (
        <PanelSection title={t("catalog.schedule.title")}>
          <ScheduleSection slots={schedule} />
        </PanelSection>
      ) : null}
      {timeOffRead ? (
        <PanelSection title={t("catalog.timeOffs.title")}>
          <TimeOffsSection timeOffs={timeOffs} timeZone={branch.time_zone} canManage={false} />
        </PanelSection>
      ) : null}
    </>
  );
}

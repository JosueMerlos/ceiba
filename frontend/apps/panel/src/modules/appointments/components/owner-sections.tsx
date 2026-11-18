import { isApiError } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import { LoadingState, toast } from "@ceiba/ui";
import type { UseQueryResult } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { describeError } from "../../../platform/errors/global-errors";
import { useCan } from "../../../platform/permissions/can";
import type { Branch, WeeklyScheduleSlot } from "../api/catalog";
import type { TimeOff, TimeOffInput, WeeklyScheduleInput } from "../api/professionals";
import { QueryError } from "./query-error";
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
  const headingId = `section-${title.replace(/\W+/g, "-").toLowerCase()}`;
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

interface SaveSchedule {
  isPending: boolean;
  mutate(
    body: WeeklyScheduleInput,
    options: { onSuccess(): void; onError(error: unknown): void },
  ): void;
}

/** Weekly hours of one owner (professional or resource) in one branch: loads, edits and shows the server's 422. */
export function ScheduleSection({
  slots,
  save,
  canManage,
}: {
  slots: UseQueryResult<{ data: WeeklyScheduleSlot[] }>;
  save: SaveSchedule;
  canManage: boolean;
}) {
  const { t } = useTranslation(["appointments", "common", "errors"]);
  const [serverMessages, setServerMessages] = useState<string[]>([]);

  if (slots.isPending) return <LoadingState label={t("common:loading")} />;
  if (slots.isError) return <QueryError error={slots.error} onRetry={() => void slots.refetch()} />;
  return (
    <WeeklyScheduleEditor
      // Re-seed the editor when the saved week changes (its drafts are local state).
      key={slots.data.data.map((slot) => slot.id).join(",")}
      slots={slots.data.data}
      readOnly={!canManage}
      saving={save.isPending}
      serverMessages={serverMessages}
      onSave={(payload) =>
        save.mutate(payload, {
          onSuccess: () => {
            setServerMessages([]);
            toast.success(t("catalog.schedule.saved"));
          },
          onError: (error) =>
            setServerMessages(
              isApiError(error) && error.status === 422
                ? error.errors.length > 0
                  ? error.errors.map((item) => item.message)
                  : [error.title]
                : [describeError(error, t)],
            ),
        })
      }
    />
  );
}

/** Absences of one owner in one branch: list, add and remove, always in the branch's zone. */
export function TimeOffsSection({
  timeOffs,
  timeZone,
  canManage,
  onCreate,
  onDelete,
}: {
  timeOffs: UseQueryResult<{ data: TimeOff[] }>;
  timeZone: string;
  canManage: boolean;
  onCreate(values: TimeOffInput): Promise<unknown>;
  onDelete(timeOff: TimeOff, options: { onSuccess(): void }): void;
}) {
  const { t } = useTranslation(["appointments", "common"]);

  if (timeOffs.isPending) return <LoadingState label={t("common:loading")} />;
  if (timeOffs.isError) {
    return <QueryError error={timeOffs.error} onRetry={() => void timeOffs.refetch()} />;
  }
  return (
    <div className="grid gap-4">
      <TimeOffsList
        timeOffs={timeOffs.data.data}
        timeZone={timeZone}
        canManage={canManage}
        onDelete={(timeOff) =>
          onDelete(timeOff, { onSuccess: () => toast.success(t("catalog.timeOffs.removed")) })
        }
      />
      {canManage ? (
        <TimeOffForm
          timeZone={timeZone}
          onSubmit={async (values) => {
            await onCreate(values);
            toast.success(t("catalog.timeOffs.added"));
          }}
        />
      ) : null}
    </div>
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

export type OwnerAccess = ReturnType<typeof useOwnerAccess>;

interface OwnerBranchData {
  schedule: UseQueryResult<{ data: WeeklyScheduleSlot[] }>;
  saveSchedule: SaveSchedule;
  timeOffs: UseQueryResult<{ data: TimeOff[] }>;
  createTimeOff(values: TimeOffInput): Promise<unknown>;
  deleteTimeOff(timeOff: TimeOff, options: { onSuccess(): void }): void;
}

/** Hours and absences of an owner (professional or resource) in one branch; each section shows only if its read permission is held. */
export function OwnerBranchSections({
  branch,
  access,
  data,
}: {
  branch: Branch;
  access: OwnerAccess;
  data: OwnerBranchData;
}) {
  const { t } = useTranslation("appointments");
  return (
    <>
      {access.scheduleRead ? (
        <PanelSection
          title={t("catalog.schedule.title")}
          description={t("catalog.timeOffs.branchHint", {
            branch: branch.name,
            timeZone: branch.time_zone,
          })}
        >
          <ScheduleSection
            slots={data.schedule}
            save={data.saveSchedule}
            canManage={access.scheduleManage}
          />
        </PanelSection>
      ) : null}
      {access.timeOffRead ? (
        <PanelSection title={t("catalog.timeOffs.title")}>
          <TimeOffsSection
            timeOffs={data.timeOffs}
            timeZone={branch.time_zone}
            canManage={access.timeOffManage}
            onCreate={data.createTimeOff}
            onDelete={data.deleteTimeOff}
          />
        </PanelSection>
      ) : null}
    </>
  );
}

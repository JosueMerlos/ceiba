import { useTranslation } from "@ceiba/i18n";
import { toast } from "@ceiba/ui";
import { useState } from "react";
import { useCan } from "../../../platform/permissions/can";
import { useServicesQuery, type Branch } from "../api/catalog";
import {
  useCreateProfessionalTimeOff,
  useDeleteProfessionalTimeOff,
  useProfessionalAssignment,
  useProfessionalScheduleQuery,
  useProfessionalTimeOffsQuery,
  usePutProfessionalSchedule,
  usePutProfessionalServices,
  useUpdateProfessional,
  type Professional,
} from "../api/professionals";
import { AssignBranchDialog } from "../components/assign-branch-dialog";
import { OwnerBranchSections, PanelSection, useOwnerAccess } from "../components/owner-sections";
import { ProfessionalBranches } from "../components/professional-branches";
import { ProfessionalForm } from "../components/professional-form";
import { ProfessionalServices } from "../components/professional-services";
import { TimeOffsList } from "../components/time-offs-list";
import { DEFAULT_TIME_ZONE } from "../lib/time-zones";
import { useOrphanTimeOffs, type AssignConfirmation } from "../lib/use-orphan-time-offs";

interface ProfessionalPanelProps {
  professional: Professional;
  /** Branches the user can see: a branch manager receives only theirs. */
  branches: readonly Branch[];
  /** The branch hours and absences are edited in (context branch or the page's choice); null until one is chosen. */
  workingBranch: Branch | null;
}

/** The sections of one professional's context panel. Each one gates its own actions by permission. */
export function ProfessionalPanel({
  professional,
  branches,
  workingBranch,
}: ProfessionalPanelProps) {
  const { t } = useTranslation("appointments");
  const can = useCan();
  const canManage = can("appointments.professional.manage");
  const canAssign = can("appointments.professional.assign");

  const update = useUpdateProfessional();
  const putServices = usePutProfessionalServices();
  const assignment = useProfessionalAssignment();
  const services = useServicesQuery("active");
  const orphan = useOrphanTimeOffs(professional);
  // Without a chosen branch, the zone of the company's first branch; the default only while the company has none.
  const orphanTimeZone = workingBranch?.time_zone ?? branches[0]?.time_zone ?? DEFAULT_TIME_ZONE;
  const [confirming, setConfirming] = useState<AssignConfirmation | null>(null);

  const assign = (branch: Branch) =>
    assignment.mutate(
      { branchId: branch.id, professionalId: professional.id, assign: true },
      { onSuccess: () => toast.success(t("catalog.professionalBranches.assignedDone")) },
    );

  function requestAssign(branchId: string) {
    const branch = branches.find((item) => item.id === branchId);
    if (!branch) return;
    const confirmation = orphan.confirmationFor(branch);
    if (confirmation) setConfirming(confirmation);
    else assign(branch);
  }

  return (
    <>
      <ProfessionalForm
        key={`${professional.id}:${professional.updated_at}`}
        professional={professional}
        readOnly={!canManage}
        onSubmit={(values) => update.mutateAsync({ id: professional.id, body: values })}
      />

      <PanelSection title={t("catalog.professionalServices.title")}>
        {services.isSuccess ? (
          <ProfessionalServices
            key={`${professional.id}:${professional.service_ids.join(",")}`}
            services={services.data.data}
            selectedIds={professional.service_ids}
            canManage={canManage}
            onSave={async (serviceIds) => {
              await putServices.mutateAsync({ id: professional.id, serviceIds });
              toast.success(t("catalog.professionalServices.saved"));
            }}
          />
        ) : null}
      </PanelSection>

      <PanelSection title={t("catalog.professionalBranches.title")}>
        <ProfessionalBranches
          branches={branches}
          assignedIds={professional.branch_ids}
          canAssign={canAssign && !orphan.loading}
          onAssign={requestAssign}
          onUnassign={(branchId) =>
            assignment.mutate({ branchId, professionalId: professional.id, assign: false })
          }
        />
      </PanelSection>

      {orphan.visible ? (
        <PanelSection
          title={t("catalog.timeOffs.pendingTitle")}
          description={t("catalog.timeOffs.pendingDescription")}
        >
          <TimeOffsList
            timeOffs={orphan.timeOffs}
            timeZone={orphanTimeZone}
            canManage={orphan.canRemove}
            onDelete={orphan.remove}
          />
          <p className="mt-3 text-xs text-muted-foreground">
            {t("catalog.timeOffs.pendingZone", { zone: orphanTimeZone })}
          </p>
        </PanelSection>
      ) : null}

      {workingBranch ? (
        professional.branch_ids.includes(workingBranch.id) ? (
          <BranchSections professional={professional} branch={workingBranch} />
        ) : (
          <p className="border-t pt-4 text-sm text-muted-foreground">
            {t("catalog.timeOffs.needBranch", { branch: workingBranch.name })}
          </p>
        )
      ) : null}

      <AssignBranchDialog
        confirmation={confirming}
        onCancel={() => setConfirming(null)}
        onConfirm={({ branch }) => {
          assign(branch);
          setConfirming(null);
        }}
      />
    </>
  );
}

/** Hours and absences of the professional in one branch (they must be assigned to it, or the API answers 404). */
function BranchSections({ professional, branch }: { professional: Professional; branch: Branch }) {
  const access = useOwnerAccess();
  const schedule = useProfessionalScheduleQuery(branch.id, professional.id, {
    enabled: access.scheduleRead,
  });
  const saveSchedule = usePutProfessionalSchedule(branch.id, professional.id);
  const timeOffs = useProfessionalTimeOffsQuery(branch.id, professional.id, {
    enabled: access.timeOffRead,
  });
  const create = useCreateProfessionalTimeOff(branch.id, professional.id);
  const remove = useDeleteProfessionalTimeOff(branch.id, professional.id);

  return (
    <OwnerBranchSections
      branch={branch}
      access={access}
      data={{
        schedule,
        saveSchedule,
        timeOffs,
        createTimeOff: (values) => create.mutateAsync(values),
        deleteTimeOff: (timeOff, options) => remove.mutate(timeOff.id, options),
      }}
    />
  );
}

import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  toast,
} from "@ceiba/ui";
import { useState } from "react";
import { useMe } from "../../../platform/me/me-provider";
import { useCan } from "../../../platform/permissions/can";
import { useServicesQuery, type Branch } from "../api/catalog";
import {
  useCompanyTimeOffsQuery,
  useCreateProfessionalTimeOff,
  useDeleteCompanyTimeOff,
  useDeleteProfessionalTimeOff,
  useProfessionalAssignment,
  useProfessionalScheduleQuery,
  useProfessionalTimeOffsQuery,
  usePutProfessionalSchedule,
  usePutProfessionalServices,
  useUpdateProfessional,
  type Professional,
} from "../api/professionals";
import { OwnerBranchSections, PanelSection, useOwnerAccess } from "../components/owner-sections";
import { ProfessionalBranches } from "../components/professional-branches";
import { ProfessionalForm } from "../components/professional-form";
import { ProfessionalServices } from "../components/professional-services";
import { TimeOffsList } from "../components/time-offs-list";
import { DEFAULT_TIME_ZONE } from "../lib/time-zones";

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
  const { t } = useTranslation(["appointments", "common"]);
  const { context } = useMe();
  const can = useCan();
  const canManage = can("appointments.professional.manage");
  const canAssign = can("appointments.professional.assign");
  const canTimeOffRead = can("appointments.time_off.read");
  const canTimeOffManage = can("appointments.time_off.manage");

  const update = useUpdateProfessional();
  const putServices = usePutProfessionalServices();
  const assignment = useProfessionalAssignment();
  const services = useServicesQuery("active");

  // Someone with no branch has absences no branch route reaches. Only a user holding the permission at COMPANY scope
  // (no branch in the context) may read them; for anyone else the section stays out and the notice is generic.
  const orphan = professional.branch_ids.length === 0;
  const companyScope = !context.branch && canTimeOffRead;
  const pending = useCompanyTimeOffsQuery(professional.id, { enabled: orphan && companyScope });
  const removePending = useDeleteCompanyTimeOff(professional.id);

  const [confirming, setConfirming] = useState<{ branch: Branch; count: number | null } | null>(
    null,
  );

  const assign = (branch: Branch) =>
    assignment.mutate(
      { branchId: branch.id, professionalId: professional.id, assign: true },
      { onSuccess: () => toast.success(t("catalog.professionalBranches.assignedDone")) },
    );

  function requestAssign(branchId: string) {
    const branch = branches.find((item) => item.id === branchId);
    if (!branch) return;
    if (!orphan) return assign(branch);
    if (pending.isSuccess) {
      const count = pending.data.data.length;
      return count === 0 ? assign(branch) : setConfirming({ branch, count });
    }
    setConfirming({ branch, count: null });
  }

  const assignedHere = workingBranch !== null && professional.branch_ids.includes(workingBranch.id);

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
          // While the company absences load, assigning waits: the confirmation needs to know whether there are any.
          canAssign={canAssign && !pending.isLoading}
          onAssign={requestAssign}
          onUnassign={(branchId) =>
            assignment.mutate({ branchId, professionalId: professional.id, assign: false })
          }
        />
      </PanelSection>

      {orphan && companyScope && pending.isSuccess && pending.data.data.length > 0 ? (
        <PanelSection
          title={t("catalog.timeOffs.pendingTitle")}
          description={t("catalog.timeOffs.pendingDescription")}
        >
          <TimeOffsList
            timeOffs={pending.data.data}
            timeZone={workingBranch?.time_zone ?? DEFAULT_TIME_ZONE}
            canManage={canTimeOffManage}
            onDelete={(timeOff) =>
              removePending.mutate(timeOff.id, {
                onSuccess: () => toast.success(t("catalog.timeOffs.removed")),
              })
            }
          />
        </PanelSection>
      ) : null}

      {workingBranch && !assignedHere ? (
        <p className="border-t pt-4 text-sm text-muted-foreground">
          {t("catalog.timeOffs.needBranch", { branch: workingBranch.name })}
        </p>
      ) : null}
      {workingBranch && assignedHere ? (
        <BranchSections professional={professional} branch={workingBranch} />
      ) : null}

      <Dialog
        open={confirming !== null}
        onOpenChange={(open) => (open ? undefined : setConfirming(null))}
      >
        <DialogContent closeLabel={t("common:close")}>
          <DialogHeader>
            <DialogTitle>
              {t("catalog.professionalBranches.confirm.title", {
                branch: confirming?.branch.name ?? "",
              })}
            </DialogTitle>
            <DialogDescription>
              {confirming?.count == null
                ? t("catalog.professionalBranches.confirm.generic", {
                    branch: confirming?.branch.name ?? "",
                  })
                : t("catalog.professionalBranches.confirm.description", {
                    count: confirming.count,
                    branch: confirming.branch.name,
                  })}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setConfirming(null)}>
              {t("common:cancel")}
            </Button>
            <Button
              type="button"
              onClick={() => {
                if (confirming) assign(confirming.branch);
                setConfirming(null);
              }}
            >
              {t("catalog.professionalBranches.confirm.action")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
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

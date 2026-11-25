import { useTranslation } from "@ceiba/i18n";
import { FormDialog, toast } from "@ceiba/ui";
import { useId, useState } from "react";
import { useCan } from "../../../platform/permissions/can";
import type { Branch } from "../api/catalog";
import {
  useCreateResource,
  useCreateResourceTimeOff,
  useDeleteResourceTimeOff,
  usePutResourceSchedule,
  useResourceScheduleQuery,
  useResourceTimeOffsQuery,
  useUpdateResource,
  type Resource,
} from "../api/resources";
import { ScheduleSection, TimeOffsSection, useOwnerAccess } from "./owner-sections";
import { ResourceForm, type ResourceFormValues } from "./resource-form";

type Section = "data" | "schedule" | "timeOffs";

/** The sections of a resource the user can write, in the order the modal shows them. */
export function useResourceSections(): Section[] {
  const can = useCan();
  const access = useOwnerAccess();
  return [
    ...(can("appointments.resource.manage") ? (["data"] as const) : []),
    ...(access.scheduleManage ? (["schedule"] as const) : []),
    ...(access.timeOffManage ? (["timeOffs"] as const) : []),
  ];
}

interface ResourceDialogProps {
  branch: Branch;
  open: boolean;
  onOpenChange(open: boolean): void;
}

/**
 * Creating a resource: step 1 (data) creates it, step 2 (weekly hours) is optional. Going back and continuing again
 * updates the resource already created, never a second one.
 */
export function NewResourceDialog({ branch, open, onOpenChange }: ResourceDialogProps) {
  const { t } = useTranslation(["appointments", "common"]);
  const access = useOwnerAccess();
  const dataFormId = useId();
  const scheduleFormId = useId();
  const [step, setStep] = useState<"data" | "schedule">("data");
  const [created, setCreated] = useState<Resource | null>(null);
  const [dataDirty, setDataDirty] = useState(false);

  const create = useCreateResource(branch.id);
  const update = useUpdateResource(branch.id);
  const schedule = useResourceScheduleQuery(branch.id, created?.id ?? "", {
    enabled: created !== null && access.scheduleRead,
  });
  const saveSchedule = usePutResourceSchedule(branch.id, created?.id ?? "");

  const withSchedule = access.scheduleManage;
  const steps = [
    { id: "data", label: t("catalog.resources.sections.data") },
    ...(withSchedule
      ? [{ id: "schedule", label: t("catalog.resources.sections.schedule"), optional: true }]
      : []),
  ];

  const close = () => onOpenChange(false);

  async function saveData(values: ResourceFormValues) {
    if (!created) {
      const result = await create.mutateAsync(values);
      setCreated(result.data);
    } else if (dataDirty) {
      const result = await update.mutateAsync({ id: created.id, body: values });
      setCreated(result.data);
    }
    if (withSchedule) setStep("schedule");
    else close();
  }

  return (
    <FormDialog
      open={open}
      onOpenChange={onOpenChange}
      title={created ? created.name : t("catalog.resources.panelNewTitle")}
      closeLabel={t("common:close")}
      steps={steps}
      step={step}
      stepsLabel={t("common:formDialog.steps")}
      onBack={() => setStep("data")}
      onSkip={close}
      formId={step === "data" ? dataFormId : scheduleFormId}
      backLabel={t("common:formDialog.back")}
      skipLabel={t("common:formDialog.skip")}
      continueLabel={t("common:formDialog.continue")}
      finishLabel={t("common:formDialog.finish")}
      pending={create.isPending || update.isPending || saveSchedule.isPending}
    >
      {step === "data" ? (
        <ResourceForm
          id={dataFormId}
          resource={created ?? undefined}
          onSubmit={saveData}
          onDirtyChange={setDataDirty}
        />
      ) : (
        <ScheduleSection
          slots={schedule}
          save={saveSchedule}
          canManage
          formId={scheduleFormId}
          onSaved={close}
        />
      )}
    </FormDialog>
  );
}

/** Editing a resource: one tab per section the user can write, each with the footer's single save. */
export function EditResourceDialog({
  branch,
  resource,
  open,
  onOpenChange,
}: ResourceDialogProps & { resource: Resource }) {
  const { t } = useTranslation(["appointments", "common"]);
  const access = useOwnerAccess();
  const sections = useResourceSections();
  const formId = useId();
  const [tab, setTab] = useState<Section>(sections[0] ?? "data");
  const [dirty, setDirty] = useState(false);

  const update = useUpdateResource(branch.id);
  const schedule = useResourceScheduleQuery(branch.id, resource.id, {
    enabled: tab === "schedule",
  });
  const saveSchedule = usePutResourceSchedule(branch.id, resource.id);
  const timeOffs = useResourceTimeOffsQuery(branch.id, resource.id, {
    enabled: tab === "timeOffs",
  });
  const createTimeOff = useCreateResourceTimeOff(branch.id, resource.id);
  const removeTimeOff = useDeleteResourceTimeOff(branch.id, resource.id);

  async function saveData(values: ResourceFormValues) {
    await update.mutateAsync({ id: resource.id, body: values });
    toast.success(t("catalog.resources.updated"));
  }

  const saveLabel = {
    data: t("catalog.resourceForm.save"),
    schedule: t("catalog.schedule.save"),
    timeOffs: t("catalog.timeOffForm.create"),
  }[tab];
  const pending = {
    data: update.isPending,
    schedule: saveSchedule.isPending,
    timeOffs: createTimeOff.isPending,
  }[tab];

  return (
    <FormDialog
      open={open}
      onOpenChange={onOpenChange}
      title={resource.name}
      closeLabel={t("common:close")}
      tabs={sections.map((id) => ({ id, label: t(`catalog.resources.sections.${id}`) }))}
      tab={tab}
      onTabChange={(next) => {
        setTab(next as Section);
        setDirty(false);
      }}
      tabsLabel={t("common:formDialog.sections")}
      dirty={dirty}
      formId={formId}
      saveLabel={saveLabel}
      pending={pending}
      confirmTitle={t("common:formDialog.discardTitle")}
      confirmDescription={t("common:formDialog.discardDescription")}
      discardLabel={t("common:formDialog.discard")}
      keepLabel={t("common:formDialog.keepEditing")}
    >
      {tab === "data" ? (
        <ResourceForm
          id={formId}
          resource={resource}
          onSubmit={saveData}
          onDirtyChange={setDirty}
        />
      ) : null}
      {tab === "schedule" ? (
        <ScheduleSection
          slots={schedule}
          save={saveSchedule}
          canManage
          formId={formId}
          onDirtyChange={setDirty}
        />
      ) : null}
      {tab === "timeOffs" ? (
        <TimeOffsSection
          timeOffs={timeOffs}
          timeZone={branch.time_zone}
          canManage={access.timeOffManage}
          formId={formId}
          onDirtyChange={setDirty}
          onCreate={(values) => createTimeOff.mutateAsync(values)}
          onDelete={(timeOff, options) => removeTimeOff.mutate(timeOff.id, options)}
        />
      ) : null}
    </FormDialog>
  );
}

import { useTranslation } from "@ceiba/i18n";
import { FormDialog, toast } from "@ceiba/ui";
import { useId, useState } from "react";
import { useCan } from "../../../platform/permissions/can";
import { useFormDialogLabels } from "../../../platform/ui/use-form-dialog-labels";
import type { Branch } from "../api/catalog";
import { resourceOwnerApi, useOwnerReads, useOwnerWrites } from "../api/owners";
import { useCreateResource, useUpdateResource, type Resource } from "../api/resources";
import { createOrUpdate, useCreationSteps } from "../lib/use-creation-steps";
import { useOwnerAccess } from "./owner-sections";
import { OwnerScheduleTab, OwnerTimeOffsTab } from "./owner-tabs";
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
  onOpenChange(open: boolean): void;
}

/**
 * Creating a resource: the data creates it and the weekly hours follow as an optional step (absences are added later,
 * when editing). Going back and continuing again updates the resource already created, never a second one.
 */
export function NewResourceDialog({ branch, onOpenChange }: ResourceDialogProps) {
  const { t } = useTranslation(["appointments", "common"]);
  const labels = useFormDialogLabels();
  const steps = useResourceSections().filter((id) => id !== "timeOffs");
  const formId = useId();
  const flow = useCreationSteps<Section, Resource>(steps, () => onOpenChange(false));
  const { step, created } = flow;

  const create = useCreateResource(branch.id);
  const update = useUpdateResource(branch.id);
  const reads = useOwnerReads(resourceOwnerApi, branch.id, created?.id ?? "", {
    schedule: created !== null && step === "schedule",
    timeOffs: false,
  });
  const writes = useOwnerWrites(resourceOwnerApi, branch.id, created?.id ?? "");

  const saveData = (values: ResourceFormValues) =>
    createOrUpdate(flow, {
      create: () => create.mutateAsync(values),
      update: (id) => update.mutateAsync({ id, body: values }),
    });

  return (
    <FormDialog
      open
      onOpenChange={onOpenChange}
      {...labels.steps}
      title={created ? created.name : t("catalog.resources.panelNewTitle")}
      steps={steps.map((id) => ({
        id,
        label: t(`catalog.resources.sections.${id}`),
        optional: id !== "data",
      }))}
      step={step}
      onBack={flow.back}
      onSkip={flow.next}
      formId={formId}
      dirty={flow.mustSubmit}
      onContinue={flow.next}
      pending={step === "data" ? create.isPending || update.isPending : writes.pending.schedule}
    >
      {step === "data" ? (
        <ResourceForm
          id={formId}
          resource={created ?? undefined}
          onSubmit={saveData}
          onDirtyChange={flow.setDirty}
        />
      ) : null}
      {created && step === "schedule" ? (
        <OwnerScheduleTab
          slots={reads.schedule}
          writes={writes}
          formId={formId}
          onDirtyChange={flow.setDirty}
          onSaved={flow.next}
        />
      ) : null}
    </FormDialog>
  );
}

/** Editing a resource: one tab per section the user can write, each with the footer's single save. */
export function EditResourceDialog({
  branch,
  resource,
  onOpenChange,
}: ResourceDialogProps & { resource: Resource }) {
  const { t } = useTranslation(["appointments", "common"]);
  const labels = useFormDialogLabels();
  const sections = useResourceSections();
  const formId = useId();
  const [tab, setTab] = useState<Section>(sections[0] ?? "data");
  const [dirty, setDirty] = useState(false);

  const update = useUpdateResource(branch.id);
  const reads = useOwnerReads(resourceOwnerApi, branch.id, resource.id, {
    schedule: tab === "schedule",
    timeOffs: tab === "timeOffs",
  });
  const writes = useOwnerWrites(resourceOwnerApi, branch.id, resource.id);

  async function saveData(values: ResourceFormValues) {
    await update.mutateAsync({ id: resource.id, body: values });
    toast.success(t("catalog.resources.updated"));
  }

  // Hours and absences have a form only once their data loaded: until then the footer has nothing to submit.
  const footer = {
    data: { editable: true, label: t("catalog.resourceForm.save"), pending: update.isPending },
    schedule: {
      editable: reads.schedule.isSuccess,
      label: t("catalog.schedule.save"),
      pending: writes.pending.schedule,
    },
    timeOffs: {
      editable: reads.timeOffs.isSuccess,
      label: t("catalog.timeOffForm.create"),
      pending: writes.pending.timeOffs,
    },
  }[tab];

  return (
    <FormDialog
      open
      onOpenChange={onOpenChange}
      {...labels.tabs}
      title={resource.name}
      tabs={sections.map((id) => ({ id, label: t(`catalog.resources.sections.${id}`) }))}
      tab={tab}
      onTabChange={(next) => {
        setTab(next as Section);
        setDirty(false);
      }}
      dirty={dirty}
      formId={footer.editable ? formId : undefined}
      saveLabel={footer.label}
      pending={footer.pending}
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
        <OwnerScheduleTab
          slots={reads.schedule}
          writes={writes}
          formId={formId}
          onDirtyChange={setDirty}
        />
      ) : null}
      {tab === "timeOffs" ? (
        <OwnerTimeOffsTab
          timeOffs={reads.timeOffs}
          branch={branch}
          writes={writes}
          formId={formId}
          onDirtyChange={setDirty}
        />
      ) : null}
    </FormDialog>
  );
}

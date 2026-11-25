import { useTranslation } from "@ceiba/i18n";
import { FormDialog, toast } from "@ceiba/ui";
import type { UseQueryResult } from "@tanstack/react-query";
import { useId, useState } from "react";
import { useCan } from "../../../platform/permissions/can";
import { QueryBoundary } from "../../../platform/ui/query-boundary";
import { useFormDialogLabels } from "../../../platform/ui/use-form-dialog-labels";
import { useEveryActiveServiceQuery, type Branch, type Service } from "../api/catalog";
import {
  useCreateProfessional,
  useProfessionalQuery,
  useProfessionalsQuery,
  usePutProfessionalServices,
  useUpdateProfessional,
  type Professional,
  type ProfessionalDetail,
} from "../api/professionals";
import { createOrUpdate, useCreationSteps } from "../lib/use-creation-steps";
import { useOwnerAccess } from "./owner-sections";
import { useProfessionalBranchTab } from "./professional-branch-tab";
import { ProfessionalForm, type ProfessionalFormValues } from "./professional-form";
import { ProfessionalScheduleTab } from "./professional-schedule-tab";
import { ProfessionalTimeOffsTab } from "./professional-time-offs-tab";
import { ServicePicker } from "./service-picker";

type Section = "profile" | "services" | "branches" | "timeOffs";

/** The sections of a professional the user can write, in the order the modal shows them. */
export function useProfessionalSections(): Section[] {
  const can = useCan();
  const access = useOwnerAccess();
  const manage = can("appointments.professional.manage");
  return [
    ...(manage ? (["profile", "services"] as const) : []),
    ...(can("appointments.professional.assign") || access.scheduleManage
      ? (["branches"] as const)
      : []),
    ...(access.timeOffManage ? (["timeOffs"] as const) : []),
  ];
}

/** Which of the branch tab's queries the section on screen needs. */
const shownOwnerSection = (section: Section) =>
  section === "branches" ? "schedule" : section === "timeOffs" ? "timeOffs" : null;

interface ProfessionalDialogProps {
  /** Branches the user can see: a branch manager receives only theirs. */
  branches: readonly Branch[];
  onOpenChange(open: boolean): void;
}

/**
 * Creating a professional: the profile creates them, and services, branch and hours, and absences follow as optional
 * steps. Going back to the profile and continuing updates the professional already created, never a second one.
 */
export function NewProfessionalDialog({ branches, onOpenChange }: ProfessionalDialogProps) {
  const { t } = useTranslation(["appointments", "common"]);
  const labels = useFormDialogLabels();
  const steps = useProfessionalSections();
  const formId = useId();
  const flow = useCreationSteps<Section, ProfessionalDetail>(steps, () => onOpenChange(false));
  const { step, index, created } = flow;

  const create = useCreateProfessional();
  const update = useUpdateProfessional();
  const putServices = usePutProfessionalServices();
  const services = useEveryActiveServiceQuery({ enabled: step === "services" });
  const list = useProfessionalsQuery();
  // Assigning a branch refreshes the list: the steps after the profile read the professional from there.
  const live = list.data?.data.find((item) => item.id === created?.id) ?? created;
  const branchTab = useProfessionalBranchTab(live, branches, shownOwnerSection(step));

  const saveProfile = (values: ProfessionalFormValues) =>
    createOrUpdate(flow, {
      create: () => create.mutateAsync(values),
      update: (id) => update.mutateAsync({ id, body: values }),
    });

  async function saveServices(serviceIds: string[]) {
    if (!created) return;
    await putServices.mutateAsync({ id: created.id, serviceIds });
    flow.next();
  }

  const first = index === 0 && !created;
  const pending = {
    profile: create.isPending || update.isPending,
    services: putServices.isPending,
    branches: branchTab.writes.pending.schedule,
    timeOffs: branchTab.writes.pending.timeOffs,
  }[step];
  const tabProps = { branches, branchTab, dirty: flow.dirty, formId, onDirtyChange: flow.setDirty };

  return (
    <FormDialog
      open
      onOpenChange={onOpenChange}
      {...labels.steps}
      title={created ? created.display_name : t("catalog.professionals.new")}
      steps={steps.map((id) => ({
        id,
        label: t(`catalog.professionals.sections.${id}`),
        optional: id !== "profile",
      }))}
      step={step}
      onBack={flow.back}
      onSkip={flow.next}
      formId={formId}
      dirty={flow.mustSubmit}
      onContinue={flow.next}
      continueLabel={
        first
          ? t("catalog.professionals.createAndContinue")
          : t("catalog.professionals.saveAndContinue")
      }
      pending={pending}
      note={
        first
          ? t("catalog.professionals.firstStepNote", { total: steps.length })
          : t("catalog.professionals.stepNote", { step: index + 1, total: steps.length })
      }
    >
      {step === "profile" ? (
        <ProfessionalForm
          id={formId}
          professional={created ?? undefined}
          withContact
          onSubmit={saveProfile}
          onDirtyChange={flow.setDirty}
        />
      ) : null}
      {live && step === "services" ? (
        <ServicesStep
          formId={formId}
          services={services}
          professional={live}
          onSubmit={saveServices}
          onDirtyChange={flow.setDirty}
        />
      ) : null}
      {live && step === "branches" ? (
        <ProfessionalScheduleTab professional={live} {...tabProps} onSaved={flow.next} />
      ) : null}
      {live && step === "timeOffs" ? (
        <ProfessionalTimeOffsTab professional={live} {...tabProps} onAdded={flow.next} />
      ) : null}
    </FormDialog>
  );
}

/** Editing a professional: one tab per section the user can write, each with the footer's single action. */
export function EditProfessionalDialog({
  professional,
  branches,
  onOpenChange,
}: ProfessionalDialogProps & { professional: Professional }) {
  const { t } = useTranslation(["appointments", "common"]);
  const labels = useFormDialogLabels();
  const sections = useProfessionalSections();
  const formId = useId();
  const [tab, setTab] = useState<Section>(sections[0] ?? "branches");
  const [dirty, setDirty] = useState(false);
  // The profile tab exists only for whoever manages professionals: the only ones who read or send the contact.
  const withContact = sections.includes("profile");

  const detail = useProfessionalQuery(professional.id, { enabled: withContact });
  const services = useEveryActiveServiceQuery({ enabled: tab === "services" });
  const update = useUpdateProfessional();
  const putServices = usePutProfessionalServices();
  const branchTab = useProfessionalBranchTab(professional, branches, shownOwnerSection(tab));

  async function saveProfile(values: ProfessionalFormValues) {
    const { data } = await update.mutateAsync({ id: professional.id, body: values });
    toast.success(t("catalog.professionals.updated"));
    return data;
  }

  async function saveServices(serviceIds: string[]) {
    await putServices.mutateAsync({ id: professional.id, serviceIds });
    toast.success(t("catalog.professionalServices.saved"));
  }

  const label = (id: Section) => t(`catalog.professionals.sections.${id}`);
  const footer = {
    // Without the loaded record there is no form for the footer to submit.
    profile: { editable: detail.isSuccess, pending: update.isPending },
    // With no active service the picker has nothing to change, so a save would send the same set back.
    services: {
      editable: services.isSuccess && services.data.length > 0,
      pending: putServices.isPending,
    },
    branches: { editable: branchTab.editable.schedule, pending: branchTab.writes.pending.schedule },
    timeOffs: { editable: branchTab.editable.timeOffs, pending: branchTab.writes.pending.timeOffs },
  }[tab];
  const tabProps = { professional, branches, branchTab, dirty, formId, onDirtyChange: setDirty };

  return (
    <FormDialog
      open
      onOpenChange={onOpenChange}
      {...labels.tabs}
      title={professional.display_name}
      tabs={sections.map((id) => ({ id, label: label(id) }))}
      tab={tab}
      onTabChange={(next) => {
        setTab(next as Section);
        setDirty(false);
      }}
      dirty={dirty}
      formId={footer.editable ? formId : undefined}
      saveLabel={tab === "timeOffs" ? t("catalog.timeOffForm.create") : labels.tabs.saveLabel}
      pending={footer.pending}
      note={t("common:formDialog.tabNote", { tab: label(tab) })}
    >
      {tab === "profile" ? (
        <QueryBoundary query={detail}>
          {({ data }) => (
            <ProfessionalForm
              id={formId}
              professional={data}
              withContact={withContact}
              onSubmit={saveProfile}
              onDirtyChange={setDirty}
            />
          )}
        </QueryBoundary>
      ) : null}
      {tab === "services" ? (
        <ServicesStep
          formId={formId}
          services={services}
          professional={professional}
          onSubmit={saveServices}
          onDirtyChange={setDirty}
        />
      ) : null}
      {tab === "branches" ? <ProfessionalScheduleTab {...tabProps} /> : null}
      {tab === "timeOffs" ? <ProfessionalTimeOffsTab {...tabProps} /> : null}
    </FormDialog>
  );
}

function ServicesStep({
  formId,
  services,
  professional,
  onSubmit,
  onDirtyChange,
}: {
  formId: string;
  services: UseQueryResult<Service[]>;
  professional: Professional;
  onSubmit(serviceIds: string[]): Promise<unknown>;
  onDirtyChange(dirty: boolean): void;
}) {
  return (
    <QueryBoundary query={services}>
      {(data) => (
        <ServicePicker
          id={formId}
          services={data}
          selectedIds={professional.service_ids}
          onSubmit={onSubmit}
          onDirtyChange={onDirtyChange}
        />
      )}
    </QueryBoundary>
  );
}

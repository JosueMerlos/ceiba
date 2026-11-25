import { useTranslation } from "@ceiba/i18n";
import { FormDialog, toast } from "@ceiba/ui";
import { useId, useState } from "react";
import { useCan } from "../../../platform/permissions/can";
import { useEveryActiveServiceQuery, type Branch } from "../api/catalog";
import {
  useCreateProfessional,
  useProfessionalQuery,
  useProfessionalsQuery,
  usePutProfessionalServices,
  useUpdateProfessional,
  type Professional,
  type ProfessionalDetail,
} from "../api/professionals";
import { useOwnerAccess } from "./owner-sections";
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
  const steps = useProfessionalSections();
  const formId = useId();
  const [step, setStep] = useState<Section>("profile");
  const [created, setCreated] = useState<ProfessionalDetail | null>(null);
  const [dirty, setDirty] = useState(false);

  const create = useCreateProfessional();
  const update = useUpdateProfessional();
  const putServices = usePutProfessionalServices();
  const list = useProfessionalsQuery();
  // Assigning a branch refreshes the list: the steps after the profile read the professional from there.
  const live = list.data?.data.find((item) => item.id === created?.id) ?? created;

  const index = steps.indexOf(step);
  const close = () => onOpenChange(false);
  const goTo = (next: Section | undefined) => {
    setDirty(false);
    if (next) setStep(next);
    else close();
  };
  const next = () => goTo(steps[index + 1]);

  async function saveProfile(values: ProfessionalFormValues) {
    if (!created) setCreated((await create.mutateAsync(values)).data);
    else if (dirty) setCreated((await update.mutateAsync({ id: created.id, body: values })).data);
    next();
  }

  async function saveServices(serviceIds: string[]) {
    if (created && dirty) await putServices.mutateAsync({ id: created.id, serviceIds });
    next();
  }

  const note =
    index === 0 && !created
      ? t("catalog.professionals.firstStepNote", { total: steps.length })
      : t("catalog.professionals.stepNote", { step: index + 1, total: steps.length });

  return (
    <FormDialog
      open
      onOpenChange={onOpenChange}
      title={created ? created.display_name : t("catalog.professionals.new")}
      closeLabel={t("common:close")}
      steps={steps.map((id) => ({
        id,
        label: t(`catalog.professionals.sections.${id}`),
        optional: id !== "profile",
      }))}
      step={step}
      stepsLabel={t("common:formDialog.steps")}
      onBack={() => goTo(steps[index - 1])}
      onSkip={next}
      formId={formId}
      backLabel={t("common:formDialog.back")}
      skipLabel={t("common:formDialog.skip")}
      continueLabel={
        index === 0 && !created
          ? t("catalog.professionals.createAndContinue")
          : t("catalog.professionals.saveAndContinue")
      }
      finishLabel={t("common:formDialog.finish")}
      pending={create.isPending || update.isPending || putServices.isPending}
      note={note}
    >
      {step === "profile" ? (
        <ProfessionalForm
          id={formId}
          professional={created ?? undefined}
          onSubmit={saveProfile}
          onDirtyChange={setDirty}
        />
      ) : null}
      {live && step === "services" ? (
        <ServicesStep
          formId={formId}
          professional={live}
          onSubmit={saveServices}
          onDirtyChange={setDirty}
        />
      ) : null}
      {live && step === "branches" ? (
        <ProfessionalScheduleTab
          professional={live}
          branches={branches}
          formId={formId}
          onDirtyChange={setDirty}
          skipClean
          onDone={next}
        />
      ) : null}
      {live && step === "timeOffs" ? (
        <ProfessionalTimeOffsTab
          professional={live}
          branches={branches}
          formId={formId}
          onDirtyChange={setDirty}
          skipClean
          onDone={close}
        />
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
  const sections = useProfessionalSections();
  const formId = useId();
  const [tab, setTab] = useState<Section>(sections[0] ?? "branches");
  const [dirty, setDirty] = useState(false);

  // The contact comes only from the company record, and only whoever manages professionals reads it.
  const detail = useProfessionalQuery(professional.id, { enabled: sections.includes("profile") });
  const update = useUpdateProfessional();
  const putServices = usePutProfessionalServices();

  async function saveProfile(values: ProfessionalFormValues) {
    await update.mutateAsync({ id: professional.id, body: values });
    toast.success(t("catalog.professionals.updated"));
  }

  async function saveServices(serviceIds: string[]) {
    await putServices.mutateAsync({ id: professional.id, serviceIds });
    toast.success(t("catalog.professionalServices.saved"));
  }

  const label = (id: Section) => t(`catalog.professionals.sections.${id}`);

  return (
    <FormDialog
      open
      onOpenChange={onOpenChange}
      title={professional.display_name}
      closeLabel={t("common:close")}
      tabs={sections.map((id) => ({ id, label: label(id) }))}
      tab={tab}
      onTabChange={(next) => {
        setTab(next as Section);
        setDirty(false);
      }}
      tabsLabel={t("common:formDialog.sections")}
      dirty={dirty}
      formId={formId}
      saveLabel={tab === "timeOffs" ? t("catalog.timeOffForm.create") : t("common:formDialog.save")}
      pending={update.isPending || putServices.isPending}
      note={t("common:formDialog.tabNote", { tab: label(tab) })}
      confirmTitle={t("common:formDialog.discardTitle")}
      confirmDescription={t("common:formDialog.discardDescription")}
      discardLabel={t("common:formDialog.discard")}
      keepLabel={t("common:formDialog.keepEditing")}
    >
      {tab === "profile" && detail.isSuccess ? (
        <ProfessionalForm
          id={formId}
          professional={detail.data.data}
          onSubmit={saveProfile}
          onDirtyChange={setDirty}
        />
      ) : null}
      {tab === "services" ? (
        <ServicesStep
          formId={formId}
          professional={professional}
          onSubmit={saveServices}
          onDirtyChange={setDirty}
        />
      ) : null}
      {tab === "branches" ? (
        <ProfessionalScheduleTab
          professional={professional}
          branches={branches}
          formId={formId}
          onDirtyChange={setDirty}
        />
      ) : null}
      {tab === "timeOffs" ? (
        <ProfessionalTimeOffsTab
          professional={professional}
          branches={branches}
          formId={formId}
          onDirtyChange={setDirty}
        />
      ) : null}
    </FormDialog>
  );
}

function ServicesStep({
  formId,
  professional,
  onSubmit,
  onDirtyChange,
}: {
  formId: string;
  professional: Professional;
  onSubmit(serviceIds: string[]): Promise<unknown>;
  onDirtyChange(dirty: boolean): void;
}) {
  const services = useEveryActiveServiceQuery();
  if (!services.isSuccess) return null;
  return (
    <ServicePicker
      id={formId}
      services={services.data}
      selectedIds={professional.service_ids}
      onSubmit={onSubmit}
      onDirtyChange={onDirtyChange}
    />
  );
}

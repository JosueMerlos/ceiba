import { useTranslation } from "@ceiba/i18n";

/**
 * The shared wording of FormDialog, grouped by mode so a dialog spreads only what its mode takes: `plain` for a
 * one-step modal, `steps` for a creation flow, `tabs` for editing, and `discard` for any other "discard changes?"
 * confirmation.
 */
export function useFormDialogLabels() {
  const { t } = useTranslation("common");
  const closeLabel = t("close");
  return {
    plain: { closeLabel },
    steps: {
      closeLabel,
      stepsLabel: t("formDialog.steps"),
      backLabel: t("formDialog.back"),
      skipLabel: t("formDialog.skip"),
      continueLabel: t("formDialog.continue"),
      finishLabel: t("formDialog.finish"),
    },
    tabs: {
      closeLabel,
      tabsLabel: t("formDialog.sections"),
      saveLabel: t("formDialog.save"),
      confirmTitle: t("formDialog.discardTitle"),
      confirmDescription: t("formDialog.discardDescription"),
      discardLabel: t("formDialog.discard"),
      keepLabel: t("formDialog.keepEditing"),
    },
    discard: {
      title: t("formDialog.discardTitle"),
      description: t("formDialog.discardDescription"),
      confirmLabel: t("formDialog.discard"),
      cancelLabel: t("formDialog.keepEditing"),
    },
  };
}

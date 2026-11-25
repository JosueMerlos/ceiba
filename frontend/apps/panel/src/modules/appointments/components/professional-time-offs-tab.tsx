import { useTranslation } from "@ceiba/i18n";
import { useContextBranch } from "../../../platform/context/use-context-branch";
import type { Branch } from "../api/catalog";
import { professionalOwnerApi } from "../api/owners";
import type { Professional } from "../api/professionals";
import { DEFAULT_TIME_ZONE } from "../lib/time-zones";
import { useOrphanTimeOffs } from "../lib/use-orphan-time-offs";
import { BranchSwitcher } from "./branch-switcher";
import { PanelSection } from "./owner-sections";
import { OwnerTimeOffsTab } from "./owner-tabs";
import type { ProfessionalBranchTab } from "./professional-branch-tab";
import { TimeOffsList } from "./time-offs-list";

interface ProfessionalTimeOffsTabProps {
  professional: Professional;
  /** Branches the user can see: a branch manager receives only theirs. */
  branches: readonly Branch[];
  branchTab: ProfessionalBranchTab;
  /** The modal's unsaved state: switching branch with an absence typed in asks first. */
  dirty: boolean;
  /** The modal footer's form: it adds the absence typed in for the branch on screen. */
  formId: string;
  onDirtyChange(dirty: boolean): void;
  onAdded?(): void;
}

/** Absences per assigned branch (added one at a time from the footer, removed at once) and those left with no branch. */
export function ProfessionalTimeOffsTab({
  professional,
  branches,
  branchTab,
  dirty,
  formId,
  onDirtyChange,
  onAdded,
}: ProfessionalTimeOffsTabProps) {
  const { t } = useTranslation("appointments");
  const { branch: contextBranch } = useContextBranch();
  const orphan = useOrphanTimeOffs(professional);
  const { active, assigned } = branchTab;
  // Without a branch the pending absences are shown in the zone of the context's branch, or the company's first.
  const orphanZone = contextBranch?.time_zone ?? branches[0]?.time_zone ?? DEFAULT_TIME_ZONE;

  return (
    <div className="grid gap-6">
      {orphan.visible ? (
        <PanelSection
          title={t("catalog.timeOffs.pendingTitle")}
          description={t("catalog.timeOffs.pendingDescription")}
        >
          <TimeOffsList
            timeOffs={orphan.timeOffs}
            timeZone={orphanZone}
            canManage={orphan.canRemove}
            onDelete={orphan.remove}
          />
          <p className="text-xs text-muted-foreground">
            {t("catalog.timeOffs.pendingZone", { zone: orphanZone })}
          </p>
        </PanelSection>
      ) : null}

      {active ? (
        <div className="grid gap-4">
          <BranchSwitcher
            label={t("catalog.timeOffs.title")}
            branches={assigned}
            value={active.id}
            dirty={dirty}
            onChange={(branchId) => {
              branchTab.choose(branchId);
              onDirtyChange(false);
            }}
          />
          <p className="text-sm text-muted-foreground">
            {t("catalog.timeOffs.branchHint", { branch: active.name, timeZone: active.time_zone })}
          </p>
          <OwnerTimeOffsTab
            key={active.id}
            api={professionalOwnerApi}
            ownerId={professional.id}
            branch={active}
            writes={branchTab.writes}
            formId={formId}
            onDirtyChange={onDirtyChange}
            onAdded={onAdded}
          />
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">{t("catalog.professionalBranches.none")}</p>
      )}
    </div>
  );
}

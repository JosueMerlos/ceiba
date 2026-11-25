import { useTranslation } from "@ceiba/i18n";
import { Badge } from "@ceiba/ui";
import type { ReactNode } from "react";
import { useServicesQuery, type Branch } from "../api/catalog";
import {
  useProfessionalScheduleQuery,
  useProfessionalTimeOffsQuery,
  type Professional,
} from "../api/professionals";
import { CatalogDetailPanel } from "../components/catalog-detail-panel";
import { NO_WRITES, OwnerBranchSections, useOwnerAccess } from "../components/owner-sections";

interface ProfessionalDetailProps {
  professional: Professional;
  /** Id -> name of the branches the user can see. */
  branchNames: ReadonlyMap<string, string>;
  /** The context's branch: its hours and absences are shown when the professional works there. */
  workingBranch: Branch | null;
  onClose(): void;
  /** "Edit" for whoever can write some section of the professional; absent for whoever only reads. */
  footer?: ReactNode;
}

/** Floating read view of a professional; changes are made in the professional's modal, never here. */
export function ProfessionalDetail({
  professional,
  branchNames,
  workingBranch,
  onClose,
  footer,
}: ProfessionalDetailProps) {
  const { t } = useTranslation("appointments");
  const services = useServicesQuery("active");
  const serviceNames = (services.data?.data ?? [])
    .filter((service) => professional.service_ids.includes(service.id))
    .map((service) => service.name);
  const branches = professional.branch_ids.flatMap((id) => branchNames.get(id) ?? []);
  const none = <span className="text-muted-foreground">—</span>;

  return (
    <CatalogDetailPanel
      id="professional-panel"
      title={professional.display_name}
      onClose={onClose}
      footer={footer}
      details={[
        {
          label: t("catalog.professionals.columns.status"),
          value: (
            <Badge variant={professional.active ? "default" : "muted"}>
              {t(`catalog.professionals.status.${professional.active ? "active" : "paused"}`)}
            </Badge>
          ),
        },
        {
          label: t("catalog.professionals.columns.branches"),
          value: branches.length > 0 ? branches.join(", ") : t("catalog.professionals.noBranches"),
        },
        {
          label: t("catalog.professionals.columns.services"),
          value: serviceNames.length > 0 ? serviceNames.join(", ") : none,
        },
      ]}
    >
      {workingBranch && professional.branch_ids.includes(workingBranch.id) ? (
        <BranchSections professional={professional} branch={workingBranch} />
      ) : null}
    </CatalogDetailPanel>
  );
}

function BranchSections({ professional, branch }: { professional: Professional; branch: Branch }) {
  const access = useOwnerAccess();
  const schedule = useProfessionalScheduleQuery(branch.id, professional.id, {
    enabled: access.scheduleRead,
  });
  const timeOffs = useProfessionalTimeOffsQuery(branch.id, professional.id, {
    enabled: access.timeOffRead,
  });
  return (
    <OwnerBranchSections
      branch={branch}
      access={{ ...access, scheduleManage: false, timeOffManage: false }}
      data={{
        schedule,
        timeOffs,
        ...NO_WRITES,
      }}
    />
  );
}

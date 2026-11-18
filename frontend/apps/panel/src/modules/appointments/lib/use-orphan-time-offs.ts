import { useTranslation } from "@ceiba/i18n";
import { toast } from "@ceiba/ui";
import { useMe } from "../../../platform/me/me-provider";
import type { Branch } from "../api/catalog";
import {
  useCompanyTimeOffsQuery,
  useDeleteCompanyTimeOff,
  type Professional,
} from "../api/professionals";
import type { TimeOff } from "../api/shared";

/** What the user must confirm before assigning a branch; `count` is null when the absences could not be counted. */
export interface AssignConfirmation {
  branch: Branch;
  count: number | null;
}

/**
 * Absences of a professional with no branch: no branch route reaches them. Only a user holding the permission at COMPANY
 * scope may read them (a branch membership's keys do not count, even with no branch in the context); for anyone else the
 * section stays out and the notice is generic.
 */
export function useOrphanTimeOffs(professional: Professional) {
  const { t } = useTranslation("appointments");
  const { company_permissions: companyPermissions } = useMe();
  const orphan = professional.branch_ids.length === 0;
  const companyScope = companyPermissions.includes("appointments.time_off.read");
  const query = useCompanyTimeOffsQuery(professional.id, { enabled: orphan && companyScope });
  const removeMutation = useDeleteCompanyTimeOff(professional.id);
  const timeOffs: readonly TimeOff[] = query.data?.data ?? [];

  return {
    visible: orphan && companyScope && query.isSuccess && timeOffs.length > 0,
    timeOffs,
    /** Deleting needs the manage key at company scope too. */
    canRemove: companyPermissions.includes("appointments.time_off.manage"),
    /** While they load, assigning waits: the confirmation needs to know whether there are any. */
    loading: query.isLoading,
    remove: (timeOff: TimeOff) =>
      removeMutation.mutate(timeOff.id, {
        onSuccess: () => toast.success(t("catalog.timeOffs.removed")),
      }),
    /** `null` when the assignment can go ahead without asking. */
    confirmationFor(branch: Branch): AssignConfirmation | null {
      if (!orphan) return null;
      if (!query.isSuccess) return { branch, count: null };
      return timeOffs.length === 0 ? null : { branch, count: timeOffs.length };
    },
  };
}

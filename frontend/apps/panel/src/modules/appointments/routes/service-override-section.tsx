import { toast } from "@ceiba/ui";
import { useTranslation } from "@ceiba/i18n";
import { useCan } from "../../../platform/permissions/can";
import {
  useDeleteServiceOverride,
  usePutServiceOverride,
  useServiceOverridesQuery,
  type Branch,
  type Service,
} from "../api/catalog";
import { BranchOverrideFields } from "../components/branch-override-fields";

/** Container of the per-branch override of one service: reads the branch's overrides and wires the two writes. */
export function ServiceOverrideSection({ service, branch }: { service: Service; branch: Branch }) {
  const { t } = useTranslation("appointments");
  const can = useCan();
  const overrides = useServiceOverridesQuery(branch.id);
  const put = usePutServiceOverride(branch.id);
  const remove = useDeleteServiceOverride(branch.id);

  // Mirrors ServiceOverridePolicy: each field needs its own override permission; managing the service is not enough.
  const canEditDuration = can("appointments.service.override_duration");
  const canEditPrice = can("appointments.service.override_price");

  // Inputs are seeded from the loaded override: render only once it is known, and re-seed when it changes.
  if (!overrides.isSuccess) return null;
  const override = overrides.data.data.find((item) => item.service_id === service.id) ?? null;

  return (
    <BranchOverrideFields
      key={`${service.id}:${override?.updated_at ?? "none"}`}
      service={service}
      override={override}
      branchName={branch.name}
      canEditDuration={canEditDuration}
      canEditPrice={canEditPrice}
      onSubmit={(change) => put.mutateAsync({ serviceId: service.id, body: change })}
      onReset={async () => {
        await remove.mutateAsync(service.id);
        toast.success(t("catalog.override.resetDone"));
      }}
    />
  );
}

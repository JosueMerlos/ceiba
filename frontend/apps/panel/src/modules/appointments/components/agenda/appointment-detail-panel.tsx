import { formatDateTime, formatTime, useTranslation } from "@ceiba/i18n";
import { Button, toast } from "@ceiba/ui";
import { useState, type ReactNode } from "react";
import type { AgendaAppointment, AgendaProfessional } from "../../api/agenda";
import { useStatusAction } from "../../api/agenda-mutations";
import { useAppointmentDetail, useRescheduleChain } from "../../api/appointment-detail";
import type { Branch } from "../../api/catalog";
import { appointmentActions } from "../../lib/agenda-actions";
import { useAgendaPermissions } from "../../lib/agenda-permissions";
import { AgendaSidePanel } from "./agenda-side-panel";
import { CancelForm } from "./cancel-form";
import { NotesForm } from "./notes-form";
import { RescheduleForm } from "./reschedule-form";

type Mode = "view" | "cancel" | "reschedule";

interface AppointmentDetailPanelProps {
  id: string;
  branch: Branch;
  appointment: AgendaAppointment;
  professionals: readonly AgendaProfessional[];
  stepMinutes: number;
  professionalName(id: string): string;
  serviceLabel(appointment: AgendaAppointment): string;
  onClose(): void;
}

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-0.5">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd>{children}</dd>
    </div>
  );
}

export function AppointmentDetailPanel({
  id,
  branch,
  appointment,
  professionals,
  stepMinutes,
  professionalName,
  serviceLabel,
  onClose,
}: AppointmentDetailPanelProps) {
  const { t } = useTranslation("appointments");
  const { appointment: permissions } = useAgendaPermissions();
  const timeZone = branch.time_zone;
  const [mode, setMode] = useState<Mode>("view");
  const canEdit = permissions.manage || permissions.own;
  const actions = appointmentActions(appointment, permissions, new Date());
  const statusAction = useStatusAction(branch.id);
  const detail = useAppointmentDetail(branch.id, appointment.id, canEdit);
  const chain = useRescheduleChain(branch.id, appointment.rescheduled_from_id ?? null, canEdit);
  const backToView = () => setMode("view");

  return (
    <AgendaSidePanel
      id={id}
      onClose={onClose}
      title={appointment.customer_name ?? t("agenda.customerFallback")}
      closeLabel={t("agenda.form.close")}
    >
      <dl className="grid gap-3 text-sm">
        <Fact label={t("agenda.detail.status")}>{t(`agenda.status.${appointment.status}`)}</Fact>
        <Fact label={t("agenda.detail.when")}>
          {t("agenda.timeRange", {
            start: formatDateTime(appointment.starts_at, timeZone),
            end: formatTime(appointment.ends_at, timeZone),
          })}
        </Fact>
        <Fact label={t("agenda.detail.services")}>{serviceLabel(appointment)}</Fact>
        <Fact label={t("agenda.detail.professional")}>
          {professionalName(appointment.professional_id)}
        </Fact>
      </dl>

      {chain.data?.map((origin) => (
        <p key={origin.id} className="text-sm text-muted-foreground">
          {t("agenda.detail.movedFrom", { date: formatDateTime(origin.starts_at, timeZone) })}
        </p>
      ))}

      {mode === "view" ? (
        <div className="grid gap-2">
          {actions.status.map((action, index) => (
            <Button
              key={action}
              type="button"
              variant={index === 0 ? "default" : "outline"}
              loading={statusAction.isPending && statusAction.variables?.action === action}
              onClick={() =>
                statusAction.mutate(
                  { id: appointment.id, action },
                  { onSuccess: () => toast.success(t("agenda.detail.updated")) },
                )
              }
            >
              {t(`agenda.actions.${action}`)}
            </Button>
          ))}
          {actions.canReschedule ? (
            <Button type="button" variant="outline" onClick={() => setMode("reschedule")}>
              {t("agenda.actions.reschedule")}
            </Button>
          ) : null}
          {actions.canCancel ? (
            <Button type="button" variant="ghost" onClick={() => setMode("cancel")}>
              {t("agenda.actions.cancel")}
            </Button>
          ) : null}
        </div>
      ) : null}

      {mode === "cancel" ? (
        <CancelForm
          branchId={branch.id}
          appointmentId={appointment.id}
          onBack={backToView}
          onDone={onClose}
        />
      ) : null}
      {mode === "reschedule" ? (
        <RescheduleForm
          branch={branch}
          appointment={appointment}
          professionals={professionals}
          stepMinutes={stepMinutes}
          onBack={backToView}
          onDone={onClose}
        />
      ) : null}

      {detail.data ? (
        <NotesForm
          key={detail.data.data.lock_version}
          branchId={branch.id}
          appointmentId={appointment.id}
          notes={detail.data.data.notes ?? ""}
          lockVersion={detail.data.data.lock_version}
        />
      ) : null}
    </AgendaSidePanel>
  );
}

import { formatDateTime, formatTime, useTranslation } from "@ceiba/i18n";
import {
  Button,
  ContextPanel,
  Input,
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Textarea,
  toast,
} from "@ceiba/ui";
import { useId, useMemo, useState, type ReactNode } from "react";
import { apiErrorMessages } from "../../../../platform/forms/api-error-messages";
import { useCan } from "../../../../platform/permissions/can";
import { AsidePortal } from "../../../../platform/shell/aside-slot";
import type { AgendaAppointment, AgendaProfessional } from "../../api/agenda";
import {
  useAppointmentDetail,
  useAvailabilityQuery,
  useCancelAppointment,
  useRescheduleAppointment,
  useRescheduleChain,
  useStatusAction,
  useUpdateNotes,
  type CancellationReason,
} from "../../api/agenda-mutations";
import type { Branch } from "../../api/catalog";
import { availableActions, nearbyOwnStarts, type StatusAction } from "../../lib/agenda-actions";
import { toWallClock } from "../../lib/agenda-time";
import { createIdempotencyKeys } from "../../lib/idempotency-keys";
import { FormAlert } from "../form-alert";
import { SlotPicker } from "./slot-picker";

const CANCELLATION_REASONS: readonly CancellationReason[] = [
  "customer_request",
  "professional_unavailable",
  "business_decision",
  "other",
];

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
  const can = useCan();
  const timeZone = branch.time_zone;
  const [mode, setMode] = useState<Mode>("view");
  const manage = can("appointments.appointment.update");
  const own = can("appointments.appointment.update_own");
  const actions = availableActions(appointment, { manage, own }, new Date());
  const statusAction = useStatusAction(branch.id);
  const detail = useAppointmentDetail(branch.id, appointment.id, manage || own);
  const chain = useRescheduleChain(
    branch.id,
    appointment.rescheduled_from_id ?? null,
    manage || own,
  );

  const statusActions = actions.filter(
    (action): action is StatusAction => action !== "reschedule" && action !== "cancel",
  );

  return (
    <AsidePortal>
      <ContextPanel
        id={id}
        open
        onOpenChange={(open) => {
          if (!open) onClose();
        }}
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
            {statusActions.map((action) => (
              <Button
                key={action}
                type="button"
                variant={action === statusActions[0] ? "default" : "outline"}
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
            {actions.includes("reschedule") ? (
              <Button type="button" variant="outline" onClick={() => setMode("reschedule")}>
                {t("agenda.actions.reschedule")}
              </Button>
            ) : null}
            {actions.includes("cancel") ? (
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
            onBack={() => setMode("view")}
            onDone={onClose}
          />
        ) : null}
        {mode === "reschedule" ? (
          <RescheduleForm
            branch={branch}
            appointment={appointment}
            professionals={professionals}
            stepMinutes={stepMinutes}
            onBack={() => setMode("view")}
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
      </ContextPanel>
    </AsidePortal>
  );
}

function CancelForm({
  branchId,
  appointmentId,
  onBack,
  onDone,
}: {
  branchId: string;
  appointmentId: string;
  onBack(): void;
  onDone(): void;
}) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const cancel = useCancelAppointment(branchId);
  const [reason, setReason] = useState<CancellationReason | null>(null);
  return (
    <div className="grid gap-2">
      <div className="grid gap-1.5">
        <Label htmlFor={fieldId}>{t("agenda.detail.reason")}</Label>
        <Select
          value={reason ?? undefined}
          onValueChange={(value) => setReason(value as CancellationReason)}
        >
          <SelectTrigger id={fieldId}>
            <SelectValue placeholder={t("agenda.detail.reasonPlaceholder")} />
          </SelectTrigger>
          <SelectContent>
            {CANCELLATION_REASONS.map((item) => (
              <SelectItem key={item} value={item}>
                {t(`agenda.detail.reasons.${item}`)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <Button
        type="button"
        variant="destructive"
        disabled={!reason}
        loading={cancel.isPending}
        onClick={() => {
          if (!reason) return;
          cancel.mutate(
            { id: appointmentId, reason },
            {
              onSuccess: () => {
                toast.success(t("agenda.detail.cancelled"));
                onDone();
              },
            },
          );
        }}
      >
        {t("agenda.detail.confirmCancel")}
      </Button>
      <Button type="button" variant="ghost" onClick={onBack}>
        {t("agenda.detail.back")}
      </Button>
    </div>
  );
}

function RescheduleForm({
  branch,
  appointment,
  professionals,
  stepMinutes,
  onBack,
  onDone,
}: {
  branch: Branch;
  appointment: AgendaAppointment;
  professionals: readonly AgendaProfessional[];
  stepMinutes: number;
  onBack(): void;
  onDone(): void;
}) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const timeZone = branch.time_zone;
  const [keys] = useState(() => createIdempotencyKeys());
  const [professionalId, setProfessionalId] = useState(appointment.professional_id);
  const [day, setDay] = useState(toWallClock(appointment.starts_at, timeZone).slice(0, 10));
  const [startsAt, setStartsAt] = useState<string | null>(null);
  const move = useRescheduleAppointment(branch.id);
  const serviceIds = useMemo(
    () => appointment.services.map((line) => line.service_id),
    [appointment.services],
  );
  const availability = useAvailabilityQuery({
    branchId: branch.id,
    serviceIds,
    professionalId,
    date: day,
  });

  const starts = useMemo(() => {
    const free = (availability.data?.data ?? []).map((slot) => slot.starts_at);
    const own =
      professionalId === appointment.professional_id
        ? nearbyOwnStarts(appointment, stepMinutes).filter(
            (start) => toWallClock(start, timeZone).slice(0, 10) === day,
          )
        : [];
    const byInstant = new Map([...free, ...own].map((start) => [Date.parse(start), start]));
    return [...byInstant].sort(([a], [b]) => a - b).map(([, start]) => start);
  }, [availability.data, appointment, professionalId, stepMinutes, timeZone, day]);

  function submit() {
    if (!startsAt) return;
    const body = { starts_at: startsAt, professional_id: professionalId };
    move.mutate(
      { id: appointment.id, key: keys.keyFor(body), body },
      {
        onSuccess: () => {
          keys.settle();
          toast.success(t("agenda.detail.moved"));
          onDone();
        },
      },
    );
  }

  const invalid =
    move.error && "status" in move.error && move.error.status === 422
      ? apiErrorMessages(move.error, t).join(" ")
      : null;

  return (
    <div className="grid gap-3">
      <div className="grid gap-1.5">
        <Label htmlFor={`${fieldId}-professional`}>{t("agenda.form.professional")}</Label>
        <Select
          value={professionalId}
          onValueChange={(value) => {
            setProfessionalId(value);
            setStartsAt(null);
          }}
        >
          <SelectTrigger id={`${fieldId}-professional`}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {professionals.map((person) => (
              <SelectItem key={person.id} value={person.id}>
                {person.display_name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div className="grid gap-1.5">
        <Label htmlFor={`${fieldId}-date`}>{t("agenda.detail.newDate")}</Label>
        <Input
          id={`${fieldId}-date`}
          type="date"
          value={day}
          onChange={(event) => {
            if (event.target.value) setDay(event.target.value);
            setStartsAt(null);
          }}
        />
      </div>
      <SlotPicker
        starts={starts}
        value={startsAt}
        onChange={setStartsAt}
        timeZone={timeZone}
        isLoading={availability.isPending}
        failed={availability.isError}
      />
      {invalid ? <FormAlert>{invalid}</FormAlert> : null}
      <Button type="button" disabled={!startsAt} loading={move.isPending} onClick={submit}>
        {t("agenda.detail.move")}
      </Button>
      <Button type="button" variant="ghost" onClick={onBack}>
        {t("agenda.detail.back")}
      </Button>
    </div>
  );
}

function NotesForm({
  branchId,
  appointmentId,
  notes,
  lockVersion,
}: {
  branchId: string;
  appointmentId: string;
  notes: string;
  lockVersion: number;
}) {
  const { t } = useTranslation("appointments");
  const fieldId = useId();
  const update = useUpdateNotes(branchId);
  const [value, setValue] = useState(notes);
  return (
    <div className="grid gap-1.5 border-t pt-4">
      <Label htmlFor={fieldId}>{t("agenda.detail.notes")}</Label>
      <Textarea
        id={fieldId}
        maxLength={500}
        value={value}
        onChange={(event) => setValue(event.target.value)}
      />
      <Button
        type="button"
        variant="outline"
        size="sm"
        disabled={value === notes}
        loading={update.isPending}
        onClick={() =>
          update.mutate(
            { id: appointmentId, notes: value.trim() || null, lockVersion },
            { onSuccess: () => toast.success(t("agenda.detail.notesSaved")) },
          )
        }
      >
        {t("agenda.detail.saveNotes")}
      </Button>
    </div>
  );
}

import { formatDateTime, useTranslation } from "@ceiba/i18n";
import {
  Badge,
  Button,
  buttonVariants,
  LoadingState,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  cn,
  toast,
} from "@ceiba/ui";
import { ChevronLeft, Plus } from "lucide-react";
import { useState, type ReactNode } from "react";
import { Link, useParams } from "react-router";
import { ForbiddenPage, NotFoundPage } from "../errors/status-pages";
import { useMe } from "../me/me-provider";
import { useCan } from "../permissions/can";
import { initials } from "../shell/initials";
import { QueryError } from "../ui/query-error";
import {
  flattenPages,
  useCustomerHistory,
  useCustomerQuery,
  useUpdateCustomer,
  type Customer,
  type CustomerAppointment,
} from "./api";
import { ContextBranchGate } from "../context/context-branch-gate";
import { CustomerDialog } from "./customer-dialog";
import { formatMonth, formatPhone, localDate } from "./lib";

type Status = CustomerAppointment["status"];

// Same visual families as the agenda's appointment cards (the --appointment-* tokens).
const STATUS_CLASS: Record<Status, string> = {
  scheduled: "bg-[var(--appointment-pending-bg)] text-[var(--appointment-pending-fg)]",
  confirmed: "bg-[var(--appointment-confirmed-bg)] text-[var(--appointment-confirmed-fg)]",
  checked_in: "bg-[var(--appointment-arrived-bg)] text-[var(--appointment-arrived-fg)]",
  completed: "bg-[var(--appointment-done-bg)] text-[var(--appointment-done-fg)]",
  cancelled: "bg-[var(--appointment-done-bg)] text-[var(--appointment-done-fg)]",
  rescheduled: "bg-[var(--appointment-done-bg)] text-[var(--appointment-done-fg)]",
  no_show: "bg-[var(--appointment-missed-bg)] text-[var(--appointment-missed-fg)]",
};
const UPCOMING: readonly Status[] = ["scheduled", "confirmed"];

/** /customers/:customerId: who the customer is, their history at the working branch, contact data and notes. */
export function CustomerPage() {
  const { t } = useTranslation("customers");
  const can = useCan();
  if (!can("platform.customer.read")) return <ForbiddenPage />;

  return (
    <ContextBranchGate what={t("profile.branchScope")}>
      {(branch) => <CustomerProfile branch={branch} />}
    </ContextBranchGate>
  );
}

interface WorkingBranch {
  id: string;
  name: string;
  time_zone: string;
}

function CustomerProfile({ branch }: { branch: WorkingBranch }) {
  const { t } = useTranslation(["customers", "common"]);
  const { customerId = "" } = useParams();
  const customer = useCustomerQuery(branch.id, customerId);

  if (customer.isPending) return <LoadingState label={t("common:loading")} />;
  if (customer.isError) return <NotFoundPage />;
  return <Profile customer={customer.data.data} branch={branch} />;
}

function Profile({ customer, branch }: { customer: Customer; branch: WorkingBranch }) {
  const { t } = useTranslation("customers");
  const can = useCan();
  const me = useMe();
  const [editing, setEditing] = useState(false);
  const update = useUpdateCustomer(branch.id);

  const archived = customer.archived_at !== null;
  const canEdit = !archived && can("platform.customer.update");
  const agendaActive = me.modules.some((module) => module.key === "appointments");
  const canReadHistory = agendaActive && can("appointments.appointment.read");
  const canBook = agendaActive && can("appointments.appointment.create");
  const history = useCustomerHistory(branch.id, customer.id, canReadHistory);
  const visits = flattenPages(history.data);
  const next = nextVisit(visits);

  async function save(body: Parameters<typeof update.mutateAsync>[0]["body"]) {
    await update.mutateAsync({ id: customer.id, body });
    toast.success(t("updated"));
    setEditing(false);
  }

  return (
    <div className="grid gap-6">
      <Link
        to="/customers"
        className="flex w-max items-center gap-1 text-sm font-semibold text-primary hover:underline"
      >
        <ChevronLeft aria-hidden="true" className="size-4" />
        {t("profile.back")}
      </Link>

      <header className="flex flex-wrap items-center gap-4">
        <span
          aria-hidden="true"
          className="grid size-14 shrink-0 place-items-center rounded-full bg-accent font-display text-xl font-bold text-accent-foreground"
        >
          {initials(customer.full_name)}
        </span>
        <div className="mr-auto grid gap-1">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="font-display text-3xl font-semibold tracking-tight">
              {customer.full_name}
            </h1>
            {archived ? <Badge variant="muted">{t("profile.archivedBadge")}</Badge> : null}
          </div>
          <p className="text-muted-foreground">
            {t("profile.since", {
              phone: formatPhone(customer.phone_e164),
              month: formatMonth(customer.created_at, branch.time_zone),
            })}
          </p>
        </div>
        {canEdit ? (
          <Button type="button" variant="outline" onClick={() => setEditing(true)}>
            {t("profile.edit")}
          </Button>
        ) : null}
        {!archived && canBook ? (
          <Link to="/agenda" className={buttonVariants()}>
            <Plus aria-hidden="true" />
            {t("profile.newAppointment")}
          </Link>
        ) : null}
      </header>

      <div className="flex flex-wrap items-start gap-6">
        <div className="grid min-w-0 flex-[2_1_26rem] gap-6">
          {next ? (
            <NextVisit visit={next} timeZone={branch.time_zone} canReschedule={canBook} />
          ) : null}
          <section aria-labelledby="customer-history" className="grid gap-3">
            <h2 id="customer-history" className="font-display text-lg font-semibold">
              {t("profile.history.title")}
            </h2>
            <HistoryBody
              agendaActive={agendaActive}
              canRead={canReadHistory}
              history={history}
              visits={visits}
              branch={branch}
            />
          </section>
        </div>

        <div className="grid min-w-0 flex-[1_1_16rem] gap-4">
          <SideCard id="customer-notes" title={t("profile.notes.title")}>
            <p className="leading-relaxed whitespace-pre-line text-muted-foreground">
              {customer.notes ?? t("profile.notes.empty")}
            </p>
          </SideCard>
          <SideCard id="customer-contact" title={t("profile.contact.title")}>
            <Field label={t("profile.contact.phone")}>{formatPhone(customer.phone_e164)}</Field>
            <Field label={t("profile.contact.email")}>
              {customer.email ?? t("profile.contact.noEmail")}
            </Field>
          </SideCard>
          <SideCard id="customer-reminders" title={t("profile.reminders.title")}>
            <div className="flex items-start gap-2.5">
              <span
                aria-hidden="true"
                className="mt-1.5 size-2 shrink-0 rounded-full border-[1.5px] border-muted-foreground"
              />
              <span className="grid gap-0.5">
                <span className="font-semibold">{t("profile.reminders.none")}</span>
                <span className="text-xs text-muted-foreground">
                  {t("profile.reminders.noneDetail")}
                </span>
              </span>
            </div>
          </SideCard>
        </div>
      </div>

      <CustomerDialog
        open={editing}
        onOpenChange={setEditing}
        title={t("profile.edit")}
        customer={customer}
        pending={update.isPending}
        onSubmit={save}
      />
    </div>
  );
}

/** The soonest appointment still ahead; history comes newest first. */
function nextVisit(visits: readonly CustomerAppointment[]) {
  const now = Date.now();
  return visits
    .filter((visit) => UPCOMING.includes(visit.status) && Date.parse(visit.starts_at) > now)
    .at(-1);
}

const serviceNames = (visit: CustomerAppointment) =>
  visit.services.map((service) => service.name).join(", ");

function NextVisit({
  visit,
  timeZone,
  canReschedule,
}: {
  visit: CustomerAppointment;
  timeZone: string;
  canReschedule: boolean;
}) {
  const { t } = useTranslation("customers");
  return (
    <section
      aria-labelledby="customer-next"
      className="flex flex-wrap items-center gap-3.5 rounded-2xl bg-accent p-4 text-accent-foreground"
    >
      <span className="grid min-w-48 flex-1 gap-0.5">
        <h2 id="customer-next" className="text-sm font-semibold text-primary">
          {t("profile.next.title")}
        </h2>
        <span className="text-base font-bold">{formatDateTime(visit.starts_at, timeZone)}</span>
        <span className="text-sm">
          {t("profile.next.detail", {
            services: serviceNames(visit),
            professional: visit.professional.display_name,
          })}
        </span>
      </span>
      {canReschedule ? (
        <Link
          to={`/agenda?date=${localDate(visit.starts_at, timeZone)}`}
          className={buttonVariants({ variant: "outline" })}
        >
          {t("profile.reschedule")}
        </Link>
      ) : null}
    </section>
  );
}

interface HistoryBodyProps {
  agendaActive: boolean;
  canRead: boolean;
  history: ReturnType<typeof useCustomerHistory>;
  visits: readonly CustomerAppointment[];
  branch: WorkingBranch;
}

function HistoryBody({ agendaActive, canRead, history, visits, branch }: HistoryBodyProps) {
  const { t } = useTranslation(["customers", "common"]);
  if (!agendaActive)
    return <p className="text-muted-foreground">{t("profile.history.moduleOff")}</p>;
  if (!canRead) return <p className="text-muted-foreground">{t("profile.history.noPermission")}</p>;
  if (history.isPending) return <LoadingState label={t("common:loading")} />;
  if (history.isError)
    return <QueryError error={history.error} onRetry={() => void history.refetch()} />;

  return (
    <>
      <p className="text-sm text-muted-foreground">
        {t("profile.history.scope", { branch: branch.name })}
      </p>
      {visits.length === 0 ? (
        <p className="py-6 text-muted-foreground">{t("profile.history.empty")}</p>
      ) : (
        <div className="overflow-x-auto">
          {/* Folded columns fit a phone: no minimum width to scroll sideways. */}
          <Table className="min-w-0">
            <TableHeader>
              <TableRow className="border-b">
                <TableHead>{t("profile.history.columns.date")}</TableHead>
                <TableHead>{t("profile.history.columns.service")}</TableHead>
                <TableHead className="hidden sm:table-cell">
                  {t("profile.history.columns.professional")}
                </TableHead>
                <TableHead>{t("profile.history.columns.status")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {visits.map((visit) => (
                <TableRow key={visit.id}>
                  <TableCell>{formatDateTime(visit.starts_at, branch.time_zone)}</TableCell>
                  <TableCell>
                    {serviceNames(visit)}
                    {/* At phone width the professional folds under the service. */}
                    <span className="block text-muted-foreground sm:hidden">
                      {visit.professional.display_name}
                    </span>
                  </TableCell>
                  <TableCell className="hidden sm:table-cell">
                    {visit.professional.display_name}
                  </TableCell>
                  <TableCell>
                    <Badge className={cn(STATUS_CLASS[visit.status])}>
                      {t(`profile.history.status.${visit.status}`)}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
      {history.hasNextPage ? (
        <Button
          type="button"
          variant="outline"
          className="justify-self-start"
          disabled={history.isFetchingNextPage}
          onClick={() => void history.fetchNextPage()}
        >
          {t("loadMore")}
        </Button>
      ) : null}
    </>
  );
}

function SideCard({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section aria-labelledby={id} className="grid gap-2.5 rounded-2xl border p-4">
      <h2 id={id} className="text-[0.9375rem] font-semibold">
        {title}
      </h2>
      {children}
    </section>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-0.5">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span>{children}</span>
    </div>
  );
}

import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  buttonVariants,
  Input,
  PageHeader,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  toast,
} from "@ceiba/ui";
import { FileUp, Plus, Search } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router";
import { ForbiddenPage } from "../errors/status-pages";
import { useCan } from "../permissions/can";
import { EmptyState } from "../ui/empty-state";
import { QueryBoundary } from "../ui/query-boundary";
import {
  flattenPages,
  useCreateCustomer,
  useCustomersQuery,
  type Customer,
  type CustomerInput,
} from "./api";
import { BranchPicker } from "./branch-picker";
import { CustomerAside } from "./customer-aside";
import { CustomerForm } from "./customer-form";
import { formatPhone } from "./lib";
import { useWorkingBranch } from "./use-working-branch";

const SEARCH_DELAY_MS = 250;

/** /customers: the company's customers, searched by name or phone, with creation in the side panel. */
export function CustomersPage() {
  const can = useCan();
  const working = useWorkingBranch();
  const [creating, setCreating] = useState(false);
  if (!can("platform.customer.read")) return <ForbiddenPage />;

  return (
    <>
      <CustomersHeader onNew={working.branch ? () => setCreating(true) : undefined} />
      {working.needsChoice ? (
        <BranchPicker
          branches={working.branches}
          value={working.branch?.id ?? null}
          onChange={working.choose}
        />
      ) : null}
      {working.branch ? (
        <CustomersList
          branchId={working.branch.id}
          creating={creating}
          onCreatingChange={setCreating}
        />
      ) : null}
    </>
  );
}

function CustomersHeader({ onNew }: { onNew?(): void }) {
  const { t } = useTranslation("customers");
  const can = useCan();
  return (
    <PageHeader
      title={t("title")}
      description={t("description")}
      actions={
        <div className="flex flex-wrap gap-2">
          {can("platform.customer.import") ? (
            <Link to="/customers/import" className={buttonVariants({ variant: "outline" })}>
              <FileUp aria-hidden="true" />
              {t("import")}
            </Link>
          ) : null}
          {onNew && can("platform.customer.create") ? (
            <Button type="button" onClick={onNew}>
              <Plus aria-hidden="true" />
              {t("new")}
            </Button>
          ) : null}
        </div>
      }
    />
  );
}

interface CustomersListProps {
  branchId: string;
  creating: boolean;
  onCreatingChange(open: boolean): void;
}

function CustomersList({ branchId, creating, onCreatingChange }: CustomersListProps) {
  const { t } = useTranslation("customers");
  const can = useCan();
  const navigate = useNavigate();
  const [term, setTerm] = useState("");
  const [searched, setSearched] = useState("");
  const customers = useCustomersQuery(branchId, searched);
  const create = useCreateCustomer(branchId);

  useEffect(() => {
    const timer = setTimeout(() => setSearched(term.trim()), SEARCH_DELAY_MS);
    return () => clearTimeout(timer);
  }, [term]);

  async function createCustomer(values: CustomerInput) {
    const created = await create.mutateAsync(values);
    toast.success(t("created"));
    onCreatingChange(false);
    void navigate(`/customers/${created.data.id}`);
  }

  const canCreate = can("platform.customer.create");

  return (
    <>
      <div className="relative mb-4 max-w-sm">
        <Search
          aria-hidden="true"
          className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
        />
        <Input
          type="search"
          aria-label={t("searchLabel")}
          placeholder={t("searchPlaceholder")}
          value={term}
          onChange={(event) => setTerm(event.target.value)}
          className="pl-9"
        />
      </div>

      <QueryBoundary
        query={customers}
        isEmpty={(data) => flattenPages(data).length === 0}
        empty={
          searched ? (
            <p className="py-10 text-center text-muted-foreground">
              {t("noMatches", { term: searched })}
            </p>
          ) : (
            <EmptyState
              title={t("empty.title")}
              description={canCreate ? t("empty.description") : t("empty.readOnlyDescription")}
              action={
                canCreate ? { label: t("new"), onClick: () => onCreatingChange(true) } : undefined
              }
            >
              {can("platform.customer.import") ? (
                <Link to="/customers/import" className={buttonVariants({ variant: "outline" })}>
                  {t("import")}
                </Link>
              ) : null}
            </EmptyState>
          )
        }
      >
        {(data) => (
          <>
            <CustomersTable customers={flattenPages(data)} />
            {customers.hasNextPage ? (
              <Button
                type="button"
                variant="outline"
                className="mt-4"
                disabled={customers.isFetchingNextPage}
                onClick={() => void customers.fetchNextPage()}
              >
                {t("loadMore")}
              </Button>
            ) : null}
          </>
        )}
      </QueryBoundary>

      {creating ? (
        <CustomerAside title={t("panelNewTitle")} onClose={() => onCreatingChange(false)}>
          <CustomerForm onSubmit={(values) => createCustomer(values as CustomerInput)} />
        </CustomerAside>
      ) : null}
    </>
  );
}

function CustomersTable({ customers }: { customers: readonly Customer[] }) {
  const { t } = useTranslation("customers");
  return (
    <Table>
      <TableHeader>
        <TableRow className="border-b">
          <TableHead>{t("columns.name")}</TableHead>
          <TableHead>{t("columns.phone")}</TableHead>
          <TableHead className="hidden sm:table-cell">{t("columns.email")}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {customers.map((customer) => (
          <TableRow key={customer.id}>
            <TableCell className="font-medium">
              <Link to={`/customers/${customer.id}`} className="hover:underline">
                {customer.full_name}
              </Link>
            </TableCell>
            <TableCell className="whitespace-nowrap tabular-nums">
              {formatPhone(customer.phone_e164)}
            </TableCell>
            <TableCell className="hidden text-muted-foreground sm:table-cell">
              {customer.email ?? ""}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

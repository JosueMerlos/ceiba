import { useTranslation } from "@ceiba/i18n";
import { Button, Input, Label } from "@ceiba/ui";
import { useEffect, useId, useState, type FormEvent } from "react";
import { apiErrorMessages } from "../../../../platform/forms/api-error-messages";
import { useCreateCustomer, useCustomerSearch } from "../../api/agenda-mutations";
import { FormAlert } from "../form-alert";

const SEARCH_DELAY_MS = 250;

export interface PickedCustomer {
  id: string;
  name: string;
}

interface CustomerPickerProps {
  branchId: string;
  value: PickedCustomer | null;
  onChange(customer: PickedCustomer | null): void;
}

/** Finds a customer by name or phone, or creates one on the spot, without leaving the booking. */
export function CustomerPicker({ branchId, value, onChange }: CustomerPickerProps) {
  const { t } = useTranslation("appointments");
  const inputId = useId();
  const [term, setTerm] = useState("");
  const [searched, setSearched] = useState("");
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => setSearched(term), SEARCH_DELAY_MS);
    return () => clearTimeout(timer);
  }, [term]);

  const results = useCustomerSearch(branchId, searched);

  if (value) {
    return (
      <div className="grid gap-1.5">
        <Label asChild>
          <span>{t("agenda.form.customer")}</span>
        </Label>
        <div className="flex items-center justify-between gap-2 rounded-lg border px-3 py-2">
          <span className="truncate font-semibold">{value.name}</span>
          <Button type="button" variant="ghost" size="sm" onClick={() => onChange(null)}>
            {t("agenda.form.changeCustomer")}
          </Button>
        </div>
      </div>
    );
  }

  const customers = results.data?.data ?? [];
  return (
    <div className="grid gap-2">
      <div className="grid gap-1.5">
        <Label htmlFor={inputId}>{t("agenda.form.searchCustomer")}</Label>
        <Input
          id={inputId}
          type="search"
          value={term}
          autoComplete="off"
          aria-describedby={`${inputId}-hint`}
          onChange={(event) => setTerm(event.target.value)}
        />
        <p id={`${inputId}-hint`} className="text-xs text-muted-foreground">
          {t("agenda.form.searchHint")}
        </p>
      </div>
      {customers.length > 0 ? (
        <ul className="grid gap-1">
          {customers.map((customer) => (
            <li key={customer.id}>
              <Button
                type="button"
                variant="ghost"
                className="h-auto w-full justify-between gap-2 py-2 text-left"
                onClick={() => onChange({ id: customer.id, name: customer.full_name })}
              >
                <span className="truncate">{customer.full_name}</span>
                <span className="text-xs text-muted-foreground">{customer.phone_e164}</span>
              </Button>
            </li>
          ))}
        </ul>
      ) : null}
      {results.isSuccess && customers.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("agenda.form.noCustomers")}</p>
      ) : null}
      {creating ? (
        <NewCustomerForm branchId={branchId} onCreated={onChange} />
      ) : (
        <Button type="button" variant="outline" size="sm" onClick={() => setCreating(true)}>
          {t("agenda.form.createCustomer")}
        </Button>
      )}
    </div>
  );
}

function NewCustomerForm({
  branchId,
  onCreated,
}: {
  branchId: string;
  onCreated(customer: PickedCustomer): void;
}) {
  const { t } = useTranslation("appointments");
  const id = useId();
  const create = useCreateCustomer(branchId);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");

  async function save(event: FormEvent) {
    event.preventDefault();
    const { data } = await create.mutateAsync({ full_name: name.trim(), phone_e164: phone.trim() });
    onCreated({ id: data.id, name: data.full_name });
  }

  return (
    // Not a <form>: this sits inside the booking form and nested forms are invalid HTML.
    <div className="grid gap-2 rounded-lg border p-3">
      <div className="grid gap-1.5">
        <Label htmlFor={`${id}-name`}>{t("agenda.form.customerName")}</Label>
        <Input id={`${id}-name`} value={name} onChange={(event) => setName(event.target.value)} />
      </div>
      <div className="grid gap-1.5">
        <Label htmlFor={`${id}-phone`}>{t("agenda.form.customerPhone")}</Label>
        <Input
          id={`${id}-phone`}
          type="tel"
          value={phone}
          onChange={(event) => setPhone(event.target.value)}
        />
      </div>
      {create.isError ? <FormAlert>{apiErrorMessages(create.error, t).join(" ")}</FormAlert> : null}
      <Button
        type="button"
        size="sm"
        loading={create.isPending}
        disabled={!name.trim() || !phone.trim()}
        onClick={(event) => void save(event).catch(() => {})}
      >
        {t("agenda.form.saveCustomer")}
      </Button>
    </div>
  );
}

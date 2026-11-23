import { useTranslation } from "@ceiba/i18n";
import {
  Button,
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  Input,
  Textarea,
} from "@ceiba/ui";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMemo } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { reportSubmitError } from "../forms/report-submit-error";
import type { Customer, CustomerPatch } from "./api";

const FIELDS = {
  full_name: "full_name",
  phone_e164: "phone_e164",
  email: "email",
  notes: "notes",
} as const;

interface CustomerFormProps {
  /** Absent = create. */
  customer?: Customer;
  /** Receives only the fields that changed when editing (a PATCH writes what it is sent). */
  onSubmit(values: CustomerPatch): Promise<unknown>;
}

export function CustomerForm({ customer, onSubmit }: CustomerFormProps) {
  const { t } = useTranslation(["customers", "errors"]);
  const schema = useMemo(
    () =>
      z.object({
        full_name: z.string().trim().min(1, t("form.errors.nameRequired")),
        phone_e164: z.string().trim().min(1, t("form.errors.phoneRequired")),
        email: z.string().trim(),
        notes: z.string().trim(),
      }),
    [t],
  );
  const form = useForm<z.infer<typeof schema>>({
    resolver: zodResolver(schema),
    defaultValues: {
      full_name: customer?.full_name ?? "",
      phone_e164: customer?.phone_e164 ?? "",
      email: customer?.email ?? "",
      notes: customer?.notes ?? "",
    },
  });

  const submit = form.handleSubmit(async (values) => {
    const body: CustomerPatch = {
      full_name: values.full_name,
      phone_e164: values.phone_e164,
      email: values.email || null,
      notes: values.notes || null,
    };
    const dirty = form.formState.dirtyFields;
    const changed = customer
      ? (Object.fromEntries(
          Object.entries(body).filter(([key]) => dirty[key as keyof typeof dirty]),
        ) as CustomerPatch)
      : body;
    try {
      await onSubmit(changed);
    } catch (error) {
      reportSubmitError(error, form.setError, t, FIELDS);
    }
  });

  const serverError = form.formState.errors.root?.serverError?.message;

  return (
    <Form {...form}>
      <form onSubmit={submit} noValidate className="grid gap-4">
        <FormField
          control={form.control}
          name="full_name"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("form.fullName")}</FormLabel>
              <FormControl>
                <Input {...field} autoComplete="off" />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="phone_e164"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("form.phone")}</FormLabel>
              <FormControl>
                <Input {...field} type="tel" inputMode="tel" autoComplete="off" />
              </FormControl>
              <FormDescription>{t("form.phoneHint")}</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="email"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("form.email")}</FormLabel>
              <FormControl>
                <Input {...field} type="email" autoComplete="off" />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="notes"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("form.notes")}</FormLabel>
              <FormControl>
                <Textarea {...field} rows={4} />
              </FormControl>
              <FormDescription>{t("form.notesHint")}</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
        {serverError ? (
          <p role="alert" className="text-sm font-medium text-destructive">
            {serverError}
          </p>
        ) : null}
        <Button type="submit" disabled={form.formState.isSubmitting} className="justify-self-start">
          {t("form.save")}
        </Button>
      </form>
    </Form>
  );
}

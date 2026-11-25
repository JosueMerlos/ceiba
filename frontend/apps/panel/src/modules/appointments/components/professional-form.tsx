import { useTranslation } from "@ceiba/i18n";
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  Input,
  Switch,
} from "@ceiba/ui";
import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useMemo } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
import type { ProfessionalDetail, ProfessionalInput } from "../api/professionals";
import { reportSubmitError } from "../../../platform/forms/report-submit-error";
import { FormAlert } from "./form-alert";

export type ProfessionalFormValues = Pick<
  ProfessionalInput,
  "display_name" | "active" | "phone" | "email"
>;

interface ProfessionalFormProps {
  /** The form has no button: the modal's footer submits it through `form={id}`. */
  id: string;
  /** Absent = create. */
  professional?: ProfessionalDetail;
  /** Rejects with the API error; the form shows it (422 on its fields, anything else as a form-level message). */
  onSubmit(values: ProfessionalFormValues): Promise<ProfessionalDetail>;
  onDirtyChange?(dirty: boolean): void;
  /** Shows and sends the phone and email. The contact is personal data: the caller decides who may see it. */
  withContact: boolean;
}

/** The profile of a professional: name, whether they take appointments and, when allowed, their contact. */
export function ProfessionalForm({
  id,
  professional,
  onSubmit,
  onDirtyChange,
  withContact,
}: ProfessionalFormProps) {
  const { t } = useTranslation(["appointments", "errors"]);
  const schema = useMemo(
    () =>
      z.object({
        display_name: z.string().trim().min(1, t("catalog.professionalForm.errors.nameRequired")),
        phone: z.string(),
        email: z.string(),
        active: z.boolean(),
      }),
    [t],
  );
  const form = useForm<z.infer<typeof schema>>({
    resolver: zodResolver(schema),
    defaultValues: {
      display_name: professional?.display_name ?? "",
      phone: professional?.phone ?? "",
      email: professional?.email ?? "",
      active: professional?.active ?? true,
    },
  });

  const dirty = form.formState.isDirty;
  useEffect(() => onDirtyChange?.(dirty), [dirty, onDirtyChange]);

  const submit = form.handleSubmit(async (values) => {
    try {
      const saved = await onSubmit({
        display_name: values.display_name.trim(),
        active: values.active,
        // Blank means "no contact": the API clears it with null.
        ...(withContact
          ? { phone: values.phone.trim() || null, email: values.email.trim() || null }
          : {}),
      });
      // The server's version is the new baseline (it normalizes the phone and the email), not what was typed.
      form.reset({
        display_name: saved.display_name,
        active: saved.active,
        phone: withContact ? (saved.phone ?? "") : values.phone,
        email: withContact ? (saved.email ?? "") : values.email,
      });
    } catch (error) {
      reportSubmitError(error, form.setError, t, {
        display_name: "display_name",
        phone: "phone",
        email: "email",
        active: "active",
      });
    }
  });

  return (
    <Form {...form}>
      <form id={id} onSubmit={submit} noValidate className="grid gap-5">
        <FormField
          control={form.control}
          name="display_name"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.professionalForm.name")}</FormLabel>
              <FormControl>
                <Input {...field} autoComplete="off" />
              </FormControl>
              <FormDescription>{t("catalog.professionalForm.nameHint")}</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
        {withContact ? (
          <div className="grid gap-5 sm:grid-cols-2">
            <FormField
              control={form.control}
              name="phone"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("catalog.professionalForm.phone")}</FormLabel>
                  <FormControl>
                    <Input {...field} type="tel" inputMode="tel" autoComplete="off" />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="email"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("catalog.professionalForm.email")}</FormLabel>
                  <FormControl>
                    <Input {...field} type="email" inputMode="email" autoComplete="off" />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
          </div>
        ) : null}
        <FormField
          control={form.control}
          name="active"
          render={({ field }) => (
            <FormItem className="rounded-xl border bg-card px-4 py-3">
              <div className="flex items-center justify-between gap-3">
                <FormLabel>{t("catalog.professionalForm.active")}</FormLabel>
                <FormControl>
                  <Switch checked={field.value} onCheckedChange={field.onChange} />
                </FormControl>
              </div>
              <FormDescription>{t("catalog.professionalForm.activeHint")}</FormDescription>
            </FormItem>
          )}
        />

        <FormAlert>{form.formState.errors.root?.serverError?.message}</FormAlert>
      </form>
    </Form>
  );
}

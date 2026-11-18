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
  Switch,
} from "@ceiba/ui";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMemo } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
import type { Professional } from "../api/professionals";
import { reportSubmitError } from "../../../platform/forms/report-submit-error";
import { FormAlert } from "./form-alert";

export interface ProfessionalFormValues {
  display_name: string;
  active: boolean;
}

interface ProfessionalFormProps {
  /** Absent = create. */
  professional?: Professional;
  readOnly?: boolean;
  /** Rejects with the API error; the form shows it (422 on its fields, anything else as a form-level message). */
  onSubmit(values: ProfessionalFormValues): Promise<unknown>;
}

export function ProfessionalForm({
  professional,
  readOnly = false,
  onSubmit,
}: ProfessionalFormProps) {
  const { t } = useTranslation(["appointments", "errors"]);
  const schema = useMemo(
    () =>
      z.object({
        display_name: z.string().trim().min(1, t("catalog.professionalForm.errors.nameRequired")),
        active: z.boolean(),
      }),
    [t],
  );
  const form = useForm<z.infer<typeof schema>>({
    resolver: zodResolver(schema),
    defaultValues: {
      display_name: professional?.display_name ?? "",
      active: professional?.active ?? true,
    },
  });

  const submit = form.handleSubmit(async (values) => {
    try {
      await onSubmit({ display_name: values.display_name.trim(), active: values.active });
    } catch (error) {
      reportSubmitError(error, form.setError, t, {
        display_name: "display_name",
        active: "active",
      });
    }
  });

  return (
    <Form {...form}>
      <form onSubmit={submit} noValidate className="grid gap-4">
        <FormField
          control={form.control}
          name="display_name"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.professionalForm.name")}</FormLabel>
              <FormControl>
                <Input {...field} disabled={readOnly} autoComplete="off" />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="active"
          render={({ field }) => (
            <FormItem>
              <div className="flex items-center justify-between gap-3">
                <FormLabel>{t("catalog.professionalForm.active")}</FormLabel>
                <FormControl>
                  <Switch
                    checked={field.value}
                    onCheckedChange={field.onChange}
                    disabled={readOnly}
                  />
                </FormControl>
              </div>
              <FormDescription>{t("catalog.professionalForm.activeHint")}</FormDescription>
            </FormItem>
          )}
        />

        <FormAlert>{form.formState.errors.root?.serverError?.message}</FormAlert>

        {readOnly ? null : (
          <Button type="submit" loading={form.formState.isSubmitting}>
            {professional
              ? t("catalog.professionalForm.save")
              : t("catalog.professionalForm.create")}
          </Button>
        )}
      </form>
    </Form>
  );
}

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
import type { Service } from "../api/catalog";
import { minorToInput, parsePriceToMinor } from "../lib/money";
import { reportSubmitError } from "../../../platform/forms/report-submit-error";
import { FormAlert } from "./form-alert";

/** What the form emits: the contract's own units (price in minor units, minutes as numbers). */
export interface ServiceFormValues {
  name: string;
  duration_minutes: number;
  buffer_after_minutes: number;
  price_minor: number;
  active: boolean;
}

interface ServiceFormProps {
  /** Absent = create. */
  service?: Service;
  currency: "NIO" | "USD";
  readOnly?: boolean;
  /** Rejects with the API error; the form shows it (422 on its fields, anything else as a form-level message). */
  onSubmit(values: ServiceFormValues): Promise<unknown>;
}

// API field names the form knows: `price_minor` is edited as `price`.
const FIELD_MAP = {
  name: "name",
  duration_minutes: "duration_minutes",
  buffer_after_minutes: "buffer_after_minutes",
  price_minor: "price",
  active: "active",
} as const;

const WHOLE = /^\d+$/;

export function ServiceForm({ service, currency, readOnly = false, onSubmit }: ServiceFormProps) {
  const { t } = useTranslation(["appointments", "errors"]);

  // The schema lives here (not at module level) because its messages come from the translations.
  const schema = useMemo(
    () =>
      z.object({
        name: z.string().trim().min(1, t("catalog.serviceForm.errors.nameRequired")),
        duration_minutes: z
          .string()
          .trim()
          .regex(WHOLE, t("catalog.serviceForm.errors.durationInvalid"))
          .refine((value) => Number(value) > 0, t("catalog.serviceForm.errors.durationInvalid")),
        buffer_after_minutes: z
          .string()
          .trim()
          .regex(WHOLE, t("catalog.serviceForm.errors.bufferInvalid")),
        price: z
          .string()
          .refine(
            (value) => parsePriceToMinor(value) !== null,
            t("catalog.serviceForm.errors.priceInvalid"),
          ),
        active: z.boolean(),
      }),
    [t],
  );
  type FormValues = z.infer<typeof schema>;

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: service?.name ?? "",
      duration_minutes: service ? String(service.duration_minutes) : "",
      buffer_after_minutes: String(service?.buffer_after_minutes ?? 0),
      price: service ? minorToInput(service.price_minor) : "",
      active: service?.active ?? true,
    },
  });

  const submit = form.handleSubmit(async (values) => {
    try {
      await onSubmit({
        name: values.name.trim(),
        duration_minutes: Number(values.duration_minutes),
        buffer_after_minutes: Number(values.buffer_after_minutes),
        price_minor: parsePriceToMinor(values.price)!,
        active: values.active,
      });
    } catch (error) {
      reportSubmitError(error, form.setError, t, FIELD_MAP);
    }
  });

  return (
    <Form {...form}>
      <form onSubmit={submit} noValidate className="grid gap-4">
        <FormField
          control={form.control}
          name="name"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.serviceForm.name")}</FormLabel>
              <FormControl>
                <Input {...field} disabled={readOnly} autoComplete="off" />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="duration_minutes"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.serviceForm.duration")}</FormLabel>
              <FormControl>
                <Input {...field} disabled={readOnly} inputMode="numeric" autoComplete="off" />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="buffer_after_minutes"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.serviceForm.bufferAfter")}</FormLabel>
              <FormControl>
                <Input {...field} disabled={readOnly} inputMode="numeric" autoComplete="off" />
              </FormControl>
              <FormDescription>{t("catalog.serviceForm.bufferAfterHint")}</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="price"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.serviceForm.price", { currency })}</FormLabel>
              <FormControl>
                <Input {...field} disabled={readOnly} inputMode="decimal" autoComplete="off" />
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
                <FormLabel>{t("catalog.serviceForm.active")}</FormLabel>
                <FormControl>
                  <Switch
                    checked={field.value}
                    onCheckedChange={field.onChange}
                    disabled={readOnly}
                  />
                </FormControl>
              </div>
              <FormDescription>{t("catalog.serviceForm.activeHint")}</FormDescription>
            </FormItem>
          )}
        />

        <FormAlert>{form.formState.errors.root?.serverError?.message}</FormAlert>

        {readOnly ? null : (
          <Button type="submit" loading={form.formState.isSubmitting}>
            {service ? t("catalog.serviceForm.save") : t("catalog.serviceForm.create")}
          </Button>
        )}
      </form>
    </Form>
  );
}

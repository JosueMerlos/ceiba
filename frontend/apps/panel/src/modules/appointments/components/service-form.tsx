import { formatDuration, useTranslation } from "@ceiba/i18n";
import {
  DurationField,
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
import { ServiceCategoryField } from "./service-category-field";

/** What the form emits: the contract's own units (price in minor units, minutes as numbers). */
export interface ServiceFormValues {
  name: string;
  /** As typed: the API trims it and stores a blank one as no category. */
  category: string | null;
  duration_minutes: number;
  buffer_before_minutes: number;
  buffer_after_minutes: number;
  price_minor: number;
  active: boolean;
}

interface ServiceFormProps {
  /** The form has no button: the modal's footer submits it through `form={id}`. */
  id: string;
  /** Absent = create. */
  service?: Service;
  currency: "NIO" | "USD";
  /** Categories already in use, offered while typing one. */
  categories: readonly string[];
  /** Rejects with the API error; the form shows it (422 on its fields, anything else as a form-level message). */
  onSubmit(values: ServiceFormValues): Promise<unknown>;
}

// API field names the form knows: `price_minor` is edited as `price`.
const FIELD_MAP = {
  name: "name",
  category: "category",
  duration_minutes: "duration_minutes",
  buffer_before_minutes: "buffer_before_minutes",
  buffer_after_minutes: "buffer_after_minutes",
  price_minor: "price",
  active: "active",
} as const;

const CATEGORY_MAX = 60;
const DEFAULT_DURATION = 30;
const BUFFER_PRESETS = [0, 5, 10, 15, 30] as const;
const BUFFER_MAX = 120;

export function ServiceForm({ id, service, currency, categories, onSubmit }: ServiceFormProps) {
  const { t } = useTranslation(["appointments", "errors"]);

  // The schema lives here (not at module level) because its messages come from the translations.
  const schema = useMemo(
    () =>
      z.object({
        name: z.string().trim().min(1, t("catalog.serviceForm.errors.nameRequired")),
        category: z.string().max(CATEGORY_MAX, t("catalog.serviceForm.errors.categoryTooLong")),
        duration_minutes: z.number().int().positive(),
        buffer_before_minutes: z.number().int().min(0),
        buffer_after_minutes: z.number().int().min(0),
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
      category: service?.category ?? "",
      duration_minutes: service?.duration_minutes ?? DEFAULT_DURATION,
      buffer_before_minutes: service?.buffer_before_minutes ?? 0,
      buffer_after_minutes: service?.buffer_after_minutes ?? 0,
      price: service ? minorToInput(service.price_minor) : "",
      active: service?.active ?? true,
    },
  });

  const submit = form.handleSubmit(async (values) => {
    try {
      await onSubmit({
        name: values.name.trim(),
        category: values.category === "" ? null : values.category,
        duration_minutes: values.duration_minutes,
        buffer_before_minutes: values.buffer_before_minutes,
        buffer_after_minutes: values.buffer_after_minutes,
        price_minor: parsePriceToMinor(values.price)!,
        active: values.active,
      });
    } catch (error) {
      reportSubmitError(error, form.setError, t, FIELD_MAP);
    }
  });

  return (
    <Form {...form}>
      <form id={id} onSubmit={submit} noValidate className="grid gap-5">
        <div className="grid gap-4 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="name"
            render={({ field }) => (
              <FormItem>
                <FormLabel>{t("catalog.serviceForm.name")}</FormLabel>
                <FormControl>
                  <Input {...field} autoComplete="off" />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="category"
            render={({ field }) => (
              <FormItem>
                <FormLabel>{t("catalog.serviceForm.category")}</FormLabel>
                <FormControl>
                  <ServiceCategoryField
                    ref={field.ref}
                    value={field.value}
                    onChange={field.onChange}
                    onBlur={field.onBlur}
                    suggestions={categories}
                    listLabel={t("catalog.serviceForm.categorySuggestions")}
                  />
                </FormControl>
                <FormDescription>{t("catalog.serviceForm.categoryHint")}</FormDescription>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <FormField
          control={form.control}
          name="duration_minutes"
          render={({ field }) => (
            <MinutesField
              label={t("catalog.serviceForm.duration")}
              controls="durationControls"
              value={field.value}
              onChange={field.onChange}
            />
          )}
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="buffer_before_minutes"
            render={({ field }) => (
              <MinutesField
                label={t("catalog.serviceForm.bufferBefore")}
                hint={t("catalog.serviceForm.bufferBeforeHint")}
                controls="bufferBeforeControls"
                buffer
                value={field.value}
                onChange={field.onChange}
              />
            )}
          />
          <FormField
            control={form.control}
            name="buffer_after_minutes"
            render={({ field }) => (
              <MinutesField
                label={t("catalog.serviceForm.bufferAfter")}
                hint={t("catalog.serviceForm.bufferAfterHint")}
                controls="bufferAfterControls"
                buffer
                value={field.value}
                onChange={field.onChange}
              />
            )}
          />
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="price"
            render={({ field }) => (
              <FormItem>
                <FormLabel>{t("catalog.serviceForm.price", { currency })}</FormLabel>
                <FormControl>
                  <Input {...field} inputMode="decimal" autoComplete="off" />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="active"
            render={({ field }) => (
              <FormItem className="content-start sm:pt-6">
                <div className="flex items-center justify-between gap-3">
                  <FormLabel>{t("catalog.serviceForm.active")}</FormLabel>
                  <FormControl>
                    <Switch checked={field.value} onCheckedChange={field.onChange} />
                  </FormControl>
                </div>
                <FormDescription>{t("catalog.serviceForm.activeHint")}</FormDescription>
              </FormItem>
            )}
          />
        </div>

        <FormAlert>{form.formState.errors.root?.serverError?.message}</FormAlert>
      </form>
    </Form>
  );
}

/** Minutes picked with the stepper and shortcuts; a buffer may be zero, a duration may not. */
function MinutesField({
  label,
  hint,
  controls,
  buffer = false,
  value,
  onChange,
}: {
  label: string;
  hint?: string;
  controls: "durationControls" | "bufferBeforeControls" | "bufferAfterControls";
  buffer?: boolean;
  value: number;
  onChange(minutes: number): void;
}) {
  const { t } = useTranslation("appointments");
  return (
    <div className="grid content-start gap-2">
      <p className="text-sm leading-none font-medium">{label}</p>
      <DurationField
        aria-label={label}
        value={value}
        onChange={onChange}
        formatDuration={formatDuration}
        {...(buffer ? { min: 0, max: BUFFER_MAX, presets: BUFFER_PRESETS } : {})}
        decreaseLabel={t(`catalog.serviceForm.${controls}.decrease`)}
        increaseLabel={t(`catalog.serviceForm.${controls}.increase`)}
        presetsLabel={t(`catalog.serviceForm.${controls}.presets`)}
      />
      {hint ? <p className="text-sm text-muted-foreground">{hint}</p> : null}
    </div>
  );
}

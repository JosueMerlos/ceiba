import { formatCurrency, useTranslation } from "@ceiba/i18n";
import {
  Button,
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  Input,
} from "@ceiba/ui";
import { useState } from "react";
import { useForm } from "react-hook-form";
import type { Service, ServiceOverride, ServiceOverrideInput } from "../api/catalog";
import { minorToInput, parsePriceToMinor } from "../lib/money";
import { reportSubmitError } from "../../../platform/forms/report-submit-error";
import { FormAlert } from "./form-alert";

interface BranchOverrideFieldsProps {
  service: Service;
  override?: ServiceOverride | null;
  branchName: string;
  /** Per-field gates: a branch manager may change the duration without being allowed to touch the price. */
  canEditDuration: boolean;
  canEditPrice: boolean;
  /** Receives ONLY the keys the user changed (the PUT is a merge); null removes that value. */
  onSubmit(change: ServiceOverrideInput): Promise<unknown>;
  onReset?(): Promise<unknown>;
}

interface Values {
  duration: string;
  price: string;
}

const WHOLE = /^\d+$/;

/** Duration and price of one service in one branch. A field the role cannot edit is shown as plain text, not as a disabled input. */
export function BranchOverrideFields({
  service,
  override,
  branchName,
  canEditDuration,
  canEditPrice,
  onSubmit,
  onReset,
}: BranchOverrideFieldsProps) {
  const { t } = useTranslation(["appointments", "errors"]);
  const [unchanged, setUnchanged] = useState(false);
  const initialDuration = override?.duration_minutes ?? null;
  const initialPrice = override?.price_minor ?? null;
  const form = useForm<Values>({
    defaultValues: {
      duration: initialDuration === null ? "" : String(initialDuration),
      price: initialPrice === null ? "" : minorToInput(initialPrice),
    },
  });

  const durationValid = (value: string) =>
    value.trim() === "" || (WHOLE.test(value.trim()) && Number(value) > 0)
      ? true
      : t("catalog.override.errors.durationInvalid");
  const priceValid = (value: string) =>
    value.trim() === "" || parsePriceToMinor(value) !== null
      ? true
      : t("catalog.override.errors.priceInvalid");

  const submit = form.handleSubmit(async (values) => {
    const change: ServiceOverrideInput = {};
    if (canEditDuration) {
      const next = values.duration.trim() === "" ? null : Number(values.duration);
      if (next !== initialDuration) change.duration_minutes = next;
    }
    if (canEditPrice) {
      const next = values.price.trim() === "" ? null : parsePriceToMinor(values.price);
      if (next !== initialPrice) change.price_minor = next;
    }
    setUnchanged(Object.keys(change).length === 0);
    if (Object.keys(change).length === 0) return;
    try {
      await onSubmit(change);
    } catch (error) {
      reportSubmitError(error, form.setError, t, {
        duration_minutes: "duration",
        price_minor: "price",
      });
    }
  });

  const reset = async () => {
    try {
      await onReset?.();
    } catch (error) {
      reportSubmitError(error, form.setError, t);
    }
  };

  const effectiveDuration = initialDuration ?? service.duration_minutes;
  const effectivePrice = initialPrice ?? service.price_minor;
  const editable = canEditDuration || canEditPrice;

  return (
    <section
      aria-label={t("catalog.override.title", { branch: branchName })}
      className="grid gap-4"
    >
      <div className="grid gap-1">
        <h3 className="font-display text-base font-semibold">
          {t("catalog.override.title", { branch: branchName })}
        </h3>
        <p className="text-sm text-muted-foreground">{t("catalog.override.description")}</p>
      </div>

      <Form {...form}>
        <form onSubmit={submit} noValidate className="grid gap-4">
          {canEditDuration ? (
            <FormField
              control={form.control}
              name="duration"
              rules={{ validate: durationValid }}
              render={({ field }) => (
                <FormItem>
                  <FormLabel>{t("catalog.override.duration")}</FormLabel>
                  <FormControl>
                    <Input
                      {...field}
                      inputMode="numeric"
                      autoComplete="off"
                      placeholder={t("catalog.override.durationPlaceholder", {
                        value: service.duration_minutes,
                      })}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
          ) : (
            <ReadOnlyValue
              label={t("catalog.override.duration")}
              value={t("catalog.services.minutes", { count: effectiveDuration })}
            />
          )}

          {canEditPrice ? (
            <FormField
              control={form.control}
              name="price"
              rules={{ validate: priceValid }}
              render={({ field }) => (
                <FormItem>
                  <FormLabel>
                    {t("catalog.override.price", { currency: service.currency })}
                  </FormLabel>
                  <FormControl>
                    <Input
                      {...field}
                      inputMode="decimal"
                      autoComplete="off"
                      placeholder={t("catalog.override.pricePlaceholder", {
                        value: formatCurrency(service.price_minor / 100, service.currency),
                      })}
                    />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
          ) : (
            <ReadOnlyValue
              label={t("catalog.override.priceReadOnly")}
              value={formatCurrency(effectivePrice / 100, service.currency)}
              hint={editable ? t("catalog.override.priceReadOnlyHint") : undefined}
            />
          )}

          {unchanged ? (
            <p role="status" className="text-sm text-muted-foreground">
              {t("catalog.override.nothingChanged")}
            </p>
          ) : null}
          <FormAlert>{form.formState.errors.root?.serverError?.message}</FormAlert>

          {editable ? (
            <div className="flex flex-wrap gap-2">
              <Button type="submit" loading={form.formState.isSubmitting}>
                {t("catalog.override.save")}
              </Button>
              {onReset && override && canEditDuration && canEditPrice ? (
                <Button type="button" variant="outline" onClick={reset}>
                  {t("catalog.override.reset")}
                </Button>
              ) : null}
            </div>
          ) : null}
        </form>
      </Form>
    </section>
  );
}

function ReadOnlyValue({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="grid gap-1">
      <p className="text-sm font-medium">{label}</p>
      <p className="text-sm tabular-nums">{value}</p>
      {hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
    </div>
  );
}

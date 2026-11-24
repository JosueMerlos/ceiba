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
  useFormField,
} from "@ceiba/ui";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMemo } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
import type { TimeOffInput } from "../api/shared";
import { BranchDatePicker, BranchTimeField } from "../../../platform/forms/branch-fields";
import { reportSubmitError } from "../../../platform/forms/report-submit-error";
import { localToUtcIso } from "../lib/zoned-time";
import { FormAlert } from "./form-alert";

const REASON_MAX = 200;
// Date and time are picked apart: a half-filled pair ("2026-12-14T") must not pass as a value.
const WALL_CLOCK = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/;

interface TimeOffFormProps {
  /** IANA zone of the branch: the dates are typed in ITS wall-clock time, whatever zone the browser is in. */
  timeZone: string;
  /** Rejects with the API error; the form shows it. Receives UTC instants, as the contract wants them. */
  onSubmit(values: TimeOffInput): Promise<unknown>;
}

export function TimeOffForm({ timeZone, onSubmit }: TimeOffFormProps) {
  const { t } = useTranslation(["appointments", "errors"]);

  const schema = useMemo(
    () =>
      z
        .object({
          start: z.string().regex(WALL_CLOCK, t("catalog.timeOffForm.errors.startRequired")),
          end: z.string().regex(WALL_CLOCK, t("catalog.timeOffForm.errors.endRequired")),
          reason: z.string().max(REASON_MAX, t("catalog.timeOffForm.errors.reasonTooLong")),
        })
        .superRefine((values, ctx) => {
          const start = localToUtcIso(values.start, timeZone);
          const end = localToUtcIso(values.end, timeZone);
          if (start && end && end <= start) {
            ctx.addIssue({
              code: "custom",
              path: ["end"],
              message: t("catalog.timeOffForm.errors.endBeforeStart"),
            });
          }
        }),
    [t, timeZone],
  );

  const form = useForm<z.infer<typeof schema>>({
    resolver: zodResolver(schema),
    defaultValues: { start: "", end: "", reason: "" },
  });

  const submit = form.handleSubmit(async (values) => {
    try {
      await onSubmit({
        starts_at: localToUtcIso(values.start, timeZone)!,
        ends_at: localToUtcIso(values.end, timeZone)!,
        reason: values.reason.trim() || null,
      });
      form.reset();
    } catch (error) {
      reportSubmitError(error, form.setError, t, {
        starts_at: "start",
        ends_at: "end",
        reason: "reason",
      });
    }
  });

  return (
    <Form {...form}>
      <form onSubmit={submit} noValidate className="grid gap-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="start"
            render={({ field }) => (
              <FormItem>
                <WallClockField
                  legend={t("catalog.timeOffForm.start")}
                  value={field.value}
                  onChange={field.onChange}
                  onBlur={field.onBlur}
                  timeZone={timeZone}
                />
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="end"
            render={({ field }) => (
              <FormItem>
                <WallClockField
                  legend={t("catalog.timeOffForm.end")}
                  value={field.value}
                  onChange={field.onChange}
                  onBlur={field.onBlur}
                  timeZone={timeZone}
                />
                <FormMessage />
              </FormItem>
            )}
          />
        </div>
        <p className="text-sm text-muted-foreground">
          {t("catalog.timeOffForm.zoneHint", { timeZone })}
        </p>
        <FormField
          control={form.control}
          name="reason"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.timeOffForm.reason")}</FormLabel>
              <FormControl>
                <Input {...field} autoComplete="off" />
              </FormControl>
              <FormDescription>{t("catalog.timeOffForm.reasonHint")}</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormAlert>{form.formState.errors.root?.serverError?.message}</FormAlert>

        <div>
          <Button type="submit" variant="outline" loading={form.formState.isSubmitting}>
            {t("catalog.timeOffForm.create")}
          </Button>
        </div>
      </form>
    </Form>
  );
}

interface WallClockFieldProps {
  legend: string;
  /** "yyyy-MM-ddTHH:mm" in the branch's wall-clock time; either half may still be empty. */
  value: string;
  onChange(value: string): void;
  onBlur(): void;
  timeZone: string;
}

function WallClockField({ legend, value, onChange, onBlur, timeZone }: WallClockFieldProps) {
  const { t } = useTranslation("common");
  const { error, formMessageId } = useFormField();
  const [day = "", clock = ""] = value.split("T");
  const describedBy = error ? formMessageId : undefined;
  return (
    <fieldset className="grid gap-2" aria-describedby={describedBy}>
      <legend className="mb-2 text-sm leading-none font-medium">{legend}</legend>
      <div className="grid grid-cols-[minmax(0,1fr)_minmax(0,9rem)] gap-2">
        <BranchDatePicker
          aria-label={t("fields.date")}
          aria-invalid={error ? true : undefined}
          value={day}
          onChange={(next) => onChange(`${next}T${clock}`)}
          timeZone={timeZone}
        />
        <BranchTimeField
          aria-label={t("fields.time")}
          aria-invalid={error ? true : undefined}
          value={clock}
          onChange={(next) => onChange(`${day}T${next}`)}
          onBlur={onBlur}
        />
      </div>
    </fieldset>
  );
}

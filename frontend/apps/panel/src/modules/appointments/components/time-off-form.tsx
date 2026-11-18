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
} from "@ceiba/ui";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMemo } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
import type { TimeOffInput } from "../api/professionals";
import { reportSubmitError } from "../lib/report-submit-error";
import { localToUtcIso } from "../lib/zoned-time";
import { FormAlert } from "./form-alert";

const REASON_MAX = 200;

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
          start: z.string().min(1, t("catalog.timeOffForm.errors.startRequired")),
          end: z.string().min(1, t("catalog.timeOffForm.errors.endRequired")),
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
                <FormLabel>{t("catalog.timeOffForm.start")}</FormLabel>
                <FormControl>
                  <Input {...field} type="datetime-local" />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="end"
            render={({ field }) => (
              <FormItem>
                <FormLabel>{t("catalog.timeOffForm.end")}</FormLabel>
                <FormControl>
                  <Input {...field} type="datetime-local" />
                </FormControl>
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

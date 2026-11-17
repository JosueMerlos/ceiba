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
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ceiba/ui";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMemo } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { reportSubmitError } from "../lib/report-submit-error";
import { TIME_ZONES } from "../lib/time-zones";
import { FormAlert } from "./form-alert";

export interface BranchFormValues {
  name: string;
  time_zone: string;
}

interface BranchFormProps {
  /** The context branch's zone: companies have none, so a new branch most likely shares its sibling's. */
  defaultTimeZone: string;
  onSubmit(values: BranchFormValues): Promise<unknown>;
}

export function BranchForm({ defaultTimeZone, onSubmit }: BranchFormProps) {
  const { t } = useTranslation(["appointments", "errors"]);
  const schema = useMemo(
    () =>
      z.object({
        name: z.string().trim().min(1, t("catalog.branchForm.errors.nameRequired")),
        time_zone: z.string().min(1),
      }),
    [t],
  );
  const form = useForm<z.infer<typeof schema>>({
    resolver: zodResolver(schema),
    defaultValues: { name: "", time_zone: defaultTimeZone },
  });

  const zones: readonly string[] = (TIME_ZONES as readonly string[]).includes(defaultTimeZone)
    ? TIME_ZONES
    : [defaultTimeZone, ...TIME_ZONES];

  const submit = form.handleSubmit(async (values) => {
    try {
      await onSubmit({ name: values.name.trim(), time_zone: values.time_zone });
    } catch (error) {
      reportSubmitError(error, form.setError, t, { name: "name", time_zone: "time_zone" });
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
              <FormLabel>{t("catalog.branchForm.name")}</FormLabel>
              <FormControl>
                <Input {...field} autoComplete="off" />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="time_zone"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.branchForm.timeZone")}</FormLabel>
              <Select value={field.value} onValueChange={field.onChange}>
                <FormControl>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                </FormControl>
                <SelectContent>
                  {zones.map((zone) => (
                    <SelectItem key={zone} value={zone}>
                      {zone}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <FormDescription>{t("catalog.branchForm.timeZoneHint")}</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormAlert>{form.formState.errors.root?.serverError?.message}</FormAlert>

        <Button type="submit" loading={form.formState.isSubmitting}>
          {t("catalog.branchForm.create")}
        </Button>
      </form>
    </Form>
  );
}

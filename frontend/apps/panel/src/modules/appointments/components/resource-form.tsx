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
  Switch,
} from "@ceiba/ui";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMemo } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
import { RESOURCE_KINDS, type Resource, type ResourceKind } from "../api/resources";
import { reportSubmitError } from "../lib/report-submit-error";
import { FormAlert } from "./form-alert";

export interface ResourceFormValues {
  name: string;
  kind: ResourceKind;
  active: boolean;
}

interface ResourceFormProps {
  /** Absent = create. */
  resource?: Resource;
  readOnly?: boolean;
  onSubmit(values: ResourceFormValues): Promise<unknown>;
}

export function ResourceForm({ resource, readOnly = false, onSubmit }: ResourceFormProps) {
  const { t } = useTranslation(["appointments", "errors"]);
  const schema = useMemo(
    () =>
      z.object({
        name: z.string().trim().min(1, t("catalog.resourceForm.errors.nameRequired")),
        kind: z.enum(RESOURCE_KINDS as [ResourceKind, ...ResourceKind[]]),
        active: z.boolean(),
      }),
    [t],
  );
  const form = useForm<z.infer<typeof schema>>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: resource?.name ?? "",
      kind: resource?.kind ?? "chair",
      active: resource?.active ?? true,
    },
  });

  const submit = form.handleSubmit(async (values) => {
    try {
      await onSubmit({ name: values.name.trim(), kind: values.kind, active: values.active });
    } catch (error) {
      reportSubmitError(error, form.setError, t, { name: "name", kind: "kind", active: "active" });
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
              <FormLabel>{t("catalog.resourceForm.name")}</FormLabel>
              <FormControl>
                <Input {...field} disabled={readOnly} autoComplete="off" />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="kind"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("catalog.resourceForm.kind")}</FormLabel>
              <Select value={field.value} onValueChange={field.onChange} disabled={readOnly}>
                <FormControl>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                </FormControl>
                <SelectContent>
                  {RESOURCE_KINDS.map((kind) => (
                    <SelectItem key={kind} value={kind}>
                      {t(`catalog.resources.kinds.${kind}`)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
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
                <FormLabel>{t("catalog.resourceForm.active")}</FormLabel>
                <FormControl>
                  <Switch
                    checked={field.value}
                    onCheckedChange={field.onChange}
                    disabled={readOnly}
                  />
                </FormControl>
              </div>
              <FormDescription>{t("catalog.resourceForm.activeHint")}</FormDescription>
            </FormItem>
          )}
        />

        <FormAlert>{form.formState.errors.root?.serverError?.message}</FormAlert>

        {readOnly ? null : (
          <Button type="submit" loading={form.formState.isSubmitting}>
            {resource ? t("catalog.resourceForm.save") : t("catalog.resourceForm.create")}
          </Button>
        )}
      </form>
    </Form>
  );
}

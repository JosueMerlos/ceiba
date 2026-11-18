import {
  isApiError,
  useBrandingQuery,
  useUpdateBrandingMutation,
  type Branding,
  type BrandingFile,
} from "@ceiba/api-client";
import { analyzeBranding, readSurfaces } from "@ceiba/branding";
import { loadBrandFont } from "@ceiba/branding/react";
import { translator, useTranslation } from "@ceiba/i18n";
import { Button, ContextPanel, Form, LoadingState, PageHeader, toast } from "@ceiba/ui";
import { PanelRightClose, PanelRightOpen } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { describeError } from "../errors/global-errors";
import { ForbiddenPage, NotFoundPage } from "../errors/status-pages";
import { useCan } from "../permissions/can";
import { AsidePortal } from "../shell/aside-slot";
import { useMe } from "../me/me-provider";
import { BrandingEditPanel } from "./branding-edit-panel";
import {
  FILE_MAX_BYTES,
  formFieldFor,
  savedAssetUrl,
  toBrandingInput,
  toChanges,
  toFormValues,
  type BrandingFormValues,
} from "./branding-form";
import { BrandingPreview } from "./branding-preview";
import { useBrandingFiles } from "./use-branding-files";

export const BRANDING_PERMISSION = "platform.branding.update";
const PANEL_ID = "branding-edit-panel";
const FORM_ID = "branding-form";

/** /settings/branding: guards on the permission (the API checks it again) and loads what is saved. */
export function BrandingPage() {
  const { context } = useMe();
  const allowed = useCan()(BRANDING_PERMISSION);
  const { organization, company } = context;
  const query = useBrandingQuery(organization?.id, company?.id, { enabled: allowed });
  const { t } = useTranslation("common");

  if (!allowed) return <ForbiddenPage />;
  if (!organization || !company) return <NotFoundPage />;
  if (!query.data) return <LoadingState label={t("loading")} />;

  return (
    <BrandingEditor
      saved={query.data.data}
      target={{ organizationId: organization.id, companyId: company.id, slug: company.slug }}
      companyName={company.name}
    />
  );
}

interface BrandingEditorProps {
  saved: Branding;
  target: { organizationId: string; companyId: string; slug: string };
  companyName: string;
}

function BrandingEditor({ saved, target, companyName }: BrandingEditorProps) {
  const { t } = useTranslation(["branding", "errors"]);
  const form = useForm<BrandingFormValues>({ defaultValues: toFormValues(saved) });
  const files = useBrandingFiles();
  const update = useUpdateBrandingMutation(target);
  const [expanded, setExpanded] = useState(true);
  const [unmapped, setUnmapped] = useState<unknown>(null);

  const values = useWatch({ control: form.control });
  const [surfaces] = useState(() => readSurfaces(document.documentElement));
  const analysis = useMemo(
    () => analyzeBranding(toBrandingInput(values as BrandingFormValues), surfaces),
    [values, surfaces],
  );

  // Fonts the user already chose are needed by the preview as soon as they are picked.
  const font = values.fontChoice;
  useEffect(() => {
    if (font) void loadBrandFont(font);
  }, [font]);

  const preview = (name: "logo" | "banner" | "favicon") => {
    if (files.chosen[name]) return files.chosen[name].url;
    return files.removed.includes(name) ? null : savedAssetUrl(saved, name);
  };
  const previews = {
    logo: preview("logo"),
    banner: preview("banner"),
    favicon: preview("favicon"),
  };

  const onSubmit = form.handleSubmit((submitted) => {
    setUnmapped(null);
    if (!withinSizeLimits()) return;
    const removed = files.removed.filter((name) => saved.assets[name] !== null);
    update.mutate(toChanges(submitted, files.files, removed), {
      onSuccess: (response) => {
        form.reset(toFormValues(response.data));
        files.reset();
        toast.success(t("branding:actions.saved"));
      },
      onError: (error) => showServerErrors(error),
    });
  });

  // Blocks the submit when a chosen file is over its kind's limit, with the same message the API's 422 would give.
  function withinSizeLimits() {
    const tooBig = (Object.keys(files.files) as BrandingFile[]).filter(
      (kind) => files.files[kind]!.size > FILE_MAX_BYTES[kind],
    );
    tooBig.forEach((kind, index) =>
      form.setError(
        kind,
        { type: "client", message: t("branding:errors.code.file_too_large") },
        { shouldFocus: index === 0 },
      ),
    );
    return tooBig.length === 0;
  }

  // 413: the whole body was refused (by the API or by the proxy), so no field is to blame; it is shown as a general message.
  // 422: each error goes under its field and the first one takes focus; anything else is a general message.
  function showServerErrors(error: unknown) {
    if (isApiError(error) && error.status === 413) return setUnmapped(error);
    if (!isApiError(error) || error.status !== 422) return;
    const translate = translator(t);
    let leftover = false;
    error.errors.forEach((fieldError, index) => {
      const name = formFieldFor(fieldError.field);
      if (!name) {
        leftover = true;
        return;
      }
      const isColor = name.endsWith("Color") && fieldError.code === "invalid";
      const message = isColor
        ? t("branding:errors.invalidColor")
        : translate(`branding:errors.code.${fieldError.code}`, {
            defaultValue: fieldError.message,
          });
      form.setError(name, { type: "server", message }, { shouldFocus: index === 0 });
    });
    if (leftover) setUnmapped(error);
  }

  const name = (values.brandName ?? "").trim() || companyName;
  const roles = analysis.notices.darkText;

  return (
    <Form {...form}>
      <PageHeader
        title={t("branding:title")}
        description={t("branding:description", { company: companyName })}
        actions={
          <div className="flex items-center gap-2">
            <Button
              type="button"
              variant="outline"
              aria-expanded={expanded}
              aria-controls={PANEL_ID}
              onClick={() => setExpanded((current) => !current)}
            >
              {expanded ? (
                <PanelRightClose aria-hidden="true" />
              ) : (
                <PanelRightOpen aria-hidden="true" />
              )}
              {expanded ? t("branding:panel.collapse") : t("branding:panel.expand")}
            </Button>
            {/* The fields live in the aside, outside this DOM subtree, so the button calls the submit itself. */}
            <Button type="button" loading={update.isPending} onClick={onSubmit}>
              {update.isPending ? t("branding:actions.saving") : t("branding:actions.save")}
            </Button>
          </div>
        }
      />

      <div className="grid min-w-0 gap-6">
        <BrandingPreview
          vars={analysis.vars}
          name={name}
          tagline={values.tagline ?? ""}
          logoUrl={previews.logo}
          bannerUrl={previews.banner}
        />

        <div role="status" className="grid gap-2 empty:hidden">
          {roles.map((role) => (
            <p
              key={role}
              className="rounded-lg border bg-secondary px-3.5 py-2.5 text-sm text-secondary-foreground"
            >
              {t("branding:notices.darkText", { role: t(`branding:notices.roles.${role}`) })}
            </p>
          ))}
          {analysis.notices.unreadable.map((role) => (
            <p
              key={`unreadable-${role}`}
              className="rounded-lg border bg-secondary px-3.5 py-2.5 text-sm text-secondary-foreground"
            >
              {t("branding:notices.unreadable", { role: t(`branding:notices.roles.${role}`) })}
            </p>
          ))}
          {analysis.notices.ringFallback ? (
            <p className="rounded-lg border bg-secondary px-3.5 py-2.5 text-sm text-secondary-foreground">
              {t("branding:notices.ringFallback")}
            </p>
          ) : null}
        </div>

        {unmapped ? (
          <p
            role="alert"
            className="rounded-lg border border-destructive/30 bg-destructive/5 px-3.5 py-2.5 text-sm font-medium text-destructive"
          >
            {describeError(unmapped, t)}
          </p>
        ) : null}
      </div>

      {/* Unmounted when closed: values and errors live in the form and the files in `files`, so reopening restores them. */}
      {expanded ? (
        <AsidePortal>
          <ContextPanel
            id={PANEL_ID}
            open
            onOpenChange={(open) => setExpanded(open)}
            title={t("branding:panel.title")}
            closeLabel={t("branding:panel.close")}
          >
            {/* Native form so Enter in a field saves; Form above is only the react-hook-form context. */}
            <form id={FORM_ID} onSubmit={onSubmit} noValidate>
              {/* A form with several text fields only submits on Enter when it has a submit button. */}
              <button type="submit" tabIndex={-1} aria-hidden="true" className="sr-only" />
              <BrandingEditPanel
                previews={previews}
                onSelectFile={(name, file) => files.select(name, file)}
                onRemoveFile={files.remove}
              />
            </form>
          </ContextPanel>
        </AsidePortal>
      ) : null}
    </Form>
  );
}

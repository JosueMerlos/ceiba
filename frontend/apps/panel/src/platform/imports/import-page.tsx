import { isApiError } from "@ceiba/api-client";
import { formatDateTime, translator, useTranslation } from "@ceiba/i18n";
import { Button, Label, PageHeader, buttonVariants, cn } from "@ceiba/ui";
import { ChevronLeft, Download, FileUp, TriangleAlert } from "lucide-react";
import { useId, useState, type ReactNode } from "react";
import { Link } from "react-router";
import { describeError } from "../errors/global-errors";
import { ForbiddenPage } from "../errors/status-pages";
import { useMe } from "../me/me-provider";
import { BranchPicker } from "../ui/branch-picker";
import { useWorkingBranch } from "../context/use-working-branch";
import {
  RUNNING,
  readAsBase64,
  useConfirmImport,
  useImportProgress,
  useRejectedRows,
  useUploadImport,
  type DuplicateMode,
  type ImportBatch,
  type ImportRow,
} from "./api";
import { IMPORT_KINDS, importKindsFor, type ImportKind } from "./kinds";

const MAX_BYTES = 5 * 1024 * 1024;
const templateOf = (kind: ImportKind) => IMPORT_KINDS.find((item) => item.key === kind)!.template;

/** /customers/import: upload a CSV, review what would happen, confirm, and follow the job to its report. */
export function ImportPage() {
  const { t } = useTranslation("imports");
  const me = useMe();
  const working = useWorkingBranch();
  const kinds = importKindsFor(me);
  if (kinds.length === 0) return <ForbiddenPage />;

  return (
    <div className="grid max-w-4xl gap-6">
      <Link
        to="/customers"
        className="flex w-max items-center gap-1 text-sm font-semibold text-primary hover:underline"
      >
        <ChevronLeft aria-hidden="true" className="size-4" />
        {t("back")}
      </Link>
      <PageHeader title={t("title")} description={t("description")} />
      {working.needsChoice ? (
        <BranchPicker
          branches={working.branches}
          value={working.branch?.id ?? null}
          onChange={working.choose}
        />
      ) : null}
      {working.branch ? (
        <ImportFlow
          key={working.branch.id}
          branchId={working.branch.id}
          timeZone={working.branch.time_zone}
          kinds={kinds.map((kind) => kind.key)}
        />
      ) : null}
    </div>
  );
}

interface ImportFlowProps {
  branchId: string;
  timeZone: string;
  kinds: readonly ImportKind[];
}

function ImportFlow({ branchId, timeZone, kinds }: ImportFlowProps) {
  const { t } = useTranslation(["imports", "errors"]);
  const [kind, setKind] = useState<ImportKind | null>(kinds.length === 1 ? kinds[0]! : null);
  const [fileError, setFileError] = useState<string | null>(null);
  const [preview, setPreview] = useState<ImportBatch | null>(null);
  const [confirmed, setConfirmed] = useState<ImportBatch | null>(null);
  const upload = useUploadImport(branchId);
  const progress = useImportProgress(branchId, confirmed);
  const current = progress.data?.data ?? confirmed;

  function restart() {
    setPreview(null);
    setConfirmed(null);
    setFileError(null);
    upload.reset();
  }

  async function choose(file: File) {
    restart();
    if (!kind) return;
    if (file.size > MAX_BYTES) {
      setFileError(t("tooLarge"));
      return;
    }
    try {
      const result = await upload.mutateAsync({ kind, content_base64: await readAsBase64(file) });
      setPreview(result.data);
    } catch (error) {
      setFileError(isApiError(error) && error.detail ? error.detail : describeError(error, t));
    }
  }

  if (current) return <Outcome batch={current} onRestart={restart} />;

  return (
    <>
      <KindChooser
        kinds={kinds}
        value={kind}
        onChange={(next) => {
          restart();
          setKind(next);
        }}
      />
      {kind ? (
        <FileChooser disabled={upload.isPending} onChoose={(file) => void choose(file)} />
      ) : null}
      {upload.isPending ? <p className="text-muted-foreground">{t("reading")}</p> : null}
      {fileError ? <Alert>{fileError}</Alert> : null}
      {preview ? (
        <Preview
          batch={preview}
          branchId={branchId}
          timeZone={timeZone}
          onConfirmed={setConfirmed}
        />
      ) : null}
    </>
  );
}

function KindChooser({
  kinds,
  value,
  onChange,
}: {
  kinds: readonly ImportKind[];
  value: ImportKind | null;
  onChange(kind: ImportKind): void;
}) {
  const { t } = useTranslation("imports");
  return (
    <fieldset className="grid gap-3">
      <legend id="import-kind" className="mb-2 font-semibold">
        {t("kindLabel")}
      </legend>
      <div role="radiogroup" aria-labelledby="import-kind" className="flex flex-wrap gap-2">
        {kinds.map((kind) => (
          <label
            key={kind}
            className={cn(
              "flex cursor-pointer items-center gap-2 rounded-lg border px-3.5 py-2 font-medium has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring",
              value === kind && "border-primary bg-accent text-accent-foreground",
            )}
          >
            <input
              type="radio"
              name="import-kind"
              value={kind}
              checked={value === kind}
              onChange={() => onChange(kind)}
              className="accent-primary"
            />
            {t(`kinds.${kind}`)}
          </label>
        ))}
      </div>
      {value ? (
        <p className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
          <a
            href={`/import-templates/${templateOf(value)}`}
            download
            className="inline-flex items-center gap-1 font-semibold text-primary hover:underline"
          >
            <Download aria-hidden="true" className="size-4" />
            {t(`template.${value}`)}
          </a>
          <span>{t("templateHint")}</span>
        </p>
      ) : null}
    </fieldset>
  );
}

// The native input stays in the tab order (visually hidden) and its visible label shows the focus: the browser's own
// "choose file" text would come in the browser's language, not the panel's.
function FileChooser({ disabled, onChoose }: { disabled: boolean; onChoose(file: File): void }) {
  const { t } = useTranslation("imports");
  const id = useId();
  const [name, setName] = useState<string | null>(null);
  return (
    <div className="grid max-w-md gap-1.5">
      <Label htmlFor={id}>{t("file")}</Label>
      <div className="flex flex-wrap items-center gap-3 rounded-lg border border-dashed bg-card p-3">
        <input
          id={id}
          type="file"
          accept=".csv,text/csv"
          disabled={disabled}
          onChange={(event) => {
            const file = event.target.files?.[0];
            event.target.value = "";
            if (!file) return;
            setName(file.name);
            onChoose(file);
          }}
          className="peer sr-only"
        />
        <label
          htmlFor={id}
          aria-hidden="true"
          className={cn(
            buttonVariants({ variant: "outline", size: "sm" }),
            "cursor-pointer peer-focus-visible:ring-2 peer-focus-visible:ring-ring peer-disabled:pointer-events-none peer-disabled:opacity-50",
          )}
        >
          <FileUp aria-hidden="true" />
          {t("choose")}
        </label>
        <span className="min-w-0 truncate text-sm text-muted-foreground">
          {name ?? t("noFile")}
        </span>
      </div>
    </div>
  );
}

function Preview({
  batch,
  branchId,
  timeZone,
  onConfirmed,
}: {
  batch: ImportBatch;
  branchId: string;
  timeZone: string;
  onConfirmed(batch: ImportBatch): void;
}) {
  const { t } = useTranslation(["imports", "errors"]);
  // The server lists the modes the kind accepts, the safest one first.
  const [mode, setMode] = useState<DuplicateMode>(batch.duplicate_modes[0]!);
  const confirm = useConfirmImport(branchId);
  const rejected = useRejectedRows(branchId, batch);

  return (
    <div className="grid gap-6">
      <section aria-labelledby="import-summary" className="grid gap-2 rounded-2xl border p-4">
        <h2 id="import-summary" className="font-display text-lg font-semibold">
          {t("summary.title")}
        </h2>
        <p className="font-semibold text-primary">
          {t("summary.ready", { count: batch.ready_count })}
        </p>
        {batch.rejected_count > 0 ? (
          <p className="font-semibold text-destructive">
            {t("summary.rejected", { count: batch.rejected_count })}
          </p>
        ) : null}
        <p className="text-sm text-muted-foreground">
          {t("summary.expires", { date: formatDateTime(batch.expires_at, timeZone) })}
        </p>
      </section>

      {batch.warnings.map((warning) => (
        <Alert key={warning} tone="warning">
          {t(`warnings.${warning}`)}
        </Alert>
      ))}

      {batch.rejected_count > 0 && rejected.data ? (
        <section className="grid gap-2">
          <h2 id="import-errors" className="font-semibold">
            {t("errorsTitle")}
          </h2>
          <ul
            aria-labelledby="import-errors"
            className="grid max-h-72 gap-1 overflow-y-auto rounded-lg border p-3 text-sm"
          >
            {rejected.data.data.map((row) => (
              <li key={row.row_number}>{errorLine(row, t)}</li>
            ))}
          </ul>
        </section>
      ) : null}

      <PreviewTable batch={batch} />

      {batch.ready_count === 0 ? (
        <Alert>{t("nothingToImport")}</Alert>
      ) : (
        <div className="grid gap-4">
          {batch.duplicate_modes.length > 1 ? (
            <ModeChooser modes={batch.duplicate_modes} value={mode} onChange={setMode} />
          ) : null}
          {confirm.isError ? <Alert>{describeError(confirm.error, t)}</Alert> : null}
          <Button
            type="button"
            className="justify-self-start"
            disabled={confirm.isPending}
            onClick={() =>
              confirm.mutate(
                { id: batch.id, mode },
                { onSuccess: (result) => onConfirmed(result.data) },
              )
            }
          >
            {t("confirm", { count: batch.ready_count })}
          </Button>
        </div>
      )}
    </div>
  );
}

function errorLine(row: ImportRow, t: ReturnType<typeof useTranslation>["t"]) {
  const translate = translator(t);
  return Object.entries(row.error_codes)
    .map(([column, code]) =>
      translate("imports:errorLine", {
        row: row.row_number,
        column: translate(`imports:columns.${column}`, { defaultValue: column }),
        reason: translate(`imports:reasonsByColumn.${column}.${code}`, {
          defaultValue: translate(`imports:reasons.${code}`, {
            defaultValue: translate("imports:reasons.other"),
          }),
        }),
      }),
    )
    .join(" ");
}

function PreviewTable({ batch }: { batch: ImportBatch }) {
  const { t } = useTranslation("imports");
  const translate = translator(t);
  if (batch.preview.length === 0) return null;
  return (
    <section aria-labelledby="import-preview" className="grid gap-2">
      <h2 id="import-preview" className="font-semibold">
        {t("preview.title")}
      </h2>
      <div className="overflow-x-auto rounded-lg border">
        <table className="w-full min-w-[32rem] text-sm">
          <thead className="bg-muted/60 text-left text-xs text-muted-foreground">
            <tr>
              <th scope="col" className="px-3 py-2 font-semibold">
                {t("preview.row")}
              </th>
              {batch.columns.map((column) => (
                <th key={column} scope="col" className="px-3 py-2 font-semibold">
                  {translate(`imports:columns.${column}`, { defaultValue: column })}
                </th>
              ))}
              <th scope="col" className="px-3 py-2 font-semibold">
                {t("preview.status")}
              </th>
            </tr>
          </thead>
          <tbody>
            {batch.preview.map((row) => (
              <tr key={row.row_number} className="border-t">
                <td className="px-3 py-2 tabular-nums text-muted-foreground">{row.row_number}</td>
                {batch.columns.map((column) => (
                  <td
                    key={column}
                    className={cn(
                      "px-3 py-2",
                      row.error_codes[column] && "font-semibold text-destructive",
                    )}
                  >
                    {row.values?.[column] ?? ""}
                  </td>
                ))}
                <td className="px-3 py-2">
                  {t(row.status === "rejected" ? "preview.rejected" : "preview.ready")}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function ModeChooser({
  modes,
  value,
  onChange,
}: {
  modes: readonly DuplicateMode[];
  value: DuplicateMode;
  onChange(mode: DuplicateMode): void;
}) {
  const { t } = useTranslation("imports");
  return (
    <fieldset className="grid gap-2">
      <legend className="mb-1 font-semibold">{t("duplicates.label")}</legend>
      {modes.map((mode) => (
        <label key={mode} className="flex cursor-pointer items-start gap-2.5">
          <input
            type="radio"
            name="duplicate-mode"
            value={mode}
            checked={value === mode}
            onChange={() => onChange(mode)}
            className="mt-1 accent-primary"
          />
          <span className="grid gap-0.5">
            <span className="font-medium">{t(`duplicates.${mode}`)}</span>
            <span className="text-sm text-muted-foreground">{t(`duplicates.${mode}Hint`)}</span>
          </span>
        </label>
      ))}
    </fieldset>
  );
}

function Outcome({ batch, onRestart }: { batch: ImportBatch; onRestart(): void }) {
  const { t } = useTranslation("imports");
  if (RUNNING.includes(batch.status)) {
    const done =
      batch.created_count +
      batch.updated_count +
      batch.restored_count +
      batch.skipped_count +
      batch.failed_count;
    return (
      <p role="status" className="font-semibold">
        {t("progress", { done, total: done + batch.ready_count })}
      </p>
    );
  }
  if (batch.status === "expired") return <Alert>{t("report.expired")}</Alert>;

  const lines = (
    [
      ["created", batch.created_count],
      ["updated", batch.updated_count],
      ["restored", batch.restored_count],
      ["skipped", batch.skipped_count],
      ["failedRows", batch.failed_count],
      ["rejected", batch.rejected_count],
    ] as const
  ).filter(([, count]) => count > 0);

  return (
    <section aria-labelledby="import-report" className="grid gap-3 rounded-2xl border p-4">
      <h2 id="import-report" className="font-display text-lg font-semibold">
        {batch.status === "completed" ? t("report.done") : t("report.failed")}
      </h2>
      <ul className="grid gap-1">
        {lines.map(([key, count]) => (
          <li key={key}>{t(`report.${key}`, { count })}</li>
        ))}
      </ul>
      <div className="flex flex-wrap gap-2">
        <Button type="button" variant="outline" onClick={onRestart}>
          {t("report.another")}
        </Button>
        <Link
          to="/customers"
          className="inline-flex items-center px-2 font-semibold text-primary hover:underline"
        >
          {t("report.toCustomers")}
        </Link>
      </div>
    </section>
  );
}

function Alert({ children, tone = "error" }: { children: ReactNode; tone?: "error" | "warning" }) {
  return (
    <p
      role={tone === "error" ? "alert" : "note"}
      className={cn(
        "flex items-start gap-2 rounded-lg border p-3 text-sm",
        tone === "error" ? "border-destructive/30 bg-destructive/5 text-destructive" : "bg-muted",
      )}
    >
      <TriangleAlert aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
      <span>{children}</span>
    </p>
  );
}

import type { AnyTranslate } from "@ceiba/i18n";
import type { FieldValues, UseFormSetError } from "react-hook-form";
import { applyApiErrors } from "../../../platform/forms/apply-api-errors";
import { describeError } from "../../../platform/errors/global-errors";

/**
 * Puts a failed submit into the form: a 422 lands on its fields; anything else (403, 5xx, network) becomes the form-level
 * error, so no failure is left to a toast the user may not see.
 */
export function reportSubmitError<T extends FieldValues>(
  error: unknown,
  setError: UseFormSetError<T>,
  translate: AnyTranslate,
  fieldMap?: Readonly<Record<string, string>>,
) {
  if (applyApiErrors(error, setError, fieldMap)) return;
  (setError as (name: string, error: { type: string; message: string }) => void)(
    "root.serverError",
    { type: "server", message: describeError(error, translate) },
  );
}

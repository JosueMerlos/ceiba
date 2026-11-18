import { isApiError } from "@ceiba/api-client";
import type { FieldValues, UseFormSetError } from "react-hook-form";
import { SERVER_ERROR, setServerError } from "./set-server-error";

/**
 * Puts the field errors of a 422 into a react-hook-form form. Returns true when the error was a 422 and has been
 * applied; any other failure (403, 5xx, network) returns false and leaves the form untouched for the caller to report.
 *
 * `fieldMap` renames API fields to form fields. When given it is also the list of known fields: anything else goes to
 * `root.serverError`, like the API's `base`, so no message is silently lost. This module must not import zod: it ships
 * in the platform chunk, not in the lazy module chunks.
 */
export function applyApiErrors<T extends FieldValues>(
  error: unknown,
  setError: UseFormSetError<T>,
  fieldMap?: Readonly<Record<string, string>>,
): boolean {
  if (!isApiError(error) || error.status !== 422) return false;

  const report = (name: string, message: string) => setServerError(setError, name, message);

  if (error.errors.length === 0) {
    report(SERVER_ERROR, error.title);
    return true;
  }

  const seen = new Set<string>();
  for (const { field, message } of error.errors) {
    const target =
      field === "base" ? SERVER_ERROR : fieldMap ? (fieldMap[field] ?? SERVER_ERROR) : field;
    if (seen.has(target)) continue;
    seen.add(target);
    report(target, message);
  }
  return true;
}

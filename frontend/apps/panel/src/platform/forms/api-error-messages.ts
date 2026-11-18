import { isApiError } from "@ceiba/api-client";
import type { AnyTranslate } from "@ceiba/i18n";
import { describeError } from "../errors/global-errors";

/** Messages to show next to a form that has no per-field slots: the 422's own list, its title, or the generic failure. */
export function apiErrorMessages(error: unknown, translate: AnyTranslate): string[] {
  if (!isApiError(error) || error.status !== 422) return [describeError(error, translate)];
  if (error.errors.length > 0) return error.errors.map((item) => item.message);
  return [error.title];
}

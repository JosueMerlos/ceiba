import type { FieldValues, UseFormSetError } from "react-hook-form";

export const SERVER_ERROR = "root.serverError";

/** The one place the field name is widened: react-hook-form types `setError` by the form's paths, the API's are dynamic. */
export function setServerError<T extends FieldValues>(
  setError: UseFormSetError<T>,
  name: string,
  message: string,
) {
  (setError as (name: string, error: { type: string; message: string }) => void)(name, {
    type: "server",
    message,
  });
}

/**
 * Panel CSRF token: lives ONLY in memory (never in localStorage). The body of `POST /auth/login` and of
 * `GET /auth/session` (which the SPA calls on startup) delivers it, and it is sent in `X-CSRF-Token` on every mutation.
 */
export interface CsrfStore {
  get(): string | undefined;
  set(token: string): void;
  clear(): void;
}

export function createCsrfStore(): CsrfStore {
  let token: string | undefined;
  return {
    get: () => token,
    set: (value) => {
      token = value;
    },
    clear: () => {
      token = undefined;
    },
  };
}

/** Default shared store: one browser, one session. */
export const csrfStore = createCsrfStore();

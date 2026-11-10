/**
 * Token CSRF del panel (11-security): vive SOLO en memoria (nunca en localStorage). Lo entrega el cuerpo de
 * `POST /auth/login` y de `GET /auth/session` (que la SPA llama al arrancar) y se envía en `X-CSRF-Token` en toda mutación.
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

/** Almacén compartido por defecto: un navegador, una sesión. */
export const csrfStore = createCsrfStore();

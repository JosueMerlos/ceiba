/**
 * One key per intended write. A retry of the same body reuses the key, so a lost response never books twice; a different
 * body needs a new key, because the API answers 409 when a key comes back with other content.
 */
export function createIdempotencyKeys(generate: () => string = () => crypto.randomUUID()) {
  let current: { body: string; key: string } | null = null;
  return {
    keyFor(payload: unknown) {
      const body = JSON.stringify(payload);
      if (current?.body !== body) current = { body, key: generate() };
      return current.key;
    },
    settle() {
      current = null;
    },
  };
}

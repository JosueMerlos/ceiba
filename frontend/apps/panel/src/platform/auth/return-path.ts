interface LocationLike {
  pathname: string;
  search: string;
  hash: string;
}

/** Destino tras iniciar sesión: solo rutas internas. Cualquier otra cosa (URL absoluta, //host, javascript:) cae a "/". */
export function safeReturnPath(raw: string | null | undefined): string {
  if (!raw) return "/";
  const internal = raw.startsWith("/") && !raw.startsWith("//") && !raw.includes("\\");
  const control = [...raw].some((char) => char.charCodeAt(0) < 0x20);
  const isLogin = raw === "/login" || raw.startsWith("/login?") || raw.startsWith("/login#");
  return internal && !control && !isLogin ? raw : "/";
}

/**
 * `/login?next=<ruta actual>`: así el usuario vuelve a donde estaba. Desde la raíz o desde /login no añade `next`.
 * `expired` marca una sesión que VENCIÓ mientras se usaba (el login lo explica); un enlace profundo en frío no lo lleva.
 */
export function loginPathFor(
  { pathname, search, hash }: LocationLike,
  { expired = false }: { expired?: boolean } = {},
): string {
  if (pathname === "/login") return `/login${search}`;
  const target = `${pathname}${search}${hash}`;
  const params = new URLSearchParams();
  if (target !== "/") params.set("next", target);
  if (expired) params.set("expired", "1");
  const query = params.toString();
  return query ? `/login?${query}` : "/login";
}

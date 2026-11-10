interface LocationLike {
  pathname: string;
  search: string;
  hash: string;
}

/** Post-login destination: internal paths only. Anything else (absolute URL, //host, javascript:) falls back to "/". */
export function safeReturnPath(raw: string | null | undefined): string {
  if (!raw) return "/";
  const internal = raw.startsWith("/") && !raw.startsWith("//") && !raw.includes("\\");
  const control = [...raw].some((char) => char.charCodeAt(0) < 0x20);
  const isLogin = raw === "/login" || raw.startsWith("/login?") || raw.startsWith("/login#");
  return internal && !control && !isLogin ? raw : "/";
}

/**
 * `/login?next=<current path>`: so the user returns to where they were. From the root or from /login it adds no `next`.
 * `expired` marks a session that EXPIRED while in use (login explains it); a cold deep link does not carry it.
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

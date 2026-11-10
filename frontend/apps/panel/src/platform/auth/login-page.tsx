import { useLoginMutation, useSessionQuery } from "@ceiba/api-client";
import { useTranslation, type AnyTranslate, translator } from "@ceiba/i18n";
import {
  Button,
  CeibaMark,
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  Input,
  LoadingState,
} from "@ceiba/ui";
import { zodResolver } from "@hookform/resolvers/zod";
import { Eye, EyeOff } from "lucide-react";
import { useState } from "react";
import { useForm } from "react-hook-form";
import { Navigate, useSearchParams } from "react-router";
import { z } from "zod";
import { describeError } from "../errors/global-errors";
import { safeReturnPath } from "./return-path";

// Los mensajes de validación se traducen al construir el esquema (zod no conoce i18n).
const loginSchema = (translate: AnyTranslate) => {
  const t = translator(translate);
  return z.object({
    email: z
      .string()
      .trim()
      .min(1, t("auth:login.emailRequired"))
      .pipe(z.email(t("auth:login.emailInvalid"))),
    password: z.string().min(1, t("auth:login.passwordRequired")),
  });
};

export function LoginPage() {
  const { t } = useTranslation(["auth", "common", "errors"]);
  const [params] = useSearchParams();
  const next = safeReturnPath(params.get("next"));
  const cameFromRedirect = params.has("next");
  const session = useSessionQuery();

  // Con sesión vigente (o recién iniciada: el login la deja en la caché) no hay nada que hacer aquí.
  if (session.isSuccess) return <Navigate to={next} replace />;
  if (session.isPending) return <LoadingState label={t("common:loading")} className="min-h-svh" />;

  return (
    <div className="grid min-h-svh md:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]">
      <aside
        aria-hidden="true"
        className="relative hidden overflow-hidden bg-primary p-12 text-primary-foreground md:flex md:flex-col md:justify-between"
      >
        {/* Los anillos de crecimiento del tronco: el único gesto decorativo de la pantalla. */}
        <div
          className="pointer-events-none absolute -right-40 -bottom-40 size-[44rem] rounded-full opacity-[0.16]"
          style={{
            backgroundImage:
              "repeating-radial-gradient(circle at center, transparent 0 1.1rem, currentColor 1.1rem 1.18rem)",
          }}
        />
        <div className="relative flex items-center gap-3">
          <CeibaMark className="size-10 rounded-lg bg-primary-foreground/95 p-1" />
          <span className="font-display text-2xl font-semibold tracking-tight">
            {t("common:appName")}
          </span>
        </div>
        <p className="relative max-w-sm font-display text-4xl leading-tight font-semibold tracking-tight text-balance">
          {t("auth:login.tagline")}
        </p>
      </aside>

      <main className="grid place-items-center px-4 py-12">
        <div className="w-full max-w-sm">
          <div className="mb-8 flex items-center gap-2.5 md:hidden">
            <CeibaMark className="size-9" />
            <span className="font-display text-xl font-semibold">{t("common:appName")}</span>
          </div>
          <h1 className="font-display text-3xl font-semibold">{t("auth:login.title")}</h1>
          <p className="mt-2 mb-6 text-muted-foreground">{t("auth:login.intro")}</p>
          {cameFromRedirect ? (
            <p
              role="status"
              className="mb-6 rounded-lg border bg-secondary px-3.5 py-2.5 text-sm text-secondary-foreground"
            >
              {t("errors:sessionExpired")}
            </p>
          ) : null}
          <LoginForm />
        </div>
      </main>
    </div>
  );
}

function LoginForm() {
  const { t } = useTranslation(["auth", "errors"]);
  const login = useLoginMutation();
  const [reveal, setReveal] = useState(false);
  const form = useForm({
    resolver: zodResolver(loginSchema(t)),
    defaultValues: { email: "", password: "" },
  });

  // Al terminar bien, el login deja la sesión en la caché y LoginPage navega sola a la ruta de retorno.
  const onSubmit = form.handleSubmit((values) =>
    login.mutateAsync(values, { onError: () => form.setFocus("password") }).catch(() => undefined),
  );

  return (
    <Form {...form}>
      <form onSubmit={onSubmit} noValidate className="grid gap-5">
        <FormField
          control={form.control}
          name="email"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("auth:login.email")}</FormLabel>
              <FormControl>
                <Input
                  {...field}
                  type="email"
                  inputMode="email"
                  autoComplete="username"
                  autoFocus
                  placeholder={t("auth:login.emailPlaceholder")}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="password"
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t("auth:login.password")}</FormLabel>
              <div className="relative">
                <FormControl>
                  <Input
                    {...field}
                    type={reveal ? "text" : "password"}
                    autoComplete="current-password"
                    className="pr-11"
                  />
                </FormControl>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="absolute top-0 right-0 text-muted-foreground"
                  aria-label={reveal ? t("auth:login.hidePassword") : t("auth:login.showPassword")}
                  onClick={() => setReveal((current) => !current)}
                >
                  {reveal ? <EyeOff aria-hidden="true" /> : <Eye aria-hidden="true" />}
                </Button>
              </div>
              <FormMessage />
            </FormItem>
          )}
        />

        {login.isError ? (
          <p
            role="alert"
            className="rounded-lg border border-destructive/30 bg-destructive/5 px-3.5 py-2.5 text-sm font-medium text-destructive"
          >
            {describeError(login.error, t)}
          </p>
        ) : null}

        <Button type="submit" size="lg" loading={login.isPending}>
          {login.isPending ? t("auth:login.submitting") : t("auth:login.submit")}
        </Button>
      </form>
    </Form>
  );
}

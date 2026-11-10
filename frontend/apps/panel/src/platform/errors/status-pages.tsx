import { useLogoutMutation } from "@ceiba/api-client";
import { useTranslation } from "@ceiba/i18n";
import { Button, StatusPage } from "@ceiba/ui";
import { isRouteErrorResponse, Link, useNavigate, useRouteError } from "react-router";
import { isApiError } from "@ceiba/api-client";

function BackToStart() {
  const { t } = useTranslation("common");
  return (
    <Button asChild>
      <Link to="/">{t("backToStart")}</Link>
    </Button>
  );
}

export function NotFoundPage() {
  const { t } = useTranslation("errors");
  return (
    <StatusPage
      code="404"
      title={t("notFound.title")}
      description={t("notFound.description")}
      action={<BackToStart />}
    />
  );
}

export function ForbiddenPage({ withLogout = false }: { withLogout?: boolean }) {
  const { t } = useTranslation(["errors", "auth"]);
  const navigate = useNavigate();
  const logout = useLogoutMutation();
  return (
    <StatusPage
      code="403"
      title={t("errors:forbidden.title")}
      description={t("errors:forbidden.description")}
      action={
        withLogout ? (
          <Button
            variant="outline"
            loading={logout.isPending}
            onClick={() => logout.mutate(undefined, { onSettled: () => navigate("/login") })}
          >
            {t("auth:logout")}
          </Button>
        ) : (
          <BackToStart />
        )
      }
    />
  );
}

export function UnexpectedPage({ onRetry }: { onRetry?: () => void }) {
  const { t } = useTranslation(["errors", "common"]);
  return (
    <StatusPage
      title={t("errors:unexpected.title")}
      description={t("errors:unexpected.description")}
      action={
        <Button onClick={onRetry ?? (() => window.location.reload())}>{t("common:retry")}</Button>
      }
    />
  );
}

export function RouteError({ withLogout = false }: { withLogout?: boolean }) {
  const error = useRouteError();
  const status = isApiError(error) ? error.status : isRouteErrorResponse(error) ? error.status : 0;
  if (status === 403) return <ForbiddenPage withLogout={withLogout} />;
  if (status === 404) return <NotFoundPage />;
  return <UnexpectedPage />;
}

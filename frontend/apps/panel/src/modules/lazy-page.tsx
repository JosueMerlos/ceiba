import { LoadingState } from "@ceiba/ui";
import { lazy, Suspense, type ComponentType, type LazyExoticComponent } from "react";
import { useTranslation } from "@ceiba/i18n";

function PageLoading() {
  const { t } = useTranslation("common");
  return <LoadingState label={t("loading")} />;
}

/**
 * Página de un módulo cargada bajo demanda: el `import()` hace que Vite la emita en el chunk del módulo y no en el de
 * arranque. El `load` de todas las páginas de un módulo apunta al mismo archivo, así que comparten un solo chunk.
 */
export function lazyPage<Name extends string>(
  load: () => Promise<Record<Name, ComponentType>>,
  name: Name,
) {
  const Page: LazyExoticComponent<ComponentType> = lazy(async () => ({
    default: (await load())[name],
  }));
  return (
    <Suspense fallback={<PageLoading />}>
      <Page />
    </Suspense>
  );
}

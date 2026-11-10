import { LoadingState } from "@ceiba/ui";
import { lazy, Suspense, type ComponentType, type LazyExoticComponent } from "react";
import { useTranslation } from "@ceiba/i18n";

function PageLoading() {
  const { t } = useTranslation("common");
  return <LoadingState label={t("loading")} />;
}

/**
 * Module page loaded on demand: `import()` makes Vite emit it in the module's chunk, not the startup one. Every page's
 * `load` in a module points at the same file, so they share a single chunk.
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

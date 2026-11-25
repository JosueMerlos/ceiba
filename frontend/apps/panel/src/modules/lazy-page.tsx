import { LoadingState } from "@ceiba/ui";
import { lazy, Suspense, type ComponentType, type LazyExoticComponent } from "react";
import { preloadNamespaces, useTranslation, type LazyNamespace } from "@ceiba/i18n";

function PageLoading() {
  const { t } = useTranslation("common");
  return <LoadingState label={t("loading")} />;
}

/**
 * Page loaded on demand: `import()` makes Vite emit it in the module's chunk, not the startup one. Every page's `load`
 * in a module points at the same file, so they share a single chunk.
 *
 * `namespaces` are the i18n namespaces the page uses beyond the startup ones (common, auth, shell, errors): they
 * download in parallel with the chunk, and the page does not paint until they are in the instance, so no raw key is
 * ever seen.
 */
export function lazyPage<Name extends string>(
  load: () => Promise<Record<Name, ComponentType>>,
  name: Name,
  namespaces: readonly LazyNamespace[],
) {
  const Page: LazyExoticComponent<ComponentType> = lazy(async () => {
    const [file] = await Promise.all([load(), preloadNamespaces(namespaces)]);
    const Component: ComponentType = file[name];
    function Translated() {
      // Suspends (inside the same boundary) until the instance has the namespaces; the download already happened.
      useTranslation(namespaces);
      return <Component />;
    }
    return { default: Translated };
  });
  return (
    <Suspense fallback={<PageLoading />}>
      <Page />
    </Suspense>
  );
}

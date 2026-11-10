import { Loader2 } from "lucide-react";
import { Slot } from "radix-ui";
import type { ComponentProps, ReactNode } from "react";
import { cn } from "../lib/cn";

const MAIN_ID = "contenido-principal";

interface AppLayoutProps {
  /** Texto del enlace "saltar al contenido" (traducido por la app). */
  skipLinkLabel: string;
  /** Nombre accesible de la navegación principal. */
  navigationLabel: string;
  brand: ReactNode;
  /** Items de navegación (`NavItem`); null = sin navegación (p. ej. sin módulos). */
  navigation: ReactNode;
  /** Acciones de la cabecera: selector de contexto, menú de cuenta. */
  actions: ReactNode;
  children: ReactNode;
}

/**
 * Estructura del panel: cabecera, navegación y contenido. En pantallas anchas la navegación es una columna lateral; en
 * tablet y móvil pasa a una fila deslizable bajo la cabecera.
 */
function AppLayout({
  skipLinkLabel,
  navigationLabel,
  brand,
  navigation,
  actions,
  children,
}: AppLayoutProps) {
  return (
    <div className="grid min-h-svh grid-rows-[auto_auto_1fr] md:grid-cols-[var(--sidebar-width)_1fr] md:grid-rows-[auto_1fr]">
      <a
        href={`#${MAIN_ID}`}
        className="sr-only z-50 rounded-md bg-primary px-4 py-2 text-primary-foreground focus:not-sr-only focus:absolute focus:top-2 focus:left-2"
      >
        {skipLinkLabel}
      </a>
      <header className="flex items-center justify-between gap-3 border-b bg-card px-4 py-3 md:col-span-2 md:px-6">
        <div className="flex items-center gap-2.5">{brand}</div>
        <div className="flex items-center gap-2">{actions}</div>
      </header>
      {navigation ? (
        <nav
          aria-label={navigationLabel}
          className="flex gap-1 overflow-x-auto border-b bg-card px-3 py-2 md:flex-col md:overflow-visible md:border-r md:border-b-0 md:px-3 md:py-4"
        >
          {navigation}
        </nav>
      ) : (
        <div className="hidden md:block md:border-r md:bg-card" />
      )}
      <main id={MAIN_ID} tabIndex={-1} className="min-w-0 px-4 py-6 outline-none md:px-8 md:py-8">
        {children}
      </main>
    </div>
  );
}

/** Enlace de navegación. Con `asChild` toma el estilo de un <NavLink>; se marca por `aria-current="page"`. */
function NavItem({
  className,
  asChild = false,
  ...props
}: ComponentProps<"a"> & { asChild?: boolean }) {
  const Comp = asChild ? Slot.Root : "a";
  return (
    <Comp
      data-slot="nav-item"
      className={cn(
        "relative flex shrink-0 items-center gap-2.5 rounded-(--nav-item-radius) px-3 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground",
        "aria-[current=page]:bg-(--nav-item-active-bg) aria-[current=page]:text-accent-foreground",
        "aria-[current=page]:before:absolute aria-[current=page]:before:inset-y-1.5 aria-[current=page]:before:-left-1 aria-[current=page]:before:w-1 aria-[current=page]:before:rounded-full aria-[current=page]:before:bg-(--nav-item-active-indicator) md:aria-[current=page]:before:-left-3",
        "[&_svg]:size-4 [&_svg]:shrink-0",
        className,
      )}
      {...props}
    />
  );
}

interface PageHeaderProps {
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
}

function PageHeader({ title, description, actions }: PageHeaderProps) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div className="grid gap-1">
        <h1 className="font-display text-2xl font-semibold md:text-3xl">{title}</h1>
        {description ? <p className="max-w-prose text-muted-foreground">{description}</p> : null}
      </div>
      {actions}
    </div>
  );
}

interface StatusPageProps {
  /** Código visible (404, 403…): es un dato, no texto traducible. */
  code?: string;
  title: ReactNode;
  description: ReactNode;
  action?: ReactNode;
  className?: string;
}

/** Pantalla de estado (no encontrado, sin permiso, error): explica qué pasó y ofrece la salida. */
function StatusPage({ code, title, description, action, className }: StatusPageProps) {
  return (
    <section
      className={cn("mx-auto grid max-w-md gap-4 px-4 py-16 text-center", className)}
      data-slot="status-page"
    >
      {code ? (
        <p aria-hidden="true" className="font-display text-7xl font-bold text-primary/25">
          {code}
        </p>
      ) : null}
      <h1 className="font-display text-2xl font-semibold">{title}</h1>
      <p className="text-muted-foreground">{description}</p>
      {action ? <div className="mt-2 flex justify-center">{action}</div> : null}
    </section>
  );
}

function LoadingState({ label, className }: { label: string; className?: string }) {
  return (
    <div
      role="status"
      className={cn(
        "flex items-center justify-center gap-2 py-16 text-muted-foreground",
        className,
      )}
    >
      <Loader2 className="size-5 animate-spin" aria-hidden="true" />
      <span>{label}</span>
    </div>
  );
}

export { AppLayout, LoadingState, MAIN_ID, NavItem, PageHeader, StatusPage };

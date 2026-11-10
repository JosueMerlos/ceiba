import { Loader2 } from "lucide-react";
import { Slot } from "radix-ui";
import type { ComponentProps, ReactNode } from "react";
import { cn } from "../lib/cn";

const MAIN_ID = "contenido-principal";

interface AppLayoutProps {
  /** Text of the "skip to content" link (translated by the app). */
  skipLinkLabel: string;
  navigationLabel: string;
  brand: ReactNode;
  /** Navigation items (`NavItem`); null = no navigation (e.g. no modules). */
  navigation: ReactNode;
  actions: ReactNode;
  children: ReactNode;
}

/**
 * Panel structure: header, navigation and content. On wide screens navigation is a side column; on tablet and mobile
 * it becomes a scrollable row under the header.
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
        <div className="flex shrink-0 items-center gap-2.5">{brand}</div>
        <div className="flex min-w-0 items-center gap-2">{actions}</div>
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

/** Navigation link. With `asChild` it styles a <NavLink>; the active one is marked by `aria-current="page"`. */
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
  /** Visible code (404, 403...): data, not translatable text. */
  code?: string;
  title: ReactNode;
  description: ReactNode;
  action?: ReactNode;
  className?: string;
}

/** Status screen (not found, no permission, error): explains what happened and offers a way out. */
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

import { Loader2, PanelLeftClose, PanelLeftOpen } from "lucide-react";
import { Slot } from "radix-ui";
import { createContext, useContext, type ComponentProps, type ReactNode } from "react";
import { cn } from "../lib/cn";
import { Button } from "./button";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "./tooltip";

const MAIN_ID = "contenido-principal";
const SIDEBAR_ID = "barra-lateral";

const AppLayoutContext = createContext({ collapsed: false });

/** Whether the sidebar is currently a 60 px rail. Lets frame content (menus, account) adapt without prop drilling. */
function useAppLayout() {
  return useContext(AppLayoutContext);
}

/**
 * Wraps a rail control in a tooltip that carries its name. Only the collapsed rail needs it (expanded, the text is
 * visible) and below `md` the rail does not exist, so it never shows there either.
 */
function RailTooltip({ label, children }: { label: string; children: ReactNode }) {
  const { collapsed } = useAppLayout();
  if (!collapsed) return children;
  return (
    <Tooltip>
      <TooltipTrigger asChild>{children}</TooltipTrigger>
      <TooltipContent side="right" className="max-md:hidden">
        {label}
      </TooltipContent>
    </Tooltip>
  );
}

interface AppLayoutProps {
  /** Text of the "skip to content" link (translated by the app). */
  skipLinkLabel: string;
  navigationLabel: string;
  /** Logo and name. Hide the name in the rail with `md:group-data-[collapsed=true]/frame:hidden`. */
  brand: ReactNode;
  /** Company and branch selector (or anything that tells where the user works). */
  context?: ReactNode;
  /** Navigation items (`NavItem`); null = no navigation (e.g. no modules). */
  navigation: ReactNode;
  /** The signed-in user's control, pinned to the bottom of the frame. */
  account: ReactNode;
  collapsed: boolean;
  onCollapsedChange(collapsed: boolean): void;
  collapseLabel: string;
  expandLabel: string;
  /** Contextual panel (`ContextPanel`): floats over the sheet's right edge (docked: a column beside it). */
  aside?: ReactNode;
  children: ReactNode;
}

/**
 * Panel structure: a soft frame (logo, context, menu, user) around a white sheet with the screen. The frame collapses
 * to an icon rail on wide screens; under `md` it becomes a top bar with a scrollable navigation row.
 */
function AppLayout({
  skipLinkLabel,
  navigationLabel,
  brand,
  context,
  navigation,
  account,
  collapsed,
  onCollapsedChange,
  collapseLabel,
  expandLabel,
  aside,
  children,
}: AppLayoutProps) {
  const ToggleIcon = collapsed ? PanelLeftOpen : PanelLeftClose;
  return (
    <AppLayoutContext.Provider value={{ collapsed }}>
      <TooltipProvider>
        <div
          data-slot="app-frame"
          data-collapsed={collapsed}
          className="group/frame flex h-svh flex-col overflow-hidden bg-sidebar text-sidebar-foreground md:flex-row"
        >
          <a
            href={`#${MAIN_ID}`}
            className="sr-only z-50 rounded-md bg-primary px-4 py-2 text-primary-foreground focus:not-sr-only focus:absolute focus:top-2 focus:left-2"
          >
            {skipLinkLabel}
          </a>
          <div
            id={SIDEBAR_ID}
            data-slot="app-sidebar"
            className={cn(
              "flex flex-wrap items-center gap-x-2 gap-y-1 px-3 pt-2 pb-1",
              "md:h-full md:w-(--sidebar-width) md:shrink-0 md:flex-col md:flex-nowrap md:items-stretch md:gap-5 md:overflow-y-auto md:px-2 md:py-3",
              "md:group-data-[collapsed=true]/frame:w-(--sidebar-width-collapsed)",
            )}
          >
            <div className="order-1 flex min-w-0 flex-1 items-center justify-between gap-1 md:flex-none md:px-2 md:group-data-[collapsed=true]/frame:flex-col md:group-data-[collapsed=true]/frame:gap-3 md:group-data-[collapsed=true]/frame:px-0">
              {brand}
              <Button
                variant="ghost"
                size="icon"
                className="size-8 text-muted-foreground max-md:hidden"
                aria-label={collapsed ? expandLabel : collapseLabel}
                aria-expanded={!collapsed}
                aria-controls={SIDEBAR_ID}
                onClick={() => onCollapsedChange(!collapsed)}
              >
                <ToggleIcon aria-hidden="true" />
              </Button>
            </div>
            {context ? <div className="order-2 min-w-0 md:order-2">{context}</div> : null}
            <div className="order-3 md:order-4 md:mt-auto">{account}</div>
            {navigation ? (
              <nav
                aria-label={navigationLabel}
                className="order-4 -mx-3 flex basis-full gap-1 overflow-x-auto px-3 pb-1 md:order-3 md:mx-0 md:basis-auto md:flex-col md:overflow-visible md:px-0 md:pb-0"
              >
                {navigation}
              </nav>
            ) : null}
          </div>
          {/* The positioning context of the floating panel, which overlays the sheet instead of taking its width. */}
          <div className="relative flex min-h-0 min-w-0 flex-1 items-stretch gap-2 p-2 md:pl-0">
            <main
              id={MAIN_ID}
              tabIndex={-1}
              className="min-h-0 min-w-0 flex-1 overflow-y-auto rounded-2xl border bg-background px-4 py-6 outline-none md:px-7 md:py-7"
            >
              {children}
            </main>
            {aside ? (
              <div data-slot="app-aside" className="contents">
                {aside}
              </div>
            ) : null}
          </div>
        </div>
      </TooltipProvider>
    </AppLayoutContext.Provider>
  );
}

interface NavItemProps extends ComponentProps<"a"> {
  asChild?: boolean;
  icon: ReactNode;
  /** Visible text; in the rail it becomes the accessible name (`aria-label`) and the tooltip. */
  label: string;
}

/**
 * Navigation link. With `asChild` it styles a <NavLink> (which brings only `to`); the active one is marked by
 * `aria-current="page"`.
 */
function NavItem({ className, asChild = false, icon, label, children, ...props }: NavItemProps) {
  const { collapsed } = useAppLayout();
  const Comp = asChild ? Slot.Root : "a";
  const text = (
    <span className="min-w-0 truncate md:group-data-[collapsed=true]/frame:sr-only">{label}</span>
  );
  return (
    <RailTooltip label={label}>
      <Comp
        data-slot="nav-item"
        aria-label={collapsed ? label : undefined}
        className={cn(
          "flex shrink-0 items-center gap-2.5 rounded-(--nav-item-radius) px-2.5 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-sidebar-accent/70 hover:text-sidebar-foreground",
          "aria-[current=page]:bg-(--nav-item-active-bg) aria-[current=page]:font-semibold aria-[current=page]:text-sidebar-accent-foreground aria-[current=page]:shadow-[inset_0_0_0_1px_var(--sidebar-border)]",
          "[&_svg]:size-[18px] [&_svg]:shrink-0",
          "md:group-data-[collapsed=true]/frame:justify-center md:group-data-[collapsed=true]/frame:px-0",
          className,
        )}
        {...props}
      >
        {icon}
        {asChild ? <Slot.Slottable>{children}</Slot.Slottable> : null}
        {text}
      </Comp>
    </RailTooltip>
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

/**
 * Opt-in page skeleton for screens with a header that must stay put while only the body scrolls (agenda, long
 * tables). Without it the whole sheet scrolls, which suits most screens.
 */
function PageFrame({ className, ...props }: ComponentProps<"div">) {
  return (
    <div
      data-slot="page-frame"
      className={cn("flex h-full min-h-0 flex-col", className)}
      {...props}
    />
  );
}

/** The scrolling region of a `PageFrame`. */
function PageBody({ className, ...props }: ComponentProps<"div">) {
  return (
    <div
      data-slot="page-body"
      className={cn("min-h-0 flex-1 overflow-y-auto", className)}
      {...props}
    />
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

export {
  AppLayout,
  LoadingState,
  MAIN_ID,
  NavItem,
  PageBody,
  PageFrame,
  PageHeader,
  RailTooltip,
  SIDEBAR_ID,
  StatusPage,
  useAppLayout,
};

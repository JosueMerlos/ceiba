import { Check } from "lucide-react";
import { Tabs as TabsPrimitive } from "radix-ui";
import { useState, type ComponentProps, type ReactNode } from "react";
import { cn } from "../lib/cn";
import { PortalContainerContext } from "../lib/portal-container";
import { ConfirmDialog } from "./alert-dialog";
import { Button } from "./button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "./dialog";

interface FormDialogItem {
  id: string;
  /** Already translated by the app. */
  label: string;
}

interface FormDialogStep extends FormDialogItem {
  /** Shows "skip": later steps of a creation flow usually are. */
  optional?: boolean;
}

interface FormDialogBaseProps {
  open: boolean;
  onOpenChange(open: boolean): void;
  title: ReactNode;
  description?: ReactNode;
  closeLabel: string;
  className?: string;
  /** Short line at the start of the footer: what the button will save, or where the flow stands. */
  note?: ReactNode;
  /** The body: usually one <form id={formId}>. It is the only part that scrolls. */
  children: ReactNode;
}

interface FormDialogPlainProps extends FormDialogBaseProps {
  footer?: ReactNode;
  tabs?: undefined;
  steps?: undefined;
}

interface FormDialogTabsProps extends FormDialogBaseProps {
  tabs: readonly FormDialogItem[];
  tab: string;
  onTabChange(tab: string): void;
  tabsLabel: string;
  /** The current tab has unsaved changes: switching tabs or closing asks first. */
  dirty: boolean;
  /** The current tab's form; the single save button submits it. Absent: the tab has nothing to save, so no footer. */
  formId?: string;
  saveLabel: string;
  pending?: boolean;
  confirmTitle: string;
  confirmDescription: string;
  discardLabel: string;
  keepLabel: string;
  steps?: undefined;
}

interface FormDialogStepsProps extends FormDialogBaseProps {
  steps: readonly FormDialogStep[];
  step: string;
  stepsLabel: string;
  onBack(): void;
  onSkip?(): void;
  /** The current step's form: Continue submits it and the app's submit decides whether to advance. */
  formId: string;
  /** Whether the current step holds something to send. With `false` and `onContinue`, Continue skips the submit. */
  dirty?: boolean;
  /** Advances without a request: a clean step has nothing to validate or save. */
  onContinue?(): void;
  backLabel: string;
  skipLabel: string;
  continueLabel: string;
  finishLabel: string;
  pending?: boolean;
  tabs?: undefined;
}

type FormDialogProps = FormDialogPlainProps | FormDialogTabsProps | FormDialogStepsProps;

type Pending = { kind: "close" } | { kind: "tab"; tab: string } | null;

/**
 * Large create/edit modal with a fixed header and footer and a scrolling body. Creating is a sequence of steps
 * (Back / Skip / Continue); editing is tabs with ONE save button for the current tab, and leaving a tab or the modal
 * with unsaved changes asks for confirmation first.
 */
function FormDialog(props: FormDialogProps) {
  if (props.tabs !== undefined) return <TabsDialog {...props} />;
  if (props.steps !== undefined) return <StepsDialog {...props} />;
  return (
    <FormDialogShell {...props} footer={props.footer}>
      <Body className="pt-4">{props.children}</Body>
    </FormDialogShell>
  );
}

interface ShellProps extends Omit<FormDialogBaseProps, "children"> {
  /** Between the title and the body: the step indicator. */
  header?: ReactNode;
  footer?: ReactNode;
  children: ReactNode;
}

function FormDialogShell({
  open,
  onOpenChange,
  title,
  description,
  closeLabel,
  className,
  note,
  header,
  footer,
  children,
}: ShellProps) {
  const [content, setContent] = useState<HTMLElement | null>(null);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        ref={setContent}
        closeLabel={closeLabel}
        data-slot="form-dialog"
        // Escape on a half-typed field cancels the typing (the field handles it), not the whole modal.
        onEscapeKeyDown={(event) => {
          if (event.target instanceof Element && event.target.closest("[data-editing]")) {
            event.preventDefault();
          }
        }}
        className={cn("flex max-h-[calc(100svh-2rem)] flex-col gap-0 p-0 sm:max-w-3xl", className)}
      >
        <PortalContainerContext.Provider value={content}>
          <div className="grid gap-1.5 px-6 pt-6 pr-12">
            <DialogTitle>{title}</DialogTitle>
            {description ? <DialogDescription>{description}</DialogDescription> : null}
          </div>
          {header}
          {children}
          {footer ? (
            <div
              data-slot="form-dialog-footer"
              className="flex flex-col-reverse gap-2 border-t px-6 py-4 sm:flex-row sm:items-center sm:justify-end"
            >
              {note ? <p className="text-xs text-muted-foreground sm:mr-auto">{note}</p> : null}
              {footer}
            </div>
          ) : null}
        </PortalContainerContext.Provider>
      </DialogContent>
    </Dialog>
  );
}

// Radix Tabs injects the tabpanel id, role and aria-labelledby through `asChild`, so the props must reach the div.
function Body({ className, ...props }: ComponentProps<"div">) {
  return (
    <div
      data-slot="form-dialog-body"
      className={cn("min-h-0 flex-1 overflow-y-auto px-6 py-5", className)}
      {...props}
    />
  );
}

function TabsDialog(props: FormDialogTabsProps) {
  const [pending, setPending] = useState<Pending>(null);

  function requestClose(next: boolean) {
    if (!next && props.dirty) setPending({ kind: "close" });
    else props.onOpenChange(next);
  }

  function requestTab(tab: string) {
    if (tab === props.tab) return;
    if (props.dirty) setPending({ kind: "tab", tab });
    else props.onTabChange(tab);
  }

  function discard() {
    if (pending?.kind === "close") props.onOpenChange(false);
    if (pending?.kind === "tab") props.onTabChange(pending.tab);
    setPending(null);
  }

  return (
    <>
      <FormDialogShell
        {...props}
        onOpenChange={requestClose}
        note={props.formId ? props.note : undefined}
        footer={
          props.formId ? (
            <Button type="submit" form={props.formId} loading={props.pending}>
              {props.saveLabel}
            </Button>
          ) : null
        }
      >
        <TabsPrimitive.Root
          value={props.tab}
          onValueChange={requestTab}
          activationMode="manual"
          className="flex min-h-0 flex-1 flex-col"
        >
          <TabsPrimitive.List
            aria-label={props.tabsLabel}
            className="mt-3 flex gap-1 overflow-x-auto border-b px-6"
          >
            {props.tabs.map((item) => (
              <TabsPrimitive.Trigger
                key={item.id}
                value={item.id}
                className={cn(
                  "-mb-px h-10 shrink-0 border-b-2 border-transparent px-3 text-sm font-semibold whitespace-nowrap text-muted-foreground transition-colors",
                  "hover:text-foreground focus-visible:outline-2 focus-visible:outline-ring",
                  "data-[state=active]:border-primary data-[state=active]:text-foreground",
                )}
              >
                {item.label}
              </TabsPrimitive.Trigger>
            ))}
          </TabsPrimitive.List>
          <TabsPrimitive.Content value={props.tab} asChild>
            <Body>{props.children}</Body>
          </TabsPrimitive.Content>
        </TabsPrimitive.Root>
      </FormDialogShell>
      <ConfirmDialog
        open={pending !== null}
        onOpenChange={(next) => {
          if (!next) setPending(null);
        }}
        title={props.confirmTitle}
        description={props.confirmDescription}
        confirmLabel={props.discardLabel}
        cancelLabel={props.keepLabel}
        onConfirm={discard}
      />
    </>
  );
}

function StepsDialog(props: FormDialogStepsProps) {
  const current = props.steps.findIndex((item) => item.id === props.step);
  const last = current === props.steps.length - 1;
  const canSkip = props.steps[current]?.optional && props.onSkip;
  const advanceOnly = props.dirty === false && props.onContinue !== undefined;
  return (
    <FormDialogShell
      {...props}
      header={<StepIndicator steps={props.steps} current={current} label={props.stepsLabel} />}
      footer={
        <>
          {canSkip ? (
            <Button
              type="button"
              variant="ghost"
              className={props.note ? undefined : "sm:mr-auto"}
              onClick={props.onSkip}
              disabled={props.pending}
            >
              {props.skipLabel}
            </Button>
          ) : null}
          {current > 0 ? (
            <Button type="button" variant="outline" onClick={props.onBack} disabled={props.pending}>
              {props.backLabel}
            </Button>
          ) : null}
          {advanceOnly ? (
            <Button type="button" onClick={props.onContinue} loading={props.pending}>
              {last ? props.finishLabel : props.continueLabel}
            </Button>
          ) : (
            <Button type="submit" form={props.formId} loading={props.pending}>
              {last ? props.finishLabel : props.continueLabel}
            </Button>
          )}
        </>
      }
    >
      <Body>{props.children}</Body>
    </FormDialogShell>
  );
}

function StepIndicator({
  steps,
  current,
  label,
}: {
  steps: readonly FormDialogStep[];
  current: number;
  label: string;
}) {
  return (
    <ol
      aria-label={label}
      className="mt-4 grid auto-cols-fr grid-flow-col gap-3 border-b px-6 pb-4"
    >
      {steps.map((item, index) => {
        const done = index < current;
        const active = index === current;
        return (
          <li
            key={item.id}
            aria-current={active ? "step" : undefined}
            className="grid min-w-0 gap-2"
          >
            <span
              aria-hidden="true"
              className={cn("h-1 rounded-full", done || active ? "bg-primary" : "bg-muted")}
            />
            <span
              className={cn(
                "flex min-w-0 items-center gap-2 text-sm",
                active ? "font-bold text-foreground" : "font-semibold",
                !done && !active && "text-muted-foreground",
              )}
            >
              <span
                aria-hidden="true"
                className={cn(
                  "grid size-5.5 shrink-0 place-items-center rounded-full text-[0.6875rem] font-bold",
                  done && "bg-primary text-primary-foreground",
                  active && "bg-foreground text-background",
                  !done && !active && "bg-muted text-muted-foreground",
                )}
              >
                {done ? <Check className="size-3" /> : index + 1}
              </span>
              <span className="truncate">{item.label}</span>
            </span>
          </li>
        );
      })}
    </ol>
  );
}

export { FormDialog };
export type { FormDialogItem, FormDialogProps, FormDialogStep };

import { Check } from "lucide-react";
import { Tabs as TabsPrimitive } from "radix-ui";
import { useState, type ReactNode } from "react";
import { cn } from "../lib/cn";
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
  /** The current tab's form; the single save button submits it. */
  formId: string;
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
  const { open, onOpenChange, title, description, closeLabel, className, children } = props;
  const [pending, setPending] = useState<Pending>(null);
  const guarded = props.tabs !== undefined && props.dirty;

  function requestClose(next: boolean) {
    if (!next && guarded) setPending({ kind: "close" });
    else onOpenChange(next);
  }

  function requestTab(tab: string) {
    if (props.tabs === undefined || tab === props.tab) return;
    if (props.dirty) setPending({ kind: "tab", tab });
    else props.onTabChange(tab);
  }

  function discard() {
    if (pending?.kind === "close") onOpenChange(false);
    if (pending?.kind === "tab" && props.tabs !== undefined) props.onTabChange(pending.tab);
    setPending(null);
  }

  return (
    <Dialog open={open} onOpenChange={requestClose}>
      <DialogContent
        closeLabel={closeLabel}
        data-slot="form-dialog"
        className={cn(
          "flex max-h-[calc(100svh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-3xl",
          className,
        )}
      >
        <div className="grid gap-1.5 px-6 pt-6 pr-12">
          <DialogTitle>{title}</DialogTitle>
          {description ? <DialogDescription>{description}</DialogDescription> : null}
        </div>

        {props.steps !== undefined ? <StepIndicator {...props} /> : null}

        {props.tabs !== undefined ? (
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
              <Body>{children}</Body>
            </TabsPrimitive.Content>
          </TabsPrimitive.Root>
        ) : (
          <Body className={props.steps === undefined ? "pt-4" : undefined}>{children}</Body>
        )}

        <FormDialogFooter {...props} />
      </DialogContent>

      {props.tabs !== undefined ? (
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
      ) : null}
    </Dialog>
  );
}

function Body({ className, children, ...props }: { className?: string; children: ReactNode }) {
  return (
    <div
      data-slot="form-dialog-body"
      className={cn("min-h-0 flex-1 overflow-y-auto px-6 py-5", className)}
      {...props}
    >
      {children}
    </div>
  );
}

function StepIndicator({ steps, step, stepsLabel }: FormDialogStepsProps) {
  const current = steps.findIndex((item) => item.id === step);
  return (
    <ol
      aria-label={stepsLabel}
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

function FormDialogFooter(props: FormDialogProps) {
  if (props.tabs !== undefined) {
    return (
      <Footer>
        <Button type="submit" form={props.formId} loading={props.pending}>
          {props.saveLabel}
        </Button>
      </Footer>
    );
  }
  if (props.steps !== undefined) {
    const index = props.steps.findIndex((item) => item.id === props.step);
    const last = index === props.steps.length - 1;
    const optional = props.steps[index]?.optional && props.onSkip;
    return (
      <Footer>
        {optional ? (
          <Button type="button" variant="ghost" className="sm:mr-auto" onClick={props.onSkip}>
            {props.skipLabel}
          </Button>
        ) : null}
        {index > 0 ? (
          <Button type="button" variant="outline" onClick={props.onBack} disabled={props.pending}>
            {props.backLabel}
          </Button>
        ) : null}
        <Button type="submit" form={props.formId} loading={props.pending}>
          {last ? props.finishLabel : props.continueLabel}
        </Button>
      </Footer>
    );
  }
  return props.footer ? <Footer>{props.footer}</Footer> : null;
}

function Footer({ children }: { children: ReactNode }) {
  return (
    <div
      data-slot="form-dialog-footer"
      className="flex flex-col-reverse gap-2 border-t px-6 py-4 sm:flex-row sm:items-center sm:justify-end"
    >
      {children}
    </div>
  );
}

export { FormDialog };
export type { FormDialogItem, FormDialogProps, FormDialogStep };

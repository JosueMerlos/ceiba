import type { ComponentProps } from "react";
import { cn } from "../lib/cn";

/** The wrapper scrolls horizontally so a wide table never pushes the page sideways on a phone. */
function Table({ className, ...props }: ComponentProps<"table">) {
  return (
    <div data-slot="table-container" className="w-full overflow-x-auto">
      <table
        data-slot="table"
        className={cn("w-full min-w-xl border-collapse text-sm", className)}
        {...props}
      />
    </div>
  );
}

function TableHeader({ className, ...props }: ComponentProps<"thead">) {
  return (
    <thead data-slot="table-header" className={cn("text-muted-foreground", className)} {...props} />
  );
}

function TableBody({ className, ...props }: ComponentProps<"tbody">) {
  return <tbody data-slot="table-body" className={className} {...props} />;
}

function TableRow({ className, ...props }: ComponentProps<"tr">) {
  return (
    <tr
      data-slot="table-row"
      className={cn(
        "border-b transition-colors last:border-b-0 hover:bg-muted/50 data-[state=selected]:bg-accent",
        className,
      )}
      {...props}
    />
  );
}

function TableHead({ className, scope = "col", ...props }: ComponentProps<"th">) {
  return (
    <th
      data-slot="table-head"
      scope={scope}
      className={cn("px-3 pb-2.5 text-left text-xs font-semibold whitespace-nowrap", className)}
      {...props}
    />
  );
}

function TableCell({ className, ...props }: ComponentProps<"td">) {
  return (
    <td data-slot="table-cell" className={cn("px-3 py-3 align-middle", className)} {...props} />
  );
}

function TableCaption({ className, ...props }: ComponentProps<"caption">) {
  return (
    <caption
      data-slot="table-caption"
      className={cn("mt-3 text-sm text-muted-foreground", className)}
      {...props}
    />
  );
}

export { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow };

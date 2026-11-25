import type { ReactNode } from "react";
import { CatalogAside } from "./catalog-aside";

export interface CatalogDetail {
  label: string;
  value: ReactNode;
}

interface CatalogDetailPanelProps {
  id: string;
  title: string;
  onClose(): void;
  /** The entity's facts, read only: label and value pairs. */
  details: readonly CatalogDetail[];
  /** Whatever the role may do from here (edit, restore); absent for whoever only reads. */
  footer?: ReactNode;
  /** Sections below the facts: hours, absences, the branch's own values. */
  children?: ReactNode;
}

/** Floating read view of one catalog row. Editing never happens here: it opens the entity's modal. */
export function CatalogDetailPanel({
  id,
  title,
  onClose,
  details,
  footer,
  children,
}: CatalogDetailPanelProps) {
  return (
    <CatalogAside id={id} title={title} onClose={onClose} footer={footer}>
      <dl className="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-2.5 text-sm">
        {details.map((detail) => (
          <div key={detail.label} className="contents">
            <dt className="text-muted-foreground">{detail.label}</dt>
            <dd className="min-w-0 font-medium tabular-nums">{detail.value}</dd>
          </div>
        ))}
      </dl>
      {children}
    </CatalogAside>
  );
}

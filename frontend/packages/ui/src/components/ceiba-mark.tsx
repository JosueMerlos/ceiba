import type { ComponentProps } from "react";

/**
 * La marca de Ceiba: la copa ancha del árbol sobre un tronco con raíces tabulares (contrafuertes), y una flor de
 * sacuanjoche. Es decorativa (aria-hidden): el nombre del producto va como texto al lado.
 */
function CeibaMark(props: ComponentProps<"svg">) {
  return (
    <svg viewBox="0 0 48 48" fill="none" aria-hidden="true" focusable="false" {...props}>
      <ellipse cx="24" cy="17" rx="19" ry="12" fill="var(--primary)" />
      <ellipse cx="14" cy="21" rx="9" ry="7" fill="var(--primary)" opacity="0.85" />
      <ellipse cx="35" cy="21" rx="9" ry="7" fill="var(--primary)" opacity="0.85" />
      <path
        d="M21.5 26h5l.8 11.2c1.6 1.6 4.4 3.6 7.7 4.8H13c3.3-1.2 6.1-3.2 7.7-4.8L21.5 26Z"
        fill="var(--foreground)"
      />
      <circle cx="33" cy="13" r="3.2" fill="var(--highlight)" />
    </svg>
  );
}

export { CeibaMark };

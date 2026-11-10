import { Component, type ReactNode } from "react";

/**
 * Límite de error que oculta su contenido en vez de tirar la pantalla: para piezas opcionales de la cabecera (el selector
 * de contexto) cuyo fallo no debe quitar la navegación ni el menú de cuenta.
 */
export class SilentBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  override state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  override render() {
    return this.state.failed ? null : this.props.children;
  }
}

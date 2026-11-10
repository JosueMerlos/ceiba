import { Component, type ReactNode } from "react";

/**
 * Error boundary that hides its content instead of breaking the screen: for optional header pieces (the context
 * selector) whose failure must not remove the navigation or the account menu.
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

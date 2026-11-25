import { useSyncExternalStore } from "react";

// Below the panel's `md` breakpoint the agenda is a list: a timeline of hours does not fit a phone.
const NARROW = "(max-width: 767.98px)";

function subscribe(onChange: () => void) {
  const query = window.matchMedia(NARROW);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

/** Whether the screen is a phone's width; follows rotations and resizes. */
export function useNarrowScreen() {
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(NARROW).matches,
    () => false,
  );
}

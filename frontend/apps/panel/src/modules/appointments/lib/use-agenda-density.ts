import { useCallback, useState } from "react";
import type { AgendaDensity } from "../components/agenda-view/types";

const storageKey = (userId: string) => `ceiba.agenda-density.${userId}`;

// localStorage can throw (blocked site data, private mode, quota): the preference is a convenience, never a requirement.
function readPreference(userId: string): AgendaDensity | null {
  try {
    const stored = window.localStorage.getItem(storageKey(userId));
    return stored === "compact" || stored === "comfortable" ? stored : null;
  } catch {
    return null;
  }
}

function writePreference(userId: string, density: AgendaDensity) {
  try {
    window.localStorage.setItem(storageKey(userId), density);
  } catch {
    // The choice still applies for this session.
  }
}

/** The agenda's density, remembered per user on this device. */
export function useAgendaDensity(userId: string) {
  const [density, setDensity] = useState<AgendaDensity>(
    () => readPreference(userId) ?? "comfortable",
  );
  const update = useCallback(
    (next: AgendaDensity) => {
      setDensity(next);
      writePreference(userId, next);
    },
    [userId],
  );
  return [density, update] as const;
}

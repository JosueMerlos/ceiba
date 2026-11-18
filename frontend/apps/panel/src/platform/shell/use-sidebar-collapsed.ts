import { useCallback, useState } from "react";

/** Below this width the sidebar starts as a rail: the sheet needs the room more than the labels do. */
const WIDE_SCREEN_PX = 1280;

const storageKey = (userId: string) => `ceiba.sidebar-collapsed.${userId}`;

// localStorage can throw (blocked site data, private mode, quota): the preference is a convenience, never a requirement.
function readPreference(userId: string): boolean | null {
  try {
    const stored = window.localStorage.getItem(storageKey(userId));
    return stored === "true" ? true : stored === "false" ? false : null;
  } catch {
    return null;
  }
}

function writePreference(userId: string, collapsed: boolean) {
  try {
    window.localStorage.setItem(storageKey(userId), String(collapsed));
  } catch {
    // The choice still applies for this session.
  }
}

/** Sidebar collapsed state: the user's saved choice wins, otherwise the screen width decides. */
export function useSidebarCollapsed(userId: string) {
  const [collapsed, setCollapsed] = useState(
    () => readPreference(userId) ?? window.innerWidth < WIDE_SCREEN_PX,
  );
  const update = useCallback(
    (next: boolean) => {
      setCollapsed(next);
      writePreference(userId, next);
    },
    [userId],
  );
  return [collapsed, update] as const;
}

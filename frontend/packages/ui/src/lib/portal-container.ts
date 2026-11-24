import { createContext, useContext } from "react";

// A modal locks scrolling and pointer events outside its content: popovers opened inside it (time list, calendar)
// must mount inside that content too, or their list cannot be scrolled.
export const PortalContainerContext = createContext<HTMLElement | null>(null);

export const usePortalContainer = () => useContext(PortalContainerContext) ?? undefined;

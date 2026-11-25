import { createContext, useContext } from "react";
import type { AgendaDensity } from "./types";

/**
 * How dense the agenda is drawn. It is a viewing preference, not agenda data, so it reaches the drawing through context
 * and the props every adapter shares stay the same.
 */
export const AgendaDensityContext = createContext<AgendaDensity>("comfortable");

export const useAgendaViewDensity = () => useContext(AgendaDensityContext);

const pad = (value: number) => String(value).padStart(2, "0");

/** "HH:mm" -> minutes since midnight. */
export const clockToMinutes = (clock: string) =>
  Number(clock.slice(0, 2)) * 60 + Number(clock.slice(3, 5));

export const minutesToClock = (minutes: number) =>
  `${pad(Math.floor(minutes / 60))}:${pad(minutes % 60)}`;

// "9", "9:30", "930", "0930", "2p", "930p", "9:30 a. m.", "12am"...
const TYPED = /^(\d{1,2})(?::?(\d{2}))?\s*(?:([ap])\.?\s*(?:m\.?)?)?$/;

/**
 * Normalizes what a person types into "HH:mm", or null when it is not a time. Without an a/p suffix the text is read
 * in 24 h (an ambiguous "9" is 9 in the morning); with one, the hour must be 1-12.
 */
export function parseClock(text: string): string | null {
  const match = TYPED.exec(text.trim().toLowerCase());
  if (!match) return null;
  const [, rawHours = "", rawMinutes, suffix] = match;
  let hours = Number(rawHours);
  const minutes = rawMinutes === undefined ? 0 : Number(rawMinutes);
  if (minutes > 59) return null;
  if (suffix) {
    if (hours < 1 || hours > 12) return null;
    hours = (hours % 12) + (suffix === "p" ? 12 : 0);
  } else if (hours > 23) {
    return null;
  }
  return minutesToClock(hours * 60 + minutes);
}

/** Every `step` minutes from `min` (rounded up to the step) to `max`, both included. */
export function clockOptions(min: string, max: string, step: number): string[] {
  const options: string[] = [];
  const last = clockToMinutes(max);
  for (
    let minutes = Math.ceil(clockToMinutes(min) / step) * step;
    minutes <= last;
    minutes += step
  ) {
    options.push(minutesToClock(minutes));
  }
  return options;
}

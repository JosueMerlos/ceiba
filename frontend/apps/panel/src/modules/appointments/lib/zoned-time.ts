// Absences are typed in the BRANCH's wall-clock time and stored in UTC. The browser's own zone is irrelevant (a manager
// may work from another country), so every conversion goes through Intl with the branch's IANA zone.

const LOCAL = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/;

function zoneFormatter(timeZone: string) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** Wall-clock parts of an instant in a zone, as the minutes since the epoch of the same wall-clock read as UTC. */
function wallClockAsUtcMs(instantMs: number, formatter: Intl.DateTimeFormat) {
  const parts = Object.fromEntries(
    formatter.formatToParts(new Date(instantMs)).map((part) => [part.type, part.value]),
  );
  return Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour),
    Number(parts.minute),
  );
}

/** "2026-11-20T09:00" read in `timeZone` -> UTC ISO string; null when the text or the zone is not valid. */
export function localToUtcIso(local: string, timeZone: string): string | null {
  const match = LOCAL.exec(local);
  if (!match) return null;
  const [, year, month, day, hour, minute] = match.map(Number);
  const wanted = Date.UTC(year!, month! - 1, day!, hour!, minute!);
  const calendar = new Date(wanted);
  // Date.UTC rolls 2026-13-45 over to a valid date: reject anything that did not round-trip.
  if (
    calendar.getUTCFullYear() !== year ||
    calendar.getUTCMonth() !== month! - 1 ||
    calendar.getUTCDate() !== day ||
    calendar.getUTCHours() !== hour ||
    calendar.getUTCMinutes() !== minute
  ) {
    return null;
  }
  let formatter: Intl.DateTimeFormat;
  try {
    formatter = zoneFormatter(timeZone);
  } catch {
    return null;
  }
  // Two passes settle the offset even when it differs between the guess and the real instant (DST changes).
  let instant = wanted;
  for (let pass = 0; pass < 2; pass += 1) {
    instant = wanted - (wallClockAsUtcMs(instant, formatter) - instant);
  }
  return new Date(instant).toISOString();
}

/** The `datetime-local` value ("2026-11-20T09:30") an instant has in `timeZone`. */
export function utcToLocalInput(iso: string, timeZone: string): string {
  return new Date(wallClockAsUtcMs(Date.parse(iso), zoneFormatter(timeZone)))
    .toISOString()
    .slice(0, 16);
}

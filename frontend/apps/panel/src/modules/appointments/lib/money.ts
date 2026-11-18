const PRICE = /^(\d+)(?:[.,](\d{1,2}))?$/;

/**
 * Typed price in major units ("250", "250.5", "250,50") to the contract's integer minor units. Parsed from the text, not
 * through a float, so 19.99 never becomes 1998. Null when the text is not a non-negative price with at most 2 decimals.
 */
export function parsePriceToMinor(text: string): number | null {
  const match = PRICE.exec(text.trim());
  if (!match) return null;
  const [, major, minor = ""] = match;
  return Number(major) * 100 + Number(minor.padEnd(2, "0"));
}

/** Minor units as the editable text of a price input. */
export function minorToInput(minor: number): string {
  return (minor / 100).toFixed(2);
}

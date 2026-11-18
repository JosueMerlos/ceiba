import { describe, expect, it } from "vitest";
import { fromBranding } from "../src/from-branding";

const BRAND = {
  primary_color: "#8B2F5C",
  secondary_color: null,
  accent_color: "no-es-un-color",
  font_choice: "lora",
} as const;

describe("fromBranding", () => {
  it("copia los colores válidos y descarta los nulos y los mal formados", () => {
    expect(fromBranding(BRAND)).toEqual({
      primaryColor: "#8B2F5C",
      secondaryColor: null,
      accentColor: null,
      fontChoice: "lora",
    });
  });

  it("Figtree equivale a no elegir tipografía", () => {
    expect(fromBranding({ ...BRAND, font_choice: "figtree" }).fontChoice).toBeNull();
  });
});

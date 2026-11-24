import { describe, expect, it } from "vitest";
import { cardTier, cardWidth, DENSITY } from "./card-tier";

describe("cardTier", () => {
  it("en compacta: 15 min son iniciales, 30 min el nombre y 60 min nombre y servicio", () => {
    expect(cardTier(15, "compact")).toBe("initials");
    expect(cardTier(30, "compact")).toBe("name");
    expect(cardTier(60, "compact")).toBe("full");
  });

  it("en cómoda la misma cita gana espacio: 30 min muestran el nombre y 45 min ya caben con el servicio", () => {
    expect(cardTier(15, "comfortable")).toBe("initials");
    expect(cardTier(30, "comfortable")).toBe("name");
    expect(cardTier(45, "comfortable")).toBe("full");
  });

  it("decide por el ancho en píxeles, con el borde exacto del nombre incluido", () => {
    expect(cardWidth(30, "compact")).toBe(60);
    expect(cardTier(30, "compact")).toBe("name");
    // 28 min in compact: 28 × 64 / 30 − 4 ≈ 55.7 px, just below the name's 56 px.
    expect(cardTier(28, "compact")).toBe("initials");
  });

  it("una duración nula o negativa nunca rompe: queda en iniciales", () => {
    expect(cardTier(0, "compact")).toBe("initials");
    expect(cardTier(-30, "comfortable")).toBe("initials");
  });

  it("la compacta es más angosta y más baja que la cómoda", () => {
    expect(DENSITY.compact.slotWidth).toBeLessThan(DENSITY.comfortable.slotWidth);
    expect(DENSITY.compact.rowHeight).toBeLessThan(DENSITY.comfortable.rowHeight);
  });
});

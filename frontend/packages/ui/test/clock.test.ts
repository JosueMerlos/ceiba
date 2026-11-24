import { describe, expect, it } from "vitest";
import { clockOptions, parseClock } from "../src/lib/clock";

describe("parseClock", () => {
  it.each([
    ["9", "09:00"],
    ["9:30", "09:30"],
    ["930", "09:30"],
    ["0930", "09:30"],
    ["13", "13:00"],
    ["1745", "17:45"],
    [" 9:05 ", "09:05"],
  ])("sin sufijo lee «%s» en 24 h como %s", (text, expected) => {
    expect(parseClock(text)).toBe(expected);
  });

  it.each([
    ["930p", "21:30"],
    ["2p", "14:00"],
    ["2 pm", "14:00"],
    ["9:30 a. m.", "09:30"],
    ["9:30 p.m.", "21:30"],
    ["12a", "00:00"],
    ["12p", "12:00"],
    ["12:15am", "00:15"],
  ])("con sufijo a/p lee «%s» como %s", (text, expected) => {
    expect(parseClock(text)).toBe(expected);
  });

  it.each(["", "abc", "25", "24:00", "9:75", "13p", "0p", "12345", "9:3", "9::30", "-9"])(
    "rechaza «%s»",
    (text) => {
      expect(parseClock(text)).toBeNull();
    },
  );
});

describe("clockOptions", () => {
  it("lista cada 15 min de min a max, ambos incluidos", () => {
    expect(clockOptions("09:00", "10:00", 15)).toEqual([
      "09:00",
      "09:15",
      "09:30",
      "09:45",
      "10:00",
    ]);
  });

  it("el día completo por defecto termina en 23:45", () => {
    const options = clockOptions("00:00", "23:45", 15);

    expect(options).toHaveLength(96);
    expect(options.at(-1)).toBe("23:45");
  });

  it("un min que no cae en el paso arranca en el siguiente múltiplo", () => {
    expect(clockOptions("09:10", "09:50", 15)).toEqual(["09:15", "09:30", "09:45"]);
  });
});

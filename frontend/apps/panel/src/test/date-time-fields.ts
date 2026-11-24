import { screen, within } from "@testing-library/react";
import type { UserEvent } from "@testing-library/user-event";

const MONTHS = [
  "enero",
  "febrero",
  "marzo",
  "abril",
  "mayo",
  "junio",
  "julio",
  "agosto",
  "septiembre",
  "octubre",
  "noviembre",
  "diciembre",
];

/** Opens a DatePicker, walks to the day's month and clicks the day, as a person would. */
export async function pickDate(user: UserEvent, trigger: HTMLElement, day: string) {
  const [year, month, date] = day.split("-").map(Number) as [number, number, number];
  await user.click(trigger);
  const calendar = await screen.findByRole("dialog", { name: "Calendario" }, { timeout: 5000 });
  for (let guard = 0; guard < 36; guard += 1) {
    const grid = await within(calendar).findByRole("grid", {}, { timeout: 5000 });
    const [shownMonth = "", shownYear = ""] = (grid.getAttribute("aria-label") ?? "")
      .toLowerCase()
      .split(" ");
    const distance = (year - Number(shownYear)) * 12 + (month - 1 - MONTHS.indexOf(shownMonth));
    if (distance === 0) {
      const button = within(grid)
        .getAllByRole("button")
        .find((item) => item.textContent === String(date) && !item.closest("[data-outside]"));
      await user.click(button!);
      return;
    }
    await user.click(
      within(calendar).getByRole("button", {
        name: distance > 0 ? "Mes siguiente" : "Mes anterior",
      }),
    );
  }
  throw new Error(`No se llegó al mes de ${day}`);
}

/** Types a time into a TimeField and leaves it, which is when the field commits. */
export async function typeTime(user: UserEvent, field: HTMLElement, clock: string) {
  await user.clear(field);
  await user.type(field, clock);
  await user.tab();
}

/** Fills a date + time fieldset ("Desde", "Hasta") with "yyyy-MM-ddTHH:mm". */
export async function fillWallClock(
  user: UserEvent,
  scope: HTMLElement,
  legend: string,
  value: string,
) {
  const group = within(scope).getByRole("group", { name: legend });
  const [day = "", clock = ""] = value.split("T");
  await pickDate(user, within(group).getByRole("button", { name: "Fecha" }), day);
  await typeTime(user, within(group).getByRole("combobox", { name: "Hora" }), clock);
}

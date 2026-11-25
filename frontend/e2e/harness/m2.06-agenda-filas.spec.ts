import { expect, test, type Locator, type Page } from "@playwright/test";
import { RAMIRO, RECEPTION, nextWorkingDay, openAgenda, sidePanel } from "../tests/agenda-helpers";
import { shot, signIn } from "../tests/helpers";

// UI QA smoke for the agenda in rows: 15 professionals, a browser in another zone, the floating panel, the week and
// the phone list. The pilot scenarios need `SEED_DEMO_PASSWORD=<demo password> bin/rails demo:agenda_pilot`. The
// 15-person salon is built in the browser on top of the pilot's real answers: nothing is written to the API.
const PILOT_RECEPTION = "recepcion@piloto-interno.ceiba.test";
const ROWS = 15;
const EXTRA_NAMES = [
  "Marcela Aguirre",
  "Tomás Zeledón",
  "Sofía Espinoza",
  "Ramiro Salazar",
  "Daniela Castro",
  "Jorge Lacayo",
  "Valeria Mendoza",
  "Héctor Ruiz",
  "Irene Toruño",
  "Mario Gaitán",
];
// Lengths that land on each card tier: initials, name, name and service.
const EXTRA_MINUTES = [15, 30, 60];

/** Today in the branch, or the Saturday before on a Sunday: the pilot has no appointments on Sundays. */
function pilotDay() {
  const day = new Date(
    `${new Date().toLocaleDateString("en-CA", { timeZone: "America/Managua" })}T12:00:00Z`,
  );
  if (day.getUTCDay() === 0) day.setUTCDate(day.getUTCDate() - 1);
  return day.toISOString().slice(0, 10);
}

type Json = Record<string, unknown> & { id: string };

/** Ten more professionals and their appointments, cloned from the pilot's real answers so their shape is the API's. */
async function fifteenProfessionals(page: Page) {
  const fakeIds = EXTRA_NAMES.map(
    (_, index) => `0198f0a0-0000-7000-8000-${String(index).padStart(12, "0")}`,
  );
  let realId = "";
  await page.route(/\/appointments\/professionals(\?|$)/, async (route) => {
    const response = await route.fetch();
    const body = (await response.json()) as { data: Json[] };
    const [first] = body.data;
    realId = first!.id;
    const extra = EXTRA_NAMES.map((display_name, index) => ({
      ...first!,
      id: fakeIds[index]!,
      display_name,
    }));
    await route.fulfill({ response, json: { ...body, data: [...body.data, ...extra] } });
  });
  // The fake people's schedules and absences are the first real professional's.
  await page.route(
    /\/professionals\/0198f0a0-0000-7000-8000-\d{12}\/(schedule|time_offs)/,
    (route) =>
      route.continue({
        url: route
          .request()
          .url()
          .replace(/0198f0a0-0000-7000-8000-\d{12}/, realId),
      }),
  );
  await page.route(/\/branches\/[^/]+\/appointments\?/, async (route) => {
    const response = await route.fetch();
    const body = (await response.json()) as { data: (Json & { starts_at: string })[] };
    const [model] = body.data;
    if (!model) return route.fulfill({ response });
    const opening = new Date(`${pilotDay()}T15:00:00Z`).getTime();
    const extra = fakeIds.flatMap((professional_id, person) =>
      EXTRA_MINUTES.map((minutes, index) => {
        const starts = opening + (index * 90 + person * 10) * 60_000;
        return {
          ...model,
          id: `${professional_id.slice(0, -2)}${person}${index}`,
          professional_id,
          resource_id: null,
          status: "confirmed",
          customer_name: `Cliente ${person + 1}-${index + 1}`,
          starts_at: new Date(starts).toISOString(),
          ends_at: new Date(starts + minutes * 60_000).toISOString(),
        };
      }),
    );
    await route.fulfill({ response, json: { ...body, data: [...body.data, ...extra] } });
  });
}

async function openPilot(page: Page) {
  await signIn(page, PILOT_RECEPTION);
  await expect(page.getByRole("navigation", { name: "Navegación principal" })).toBeVisible();
  await page.goto(`/agenda?date=${pilotDay()}`);
  await expect(page.locator(".agenda-card").first()).toBeVisible();
}

/** Whether a card is drawn in the row whose name is `row`: its vertical middle falls inside the row's label. */
async function inRow(page: Page, card: Locator, row: string) {
  const label = (await page.getByRole("group", { name: row, exact: true }).boundingBox())!;
  const box = (await card.boundingBox())!;
  const middle = box.y + box.height / 2;
  return middle > label.y && middle < label.y + label.height;
}

/** Whether a card starts inside the hour column labelled `HH:00` in the header: its position, not its text. */
async function inHour(page: Page, card: Locator, day: string, hour: string) {
  const column = page.locator(
    `.ec-timeline .ec-header .ec-slot:has(time[datetime="${day}T${hour}:00:00"])`,
  );
  const slot = (await column.boundingBox())!;
  const box = (await card.boundingBox())!;
  return box.x >= slot.x - 2 && box.x < slot.x + slot.width;
}

const agendaBox = (page: Page) => page.locator("[data-slot=agenda-view]");

test.describe("agenda en filas", () => {
  test("con 15 profesionales todas las filas se alcanzan por dentro y el encabezado de horas queda fijo", async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await fifteenProfessionals(page);
    await openPilot(page);
    await expect(page.locator(".agenda-row")).toHaveCount(ROWS);
    await shot(page, testInfo, "40-agenda-15-filas");

    const scroller = page.locator(".ec-main");
    const header = page.locator(".ec-timeline .ec-header");
    const headerBefore = (await header.boundingBox())!.y;
    const scrolled = await scroller.evaluate((main) => {
      main.scrollTop = main.scrollHeight;
      return main.scrollTop;
    });
    expect(scrolled, "la agenda debe desplazarse por dentro").toBeGreaterThan(0);

    const last = page.getByRole("group", { name: EXTRA_NAMES.at(-1)!, exact: true });
    const lastBox = (await last.boundingBox())!;
    const scrollerBox = (await scroller.boundingBox())!;
    expect(lastBox.y + lastBox.height).toBeLessThanOrEqual(scrollerBox.y + scrollerBox.height + 1);
    expect((await header.boundingBox())!.y).toBe(headerBefore);
    expect(
      await page.evaluate(() => document.scrollingElement!.scrollHeight <= window.innerHeight),
    ).toBe(true);
    // On the pilot's own day the now line is drawn: its label in the header sits on it.
    const label = page.locator(".agenda-now-label");
    if (await label.isVisible()) {
      const labelBox = (await label.boundingBox())!;
      const line = (await page.locator(".agenda-now").first().boundingBox())!;
      expect(Math.abs(labelBox.x + labelBox.width / 2 - (line.x + line.width / 2))).toBeLessThan(2);
    }
    await shot(page, testInfo, "41-agenda-15-filas-desplazada");

    await page.getByRole("button", { name: "Vista compacta" }).click();
    await expect(agendaBox(page)).toHaveAttribute("data-density", "compact");
    await shot(page, testInfo, "42-agenda-15-filas-compacta");
    await page.getByRole("button", { name: "Vista cómoda" }).click();
  });

  test("abrir Próximas llegadas no cambia el ancho de la agenda", async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await openPilot(page);
    const before = (await agendaBox(page).boundingBox())!.width;

    await page.getByRole("button", { name: /Próximas llegadas/ }).click();
    await expect(page.getByRole("complementary", { name: "Próximas llegadas" })).toBeVisible();

    expect((await agendaBox(page).boundingBox())!.width).toBe(before);
    await shot(page, testInfo, "43-agenda-llegadas-flotante");
  });

  test("la semana de otro profesional muestra sus citas de lunes a domingo", async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await openPilot(page);
    const weekOf = (response: { url(): string; ok(): boolean }) =>
      response.ok() ? new URL(response.url()).searchParams.get("professional_id") : null;
    const firstWeek = page.waitForResponse((response) => !!weekOf(response));
    await page.getByRole("button", { name: "Semana", exact: true }).click();
    const opened = weekOf(await firstWeek);
    await page.getByRole("combobox", { name: "Profesional de la semana" }).click();
    // The week opens with the first professional; Luis is the second one the pilot creates.
    const listing = page.waitForResponse((response) => {
      const id = weekOf(response);
      return !!id && id !== opened;
    });
    await page.getByRole("option", { name: "Luis Pérez" }).click();
    const { data } = (await (await listing).json()) as {
      data: { professional_id: string; customer_name: string; status: string }[];
    };

    await expect(page.locator(".ec-col-head")).toHaveCount(7);
    expect(new Set(data.map((item) => item.professional_id)).size).toBe(1);
    const shown = data.find((item) => !["cancelled", "rescheduled"].includes(item.status))!;
    await expect(
      page.getByRole("button", { name: new RegExp(shown.customer_name) }).first(),
    ).toBeAttached();
    await shot(page, testInfo, "44-agenda-semana-otro-profesional");
  });

  test.describe("con el navegador en Madrid", () => {
    test.use({ timezoneId: "Europe/Madrid" });

    test("cada cita queda en la fila de su profesional y a la hora de Managua", async ({
      page,
    }, testInfo) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      const professionals = page.waitForResponse(
        (response) => /\/appointments\/professionals(\?|$)/.test(response.url()) && response.ok(),
      );
      // Today's arrivals are another listing: on a Sunday it is not the pilot's day.
      const listing = page.waitForResponse(
        (response) => response.url().includes(`/appointments?from=${pilotDay()}`) && response.ok(),
      );
      await openPilot(page);
      const names = new Map(
        (
          (await (await professionals).json()) as { data: { id: string; display_name: string }[] }
        ).data.map((item) => [item.id, item.display_name]),
      );
      const { data } = (await (await listing).json()) as {
        data: {
          starts_at: string;
          status: string;
          customer_name: string;
          professional_id: string;
        }[];
      };
      const checked = data
        .filter((item) => !["cancelled", "rescheduled"].includes(item.status))
        .slice(0, 3);
      expect(checked.length).toBeGreaterThan(0);
      for (const item of checked) {
        const hour = new Intl.DateTimeFormat("es-NI", {
          hour: "numeric",
          minute: "2-digit",
          hour12: true,
          timeZone: "America/Managua",
        })
          .formatToParts(new Date(item.starts_at))
          .filter((part) => part.type === "hour" || part.type === "minute")
          .map((part) => part.value)
          .join(":");
        // The pilot reuses customer names: the hour tells the appointments apart.
        const card = page
          .getByRole("button", { name: new RegExp(`^${item.customer_name}[^:]*\\b${hour}\\s`) })
          .first();
        await expect(card).toContainText(hour);
        expect(await inRow(page, card, names.get(item.professional_id)!)).toBe(true);
        const hourColumn = new Intl.DateTimeFormat("en-GB", {
          hour: "2-digit",
          hourCycle: "h23",
          timeZone: "America/Managua",
        }).format(new Date(item.starts_at));
        expect(await inHour(page, card, pilotDay(), hourColumn)).toBe(true);
      }
      await shot(page, testInfo, "45-agenda-filas-madrid");
    });
  });

  test.describe("en un celular", () => {
    test.use({ viewport: { width: 390, height: 844 }, hasTouch: true });

    test("tocar un hueco libre abre Nueva cita con ese profesional y esa hora", async ({
      page,
    }, testInfo) => {
      await openAgenda(page, RECEPTION, nextWorkingDay());
      await page
        .getByRole("group", { name: "Profesional" })
        .getByRole("button", { name: new RegExp(RAMIRO) })
        .click();
      const free = page.getByRole("button", { name: /^Libre/ }).first();
      const label = (await free.getAttribute("aria-label")) ?? "";
      const time = /a las (.+?) con/.exec(label)?.[1] ?? "";
      expect(time).not.toBe("");
      await shot(page, testInfo, "46-agenda-movil-lista");

      await free.click();
      const panel = sidePanel(page, "Nueva cita");
      await expect(panel.getByRole("combobox", { name: "Profesional" })).toContainText(RAMIRO);
      await panel.getByRole("checkbox", { name: "Afeitado clásico" }).click();
      await expect(panel.getByRole("button", { name: time, pressed: true })).toBeVisible();
      expect(
        await page.evaluate(() => document.scrollingElement!.scrollWidth <= window.innerWidth),
      ).toBe(true);
      await shot(page, testInfo, "47-agenda-movil-nueva-cita");
    });
  });
});

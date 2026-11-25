import { expect, test } from "@playwright/test";
import { shot } from "./helpers";
import {
  DON_EFRAIN,
  PROFESSIONAL,
  RAMIRO,
  RECEPTION,
  appointmentCard,
  bookNewCustomer,
  cancelIfPresent,
  chooseNewCustomer,
  freeTimes,
  nextWorkingDay,
  openAgenda,
  openAppointment,
  secondSession,
  sidePanel,
  startBooking,
  uniquePhone,
} from "./agenda-helpers";

// The agenda against the real API. These flows WRITE: each uses its own customer and cancels its appointments.
const day = nextWorkingDay();

test.describe("agenda del staff", () => {
  test("recepción crea, mueve y cancela una cita, y queda la cadena de reprogramación", async ({
    page,
  }, testInfo) => {
    const stamp = Date.now();
    const customer = `e2e-cliente-${stamp}`;
    await openAgenda(page, RECEPTION, day);
    await expect(page.getByRole("group", { name: DON_EFRAIN })).toBeVisible();
    await expect(page.getByRole("group", { name: RAMIRO })).toBeVisible();

    try {
      await bookNewCustomer(page, {
        professional: DON_EFRAIN,
        service: "Corte clásico",
        customer,
        phone: uniquePhone(stamp),
      });
      await shot(page, testInfo, "20-agenda-cita-creada");

      await openAppointment(page, customer);
      const panel = sidePanel(page, customer);
      await panel.getByRole("button", { name: "Reprogramar" }).click();
      await panel
        .getByRole("button", { name: /\d:\d\d/ })
        .last()
        .click();
      await panel.getByRole("button", { name: "Mover cita" }).click();
      await expect(page.getByText("Cita movida. Queda por confirmar.")).toBeVisible();

      await openAppointment(page, customer);
      await expect(sidePanel(page, customer).getByText(/Reprogramada desde/)).toBeVisible();
      await shot(page, testInfo, "21-agenda-cita-movida");
    } finally {
      await cancelIfPresent(page, customer);
    }
    await expect(appointmentCard(page, customer)).toHaveCount(0);
  });

  test("si dos recepcionistas toman el mismo hueco, la segunda recibe el aviso y la agenda se actualiza", async ({
    page,
    browser,
  }) => {
    const stamp = Date.now();
    const winner = `e2e-gana-${stamp}`;
    const loser = `e2e-pierde-${stamp}`;
    await openAgenda(page, RECEPTION, day);
    const other = await secondSession(browser, RECEPTION, day);

    try {
      // The second receptionist has the slot chosen before the first one confirms it.
      await startBooking(other.page, RAMIRO, "Afeitado clásico");
      await freeTimes(other.page).first().click();
      await chooseNewCustomer(other.page, loser, uniquePhone(stamp, 1));

      await bookNewCustomer(page, {
        professional: RAMIRO,
        service: "Afeitado clásico",
        customer: winner,
        phone: uniquePhone(stamp, 2),
      });

      await sidePanel(other.page, "Nueva cita")
        .getByRole("button", { name: "Confirmar cita" })
        .click();
      await expect(other.page.getByText(/El horario ya no está disponible/)).toBeVisible();
      await expect(appointmentCard(other.page, winner)).toBeVisible();
      await expect(appointmentCard(other.page, loser)).toHaveCount(0);
    } finally {
      await other.context.close();
      await cancelIfPresent(page, winner);
    }
  });

  test("el profesional ve sus citas y solo actúa sobre ellas; con otra zona del navegador la hora no cambia", async ({
    page,
    browser,
  }) => {
    const stamp = Date.now();
    const customer = `e2e-propia-${stamp}`;
    await openAgenda(page, RECEPTION, day);
    const professional = {
      context: null as Awaited<ReturnType<typeof secondSession>>["context"] | null,
    };

    try {
      await bookNewCustomer(page, {
        professional: DON_EFRAIN,
        service: "Corte clásico",
        customer,
        phone: uniquePhone(stamp, 3),
      });
      const managuaCard = (await appointmentCard(page, customer).textContent()) ?? "";

      const session = await secondSession(browser, PROFESSIONAL, day, "Europe/Madrid");
      professional.context = session.context;
      await expect(session.page.getByRole("group", { name: DON_EFRAIN })).toBeVisible();
      await expect(session.page.getByRole("group", { name: RAMIRO })).toHaveCount(0);
      await expect(session.page.getByRole("button", { name: "Nueva cita" })).toHaveCount(0);

      const card = appointmentCard(session.page, customer);
      await expect(card).toBeVisible();
      expect(await card.textContent()).toBe(managuaCard);

      await card.click();
      const panel = sidePanel(session.page, customer);
      await expect(panel.getByRole("button", { name: "Confirmar", exact: true })).toBeVisible();
      await expect(panel.getByRole("button", { name: "Cancelar cita" })).toHaveCount(0);
      await expect(panel.getByRole("button", { name: "Reprogramar" })).toHaveCount(0);
    } finally {
      await professional.context?.close();
      await cancelIfPresent(page, customer);
    }
  });
});

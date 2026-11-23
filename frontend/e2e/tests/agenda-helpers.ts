import { expect, type Browser, type Page } from "@playwright/test";
import { signIn } from "./helpers";

export const RECEPTION = "recepcion@barberia-guegu.ceiba.test";
export const PROFESSIONAL = "profesional@barberia-guegu.ceiba.test";
export const DON_EFRAIN = "Don Efraín Blandón";
export const RAMIRO = "Ramiro Salinas";
const BRANCH_ZONE = "America/Managua";

/** The next Tuesday-to-Saturday in the branch's zone: the days both demo barbers work, never in the past. */
export function nextWorkingDay(from = new Date()) {
  const day = new Date(`${from.toLocaleDateString("en-CA", { timeZone: BRANCH_ZONE })}T12:00:00Z`);
  do day.setUTCDate(day.getUTCDate() + 1);
  while (day.getUTCDay() === 0 || day.getUTCDay() === 1);
  return day.toISOString().slice(0, 10);
}

export const uniquePhone = (stamp: number, offset = 0) => `8${String(stamp + offset).slice(-7)}`;

export const appointmentCard = (page: Page, customer: string) =>
  page.getByRole("button", { name: new RegExp(customer) });

export const sidePanel = (page: Page, name: string) => page.getByRole("complementary", { name });

export async function openAgenda(page: Page, email: string, day: string) {
  await signIn(page, email);
  await expect(page.getByRole("navigation", { name: "Navegación principal" })).toBeVisible();
  await page.goto(`/agenda?date=${day}`);
  await expect(page.getByRole("heading", { level: 1, name: /Agenda del/ })).toBeVisible();
}

export async function startBooking(page: Page, professional: string, service: string) {
  await page.getByRole("button", { name: "Nueva cita" }).click();
  const panel = sidePanel(page, "Nueva cita");
  await panel.getByRole("combobox", { name: "Profesional" }).click();
  await page.getByRole("option", { name: professional }).click();
  await panel.getByRole("checkbox", { name: service }).click();
  return panel;
}

export const freeTimes = (page: Page) =>
  sidePanel(page, "Nueva cita").getByRole("button", { name: /\d:\d\d/ });

export async function chooseNewCustomer(page: Page, name: string, phone: string) {
  const panel = sidePanel(page, "Nueva cita");
  await panel.getByLabel("Buscar cliente").fill(name);
  await panel.getByRole("button", { name: "Crear cliente" }).click();
  await panel.getByLabel("Nombre completo").fill(name);
  await panel.getByLabel("Teléfono").fill(phone);
  await panel.getByRole("button", { name: "Guardar cliente" }).click();
  await expect(panel.getByRole("button", { name: "Cambiar cliente" })).toBeVisible();
}

export async function bookNewCustomer(
  page: Page,
  {
    professional,
    service,
    customer,
    phone,
  }: Record<"professional" | "service" | "customer" | "phone", string>,
) {
  await startBooking(page, professional, service);
  await freeTimes(page).first().click();
  await chooseNewCustomer(page, customer, phone);
  await sidePanel(page, "Nueva cita").getByRole("button", { name: "Confirmar cita" }).click();
  await expect(appointmentCard(page, customer)).toBeVisible();
}

export async function cancelAppointment(page: Page, customer: string) {
  await page.keyboard.press("Escape");
  await appointmentCard(page, customer).click();
  const panel = sidePanel(page, customer);
  await panel.getByRole("button", { name: "Cancelar cita" }).click();
  await panel.getByRole("combobox", { name: "Motivo" }).click();
  await page.getByRole("option", { name: "Decisión del negocio" }).click();
  await panel.getByRole("button", { name: "Confirmar cancelación" }).click();
  await expect(appointmentCard(page, customer)).toHaveCount(0);
}

/** Best effort: a failed test must not leave an appointment occupying the slot of the next run. */
export async function cancelIfPresent(page: Page, customer: string) {
  if (await appointmentCard(page, customer).count()) await cancelAppointment(page, customer);
}

export async function secondSession(
  browser: Browser,
  email: string,
  day: string,
  timezoneId?: string,
) {
  const context = await browser.newContext({
    locale: "es-NI",
    ...(timezoneId ? { timezoneId } : {}),
  });
  const page = await context.newPage();
  await openAgenda(page, email, day);
  return { context, page };
}

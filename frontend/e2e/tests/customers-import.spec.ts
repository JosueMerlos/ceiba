import { expect, test, type Page } from "@playwright/test";
import { shot, signIn } from "./helpers";

// Customer import against the real environment (API, worker and database). It CREATES customers: every run uses its own
// block of phone numbers, so a run never collides with an earlier one. Customers are archived, never deleted, so they stay.
const MANAGER = "gerente@barberia-guegu.ceiba.test";
const ROWS = 20;
const INVALID = new Set([4, 13]);

const nav = (page: Page) => page.getByRole("navigation", { name: "Navegación principal" });

/** A block of Nicaraguan mobile numbers (8 digits starting with 8) unique to this run. */
function phoneBlock() {
  const base = 80_000_000 + (Date.now() % 900_000) * 10;
  return (index: number) => {
    const digits = String(base + index);
    return `${digits.slice(0, 4)} ${digits.slice(4)}`;
  };
}

/** The file as Excel in Spanish saves it: Windows-1252, ";" and CRLF. */
function excelCsv(rows: number, phone: (index: number) => string) {
  const lines = ["Nombre;Teléfono;Correo"];
  for (let index = 0; index < rows; index += 1) {
    lines.push(
      INVALID.has(index)
        ? `Persona inválida ${index};123;`
        : `Señora Núñez ${index};${phone(index)};`,
    );
  }
  return Buffer.from(`${lines.join("\r\n")}\r\n`, "latin1");
}

async function upload(page: Page, name: string, buffer: Buffer) {
  await page.getByRole("radio", { name: "Clientes" }).check();
  await page.getByLabel("Archivo CSV").setInputFiles({ name, mimeType: "text/csv", buffer });
}

test.describe("importación de clientes desde CSV (AC1, AC2, AC5)", () => {
  test("previsualiza un CSV de Excel, importa las filas válidas y reimportarlo no duplica", async ({
    page,
  }, testInfo) => {
    const phone = phoneBlock();
    const file = excelCsv(ROWS, phone);

    await signIn(page, MANAGER);
    await nav(page).getByRole("link", { name: "Clientes" }).click();
    await page.getByRole("link", { name: "Importar desde CSV" }).first().click();
    await upload(page, "clientes-excel.csv", file);

    const summary = page.getByRole("region", { name: "Resumen del archivo" });
    await expect(summary.getByText(`${ROWS - INVALID.size} listas para importar`)).toBeVisible();
    await expect(summary.getByText(`${INVALID.size} con errores: no se importarán`)).toBeVisible();
    const errors = page.getByRole("list", { name: "Filas con errores" });
    await expect(errors.getByRole("listitem")).toHaveText([
      "Fila 6: Teléfono: no es un número válido",
      "Fila 15: Teléfono: no es un número válido",
    ]);
    await expect(page.getByRole("cell", { name: "Señora Núñez 0" })).toBeVisible();
    await shot(page, testInfo, "20-importacion-previsualizacion");

    await page.getByRole("button", { name: `Importar ${ROWS - INVALID.size} filas` }).click();
    const report = page.getByRole("region", { name: "Importación terminada" });
    await expect(report.getByText(`${ROWS - INVALID.size} creados`)).toBeVisible({
      timeout: 30_000,
    });
    await shot(page, testInfo, "21-importacion-reporte");

    // The same file again, skipping duplicates: nobody is created twice.
    await report.getByRole("button", { name: "Importar otro archivo" }).click();
    await upload(page, "clientes-excel.csv", file);
    await page.getByRole("button", { name: `Importar ${ROWS - INVALID.size} filas` }).click();
    await expect(report.getByText(`${ROWS - INVALID.size} omitidos`)).toBeVisible({
      timeout: 30_000,
    });
    await expect(report.getByText(/creados/)).toHaveCount(0);

    // An imported customer is found by phone and opens their profile.
    await nav(page).getByRole("link", { name: "Clientes" }).click();
    await page.getByRole("searchbox", { name: "Buscar clientes" }).fill(phone(0));
    await page.getByRole("link", { name: "Señora Núñez 0" }).click();
    await expect(page.getByRole("heading", { level: 1, name: "Señora Núñez 0" })).toBeVisible();
  });

  test("un archivo de 6000 filas se rechaza con un mensaje claro", async ({ page }) => {
    const rows = [
      "nombre;telefono",
      ...Array.from({ length: 6000 }, (_, index) => `P ${index};8800 0000`),
    ];

    await signIn(page, MANAGER);
    await expect(nav(page)).toBeVisible();
    await page.goto("/customers/import");
    await upload(page, "grande.csv", Buffer.from(rows.join("\n"), "utf8"));

    await expect(
      page.getByText(
        "El archivo tiene 6000 filas y el máximo es 5000: divídelo en varios archivos",
      ),
    ).toBeVisible();
  });
});

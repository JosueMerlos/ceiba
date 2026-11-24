import { formatClock } from "@ceiba/i18n";
import { fireEvent, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { scheduleSlot } from "../../../test/fixtures";
import { renderWithI18n } from "../../../test/render-with-i18n";
import { WeeklyScheduleEditor } from "./weekly-schedule-editor";

const day = (name: string) => screen.getByRole("group", { name });
// The field commits what is typed when it loses focus, as a person tabbing out of it.
const setTime = (input: HTMLElement, value: string) => {
  fireEvent.change(input, { target: { value } });
  fireEvent.blur(input);
};

const MONDAY = scheduleSlot("s1", 1, "09:00", "13:00");

async function renderEditor(
  props: Partial<React.ComponentProps<typeof WeeklyScheduleEditor>> = {},
) {
  const onSave = vi.fn();
  const view = await renderWithI18n(
    <WeeklyScheduleEditor slots={[MONDAY]} onSave={onSave} {...props} />,
  );
  return { onSave, ...view };
}

describe("WeeklyScheduleEditor", () => {
  it("muestra las franjas en su día, lunes primero, y marca como cerrados los días sin franja", async () => {
    await renderEditor({ slots: [MONDAY, scheduleSlot("s2", 0, "10:00", "12:00")] });

    const names = screen.getAllByRole("group").map((group) => group.getAttribute("aria-label"));
    expect(names).toEqual([
      "Lunes",
      "Martes",
      "Miércoles",
      "Jueves",
      "Viernes",
      "Sábado",
      "Domingo",
    ]);
    expect(within(day("Lunes")).getByLabelText("Inicio")).toHaveProperty(
      "value",
      formatClock("09:00"),
    );
    expect(within(day("Lunes")).getByLabelText("Fin")).toHaveProperty(
      "value",
      formatClock("13:00"),
    );
    expect(within(day("Domingo")).getByLabelText("Inicio")).toHaveProperty(
      "value",
      formatClock("10:00"),
    );
    expect(within(day("Martes")).getByText("Cerrado")).toBeTruthy();
  });

  it("agrega una franja, la edita y envía el horario completo ordenado", async () => {
    const { user, onSave } = await renderEditor();

    await user.click(within(day("Martes")).getByRole("button", { name: "Agregar franja" }));
    setTime(within(day("Martes")).getByLabelText("Inicio"), "08:00");
    setTime(within(day("Martes")).getByLabelText("Fin"), "12:30");
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect(onSave).toHaveBeenCalledWith({
      slots: [
        { weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00" },
        { weekday: 2, starts_at_local: "08:00", ends_at_local: "12:30" },
      ],
    });
  });

  it("quita una franja", async () => {
    const { user, onSave } = await renderEditor({
      slots: [MONDAY, scheduleSlot("s2", 1, "14:00", "18:00")],
    });

    await user.click(within(day("Lunes")).getAllByRole("button", { name: "Quitar franja" })[0]!);
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect(onSave).toHaveBeenCalledWith({
      slots: [{ weekday: 1, starts_at_local: "14:00", ends_at_local: "18:00" }],
    });
  });

  it("AC3: dos franjas solapadas el mismo día marcan el campo y NO llaman a guardar", async () => {
    const { user, onSave } = await renderEditor({
      slots: [MONDAY, scheduleSlot("s2", 1, "12:00", "15:00")],
    });

    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect(onSave).not.toHaveBeenCalled();
    const alerts = within(day("Lunes")).getAllByRole("alert");
    expect(alerts.map((alert) => alert.textContent)).toEqual([
      "Esta franja se cruza con otra del mismo día.",
      "Esta franja se cruza con otra del mismo día.",
    ]);
    expect(within(day("Lunes")).getAllByLabelText("Inicio")[0]!.getAttribute("aria-invalid")).toBe(
      "true",
    );
  });

  it("AC3: un fin igual o anterior al inicio marca el error y no guarda", async () => {
    const { user, onSave } = await renderEditor();

    setTime(within(day("Lunes")).getByLabelText("Fin"), "09:00");
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect(onSave).not.toHaveBeenCalled();
    expect(within(day("Lunes")).getByRole("alert").textContent).toBe(
      "La hora de fin debe ser posterior a la de inicio.",
    );
  });

  it("una hora inválida a la vista no deja guardar la hora anterior", async () => {
    const { user, onSave } = await renderEditor();

    setTime(within(day("Lunes")).getByLabelText("Fin"), "9:75");
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect(onSave).not.toHaveBeenCalled();
    expect(within(day("Lunes")).getByLabelText("Fin")).toHaveProperty("value", "9:75");
    expect(within(day("Lunes")).getByLabelText("Fin").getAttribute("aria-invalid")).toBe("true");
  });

  it("corregir la franja limpia el error y deja guardar", async () => {
    const { user, onSave } = await renderEditor({
      slots: [MONDAY, scheduleSlot("s2", 1, "12:00", "15:00")],
    });
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    setTime(within(day("Lunes")).getAllByLabelText("Inicio")[1]!, "13:00");
    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect(within(day("Lunes")).queryByRole("alert")).toBeNull();
    expect(onSave).toHaveBeenCalledOnce();
  });

  it("con la validación del cliente apagada, el solape llega a guardar (lo decide el servidor)", async () => {
    const { user, onSave } = await renderEditor({
      validateClient: false,
      slots: [MONDAY, scheduleSlot("s2", 1, "12:00", "15:00")],
    });

    await user.click(screen.getByRole("button", { name: "Guardar horario" }));

    expect(onSave).toHaveBeenCalledOnce();
  });

  it("muestra los errores que devolvió el servidor en el editor", async () => {
    await renderEditor({ serverMessages: ["se cruza con otro horario del profesional"] });

    expect(screen.getByRole("alert").textContent).toContain(
      "se cruza con otro horario del profesional",
    );
  });

  it("guardar sin franjas pide confirmar que la sucursal quedará cerrada", async () => {
    const { user, onSave } = await renderEditor({ slots: [] });

    await user.click(screen.getByRole("button", { name: "Guardar horario" }));
    expect(onSave).not.toHaveBeenCalled();
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).getByText(/la sucursal quedará cerrada/i)).toBeTruthy();

    await user.click(within(dialog).getByRole("button", { name: "Dejar cerrada" }));
    expect(onSave).toHaveBeenCalledWith({ slots: [] });
  });

  it("cancelar la confirmación no guarda", async () => {
    const { user, onSave } = await renderEditor({ slots: [] });

    await user.click(screen.getByRole("button", { name: "Guardar horario" }));
    await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Cancelar" }));

    expect(onSave).not.toHaveBeenCalled();
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("de solo lectura no hay campos ni botones de edición", async () => {
    await renderEditor({ readOnly: true });

    expect(screen.queryByLabelText("Inicio")).toBeNull();
    expect(screen.queryByRole("button", { name: "Guardar horario" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Agregar franja" })).toBeNull();
    expect(within(day("Lunes")).getByText("9:00 a. m. – 1:00 p. m.")).toBeTruthy();
  });

  describe("dentro de un modal (formId)", () => {
    async function renderInDialog(
      props: Partial<React.ComponentProps<typeof WeeklyScheduleEditor>> = {},
    ) {
      const onSave = vi.fn();
      const view = await renderWithI18n(
        <>
          <WeeklyScheduleEditor slots={[MONDAY]} onSave={onSave} formId="schedule" {...props} />
          <button type="submit" form="schedule">
            Pie del modal
          </button>
        </>,
      );
      return { onSave, ...view };
    }

    it("no pinta su propio botón: el del pie del modal envía el horario", async () => {
      const { user, onSave } = await renderInDialog();

      expect(screen.queryByRole("button", { name: "Guardar horario" })).toBeNull();
      await user.click(within(day("Martes")).getByRole("button", { name: "Agregar franja" }));
      await user.click(screen.getByRole("button", { name: "Pie del modal" }));

      expect(onSave).toHaveBeenCalledWith({
        slots: [
          { weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00" },
          { weekday: 2, starts_at_local: "09:00", ends_at_local: "13:00" },
        ],
      });
    });

    it("sin franjas sigue pidiendo confirmar la semana cerrada", async () => {
      const { user, onSave } = await renderInDialog({ slots: [] });

      await user.click(screen.getByRole("button", { name: "Pie del modal" }));
      expect(onSave).not.toHaveBeenCalled();
      await user.click(
        within(screen.getByRole("dialog")).getByRole("button", { name: "Dejar cerrada" }),
      );
      expect(onSave).toHaveBeenCalledWith({ slots: [] });
    });

    it("avisa cuando el horario difiere del guardado y cuando vuelve a coincidir", async () => {
      const onDirtyChange = vi.fn();
      const { user } = await renderInDialog({ onDirtyChange });

      await user.click(within(day("Martes")).getByRole("button", { name: "Agregar franja" }));
      expect(onDirtyChange).toHaveBeenLastCalledWith(true);
      await user.click(within(day("Martes")).getByRole("button", { name: "Quitar franja" }));
      expect(onDirtyChange).toHaveBeenLastCalledWith(false);
    });
  });
});

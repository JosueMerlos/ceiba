import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { FormDialog } from "../src";

const TABS = [
  { id: "perfil", label: "Perfil" },
  { id: "servicios", label: "Servicios" },
];

function TabsHarness({ dirty = true, onSave }: { dirty?: boolean; onSave?: () => void }) {
  const [open, setOpen] = useState(true);
  const [tab, setTab] = useState("perfil");
  return (
    <>
      <p data-testid="estado">{open ? "abierto" : "cerrado"}</p>
      <FormDialog
        open={open}
        onOpenChange={setOpen}
        title="Editar profesional"
        closeLabel="Cerrar"
        tabs={TABS}
        tab={tab}
        onTabChange={setTab}
        dirty={dirty}
        formId="form-perfil"
        saveLabel="Guardar cambios"
        tabsLabel="Secciones"
        confirmTitle="¿Descartar los cambios?"
        confirmDescription="Lo que cambió en esta pestaña se perderá."
        discardLabel="Descartar"
        keepLabel="Seguir editando"
      >
        <form
          id="form-perfil"
          onSubmit={(event) => {
            event.preventDefault();
            onSave?.();
          }}
        >
          <label>
            Nombre
            <input defaultValue="Ana" />
          </label>
          <p>Pestaña {tab}</p>
        </form>
      </FormDialog>
    </>
  );
}

const STEPS = [
  { id: "perfil", label: "Perfil" },
  { id: "servicios", label: "Servicios", optional: true },
  { id: "ausencias", label: "Ausencias", optional: true },
];

function StepsHarness({ onSkip }: { onSkip?: () => void }) {
  const [step, setStep] = useState("perfil");
  const index = STEPS.findIndex((item) => item.id === step);
  return (
    <FormDialog
      open
      onOpenChange={() => {}}
      title="Nuevo profesional"
      closeLabel="Cerrar"
      steps={STEPS}
      step={step}
      onBack={() => setStep(STEPS[index - 1]!.id)}
      onSkip={() => {
        onSkip?.();
        setStep(STEPS[index + 1]!.id);
      }}
      formId="form-paso"
      backLabel="Atrás"
      skipLabel="Omitir por ahora"
      continueLabel="Continuar"
      finishLabel="Terminar"
      stepsLabel="Pasos"
    >
      <form
        id="form-paso"
        onSubmit={(event) => {
          event.preventDefault();
          if (index < STEPS.length - 1) setStep(STEPS[index + 1]!.id);
        }}
      >
        <label>
          Campo de {step}
          <input />
        </label>
      </form>
    </FormDialog>
  );
}

const dialog = () => screen.getByRole("dialog", { name: "Editar profesional" });

describe("FormDialog en modo pestañas", () => {
  it("tiene un solo botón de guardar visible, que envía el formulario de la pestaña", async () => {
    const onSave = vi.fn();
    render(<TabsHarness onSave={onSave} />);
    const user = userEvent.setup();

    const save = within(dialog()).getAllByRole("button", { name: "Guardar cambios" });
    expect(save).toHaveLength(1);
    expect(save[0]!.getAttribute("form")).toBe("form-perfil");

    await user.click(save[0]!);

    expect(onSave).toHaveBeenCalledOnce();
  });

  it("las pestañas son un tablist con la actual seleccionada", () => {
    render(<TabsHarness />);

    const tabs = within(dialog()).getAllByRole("tab");
    expect(tabs.map((tab) => [tab.textContent, tab.getAttribute("aria-selected")])).toEqual([
      ["Perfil", "true"],
      ["Servicios", "false"],
    ]);
  });

  it("con cambios sin guardar, cambiar de pestaña pide confirmar; «Seguir editando» no cambia", async () => {
    render(<TabsHarness />);
    const user = userEvent.setup();

    await user.click(within(dialog()).getByRole("tab", { name: "Servicios" }));

    const alert = screen.getByRole("alertdialog", { name: "¿Descartar los cambios?" });
    await user.click(within(alert).getByRole("button", { name: "Seguir editando" }));

    expect(screen.queryByRole("alertdialog")).toBeNull();
    expect(within(dialog()).getByText("Pestaña perfil")).toBeTruthy();
  });

  it("«Descartar» completa el cambio de pestaña", async () => {
    render(<TabsHarness />);
    const user = userEvent.setup();

    await user.click(within(dialog()).getByRole("tab", { name: "Servicios" }));
    await user.click(screen.getByRole("button", { name: "Descartar" }));

    expect(within(dialog()).getByText("Pestaña servicios")).toBeTruthy();
  });

  it("con cambios sin guardar, cerrar con la X o con Escape pide confirmar", async () => {
    render(<TabsHarness />);
    const user = userEvent.setup();

    await user.click(within(dialog()).getByRole("button", { name: "Cerrar" }));
    expect(screen.getByRole("alertdialog")).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "Seguir editando" }));
    expect(screen.getByTestId("estado").textContent).toBe("abierto");

    await user.click(within(dialog()).getByLabelText("Nombre"));
    await user.keyboard("{Escape}");
    expect(screen.getByRole("alertdialog")).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "Descartar" }));

    expect(screen.getByTestId("estado").textContent).toBe("cerrado");
  });

  it("sin cambios, cambiar de pestaña y cerrar no piden confirmar", async () => {
    render(<TabsHarness dirty={false} />);
    const user = userEvent.setup();

    await user.click(within(dialog()).getByRole("tab", { name: "Servicios" }));
    expect(screen.queryByRole("alertdialog")).toBeNull();
    expect(within(dialog()).getByText("Pestaña servicios")).toBeTruthy();

    await user.keyboard("{Escape}");
    expect(screen.getByTestId("estado").textContent).toBe("cerrado");
  });

  it("encabezado y pie quedan fuera del cuerpo, que es la única región con scroll", () => {
    render(<TabsHarness />);

    const body = dialog().querySelector('[data-slot="form-dialog-body"]')!;
    expect(body.className).toContain("overflow-y-auto");
    expect(
      body.contains(within(dialog()).getByRole("heading", { name: "Editar profesional" })),
    ).toBe(false);
    expect(body.contains(within(dialog()).getByRole("button", { name: "Guardar cambios" }))).toBe(
      false,
    );
    expect(body.contains(within(dialog()).getByLabelText("Nombre"))).toBe(true);
  });

  it("atrapa el foco: Tab desde el último control vuelve al primero", async () => {
    render(<TabsHarness dirty={false} />);
    const user = userEvent.setup();

    within(dialog()).getByRole("button", { name: "Guardar cambios" }).focus();
    await user.tab();

    expect(dialog().contains(document.activeElement)).toBe(true);
  });
});

describe("FormDialog en modo pasos", () => {
  const steps = () => screen.getByRole("dialog", { name: "Nuevo profesional" });

  it("marca el paso actual y avanza con Continuar (el submit de la app decide)", async () => {
    render(<StepsHarness />);
    const user = userEvent.setup();

    const current = () =>
      within(within(steps()).getByRole("list", { name: "Pasos" }))
        .getAllByRole("listitem")
        .find((item) => item.getAttribute("aria-current") === "step")?.textContent;
    expect(current()).toContain("Perfil");
    expect(within(steps()).queryByRole("button", { name: "Atrás" })).toBeNull();
    expect(within(steps()).queryByRole("button", { name: "Omitir por ahora" })).toBeNull();

    await user.click(within(steps()).getByRole("button", { name: "Continuar" }));

    expect(current()).toContain("Servicios");
    expect(within(steps()).getByLabelText("Campo de servicios")).toBeTruthy();
  });

  it("Omitir aparece solo en pasos opcionales y Atrás vuelve", async () => {
    const onSkip = vi.fn();
    render(<StepsHarness onSkip={onSkip} />);
    const user = userEvent.setup();

    await user.click(within(steps()).getByRole("button", { name: "Continuar" }));
    await user.click(within(steps()).getByRole("button", { name: "Omitir por ahora" }));
    expect(onSkip).toHaveBeenCalledOnce();
    expect(within(steps()).getByLabelText("Campo de ausencias")).toBeTruthy();

    await user.click(within(steps()).getByRole("button", { name: "Atrás" }));
    expect(within(steps()).getByLabelText("Campo de servicios")).toBeTruthy();
  });

  it("en el último paso el botón principal dice Terminar", async () => {
    render(<StepsHarness />);
    const user = userEvent.setup();

    await user.click(within(steps()).getByRole("button", { name: "Continuar" }));
    await user.click(within(steps()).getByRole("button", { name: "Continuar" }));

    expect(within(steps()).getByRole("button", { name: "Terminar" }).getAttribute("type")).toBe(
      "submit",
    );
    expect(within(steps()).queryByRole("button", { name: "Continuar" })).toBeNull();
  });
});

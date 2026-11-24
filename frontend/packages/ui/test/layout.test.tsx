import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState, type ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";
import {
  AppLayout,
  ContextPanel,
  NavItem,
  PageBody,
  PageFrame,
  PageHeader,
  StatusPage,
} from "../src";

interface HarnessProps {
  initialCollapsed?: boolean;
  aside?: ReactNode;
  navigation?: ReactNode;
  onCollapsedChange?: (collapsed: boolean) => void;
}

function Harness({
  initialCollapsed = false,
  aside,
  navigation = <NavItem href="/agenda" icon={<svg data-testid="icon" />} label="Agenda" />,
  onCollapsedChange,
}: HarnessProps) {
  const [collapsed, setCollapsed] = useState(initialCollapsed);
  return (
    <AppLayout
      skipLinkLabel="Saltar al contenido"
      navigationLabel="Principal"
      brand={<span>Ceiba</span>}
      context={<button type="button">Estética Rosa</button>}
      navigation={navigation}
      account={<button type="button">Cuenta</button>}
      collapsed={collapsed}
      onCollapsedChange={(next) => {
        setCollapsed(next);
        onCollapsedChange?.(next);
      }}
      collapseLabel="Contraer menú"
      expandLabel="Expandir menú"
      aside={aside}
    >
      <h1>Hoy</h1>
    </AppLayout>
  );
}

describe("AppLayout (marco y hoja)", () => {
  it("expone los puntos de referencia: navegación principal y contenido, sin cabecera superior", () => {
    render(<Harness />);

    const nav = screen.getByRole("navigation", { name: "Principal" });
    expect(within(nav).getByRole("link", { name: "Agenda" })).toBeTruthy();
    expect(within(screen.getByRole("main")).getByRole("heading", { name: "Hoy" })).toBeTruthy();
    expect(screen.queryByRole("banner")).toBeNull();
  });

  it("el marco aloja la marca, el contexto y la cuenta", () => {
    render(<Harness />);

    expect(screen.getByText("Ceiba")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Estética Rosa" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Cuenta" })).toBeTruthy();
  });

  it("ofrece un enlace para saltar al contenido que apunta al <main>", () => {
    render(<Harness />);

    const link = screen.getByRole("link", { name: "Saltar al contenido" });
    expect(link.getAttribute("href")).toBe(`#${screen.getByRole("main").id}`);
  });

  it("contraer y expandir cambia aria-expanded y avisa con el valor nuevo", async () => {
    const onCollapsedChange = vi.fn();
    render(<Harness onCollapsedChange={onCollapsedChange} />);
    const user = userEvent.setup();

    const collapse = screen.getByRole("button", { name: "Contraer menú" });
    expect(collapse.getAttribute("aria-expanded")).toBe("true");
    await user.click(collapse);

    const expand = screen.getByRole("button", { name: "Expandir menú" });
    expect(expand.getAttribute("aria-expanded")).toBe("false");
    expect(onCollapsedChange).toHaveBeenLastCalledWith(true);
    await user.click(expand);
    expect(
      screen.getByRole("button", { name: "Contraer menú" }).getAttribute("aria-expanded"),
    ).toBe("true");
    expect(onCollapsedChange).toHaveBeenLastCalledWith(false);
  });

  it("el botón de contraer controla el marco (aria-controls apunta a un elemento existente)", () => {
    const { container } = render(<Harness />);

    const controlled = screen
      .getByRole("button", { name: "Contraer menú" })
      .getAttribute("aria-controls");
    expect(controlled).toBeTruthy();
    expect(container.querySelector(`#${controlled}`)).not.toBeNull();
  });

  it("el marco refleja el estado en data-collapsed (el CSS lo usa para el riel de 60 px)", () => {
    const { container } = render(<Harness initialCollapsed />);

    expect(container.querySelector("[data-slot='app-frame']")?.getAttribute("data-collapsed")).toBe(
      "true",
    );
  });

  it("en el riel cada ítem lleva aria-label; expandido, el nombre sale del texto", () => {
    const { rerender } = render(<Harness initialCollapsed />);
    expect(screen.getByRole("link", { name: "Agenda" }).getAttribute("aria-label")).toBe("Agenda");

    rerender(<Harness initialCollapsed={false} />);
    // Same component instance keeps its state, so a fresh mount checks the expanded case.
    expect(screen.getByRole("link", { name: "Agenda" })).toBeTruthy();
  });

  it("en el riel el foco por teclado muestra el tooltip con el nombre del ítem", async () => {
    render(<Harness initialCollapsed />);
    const user = userEvent.setup();

    await user.tab();
    while (document.activeElement?.getAttribute("href") !== "/agenda") await user.tab();

    expect((await screen.findByRole("tooltip")).textContent).toContain("Agenda");
  });

  it("expandido no hay tooltip: el texto ya es visible (adversarial)", async () => {
    render(<Harness />);
    const user = userEvent.setup();

    await user.tab();
    while (document.activeElement?.getAttribute("href") !== "/agenda") await user.tab();

    expect(screen.getByRole("link", { name: "Agenda" }).getAttribute("aria-label")).toBeNull();
    expect(screen.queryByRole("tooltip")).toBeNull();
  });

  it("NavItem con asChild estiliza el enlace del router y conserva aria-current", () => {
    render(
      <Harness
        navigation={
          <NavItem asChild icon={<svg />} label="Servicios">
            <a href="/services" aria-current="page" />
          </NavItem>
        }
      />,
    );

    const link = screen.getByRole("link", { name: "Servicios" });
    expect(link.getAttribute("aria-current")).toBe("page");
    expect(link.getAttribute("href")).toBe("/services");
  });

  it("aside se renderiza como complementary junto a la hoja", () => {
    render(<Harness aside={<aside aria-label="Edición">panel</aside>} />);

    expect(screen.getByRole("complementary", { name: "Edición" })).toBeTruthy();
  });

  it("sin aside no hay complementary ni hueco reservado", () => {
    const { container } = render(<Harness />);

    expect(screen.queryByRole("complementary")).toBeNull();
    expect(container.querySelector("[data-slot='app-aside']")).toBeNull();
  });

  it("ocupa exactamente la ventana: el marco no crece y la hoja desplaza su contenido", () => {
    const { container } = render(<Harness />);

    const frame = container.querySelector<HTMLElement>("[data-slot='app-frame']")!;
    expect(frame.className.split(" ")).toEqual(
      expect.arrayContaining(["h-svh", "overflow-hidden"]),
    );
    expect(frame.className).not.toContain("min-h-svh");
    const main = screen.getByRole("main");
    expect(main.className.split(" ")).toEqual(
      expect.arrayContaining(["min-h-0", "overflow-y-auto"]),
    );
    // A block, not a flex column: screens keep their layout (margins, mx-auto) without changes.
    expect(main.className.split(" ")).not.toContain("flex");
  });

  it("la barra lateral ya no es sticky: con el alto fijo no se mueve sola", () => {
    const { container } = render(<Harness />);

    expect(container.querySelector("[data-slot='app-sidebar']")!.className).not.toContain("sticky");
  });

  it("el panel flotante se posiciona sobre la hoja: el contenedor de la hoja es su referencia", () => {
    render(
      <Harness
        aside={
          <ContextPanel id="p" open onOpenChange={() => {}} title="Llegadas" closeLabel="Cerrar">
            x
          </ContextPanel>
        }
      />,
    );

    const panel = screen.getByRole("complementary", { name: "Llegadas" });
    const sheet = screen.getByRole("main").parentElement!;
    expect(sheet.contains(panel)).toBe(true);
    expect(sheet.className.split(" ")).toContain("relative");
  });

  it("PageFrame con PageBody: encabezado fijo y un cuerpo que es la región con scroll", () => {
    render(
      <AppLayout
        skipLinkLabel="Saltar"
        navigationLabel="Principal"
        brand={null}
        navigation={null}
        account={null}
        collapsed={false}
        onCollapsedChange={() => {}}
        collapseLabel="Contraer"
        expandLabel="Expandir"
      >
        <PageFrame>
          <PageHeader title="Agenda" />
          <PageBody>
            <p>Filas</p>
          </PageBody>
        </PageFrame>
      </AppLayout>,
    );

    const body = screen.getByText("Filas").parentElement!;
    expect(body.getAttribute("data-slot")).toBe("page-body");
    expect(body.className.split(" ")).toEqual(
      expect.arrayContaining(["min-h-0", "flex-1", "overflow-y-auto"]),
    );
    const frame = body.parentElement!;
    expect(frame.getAttribute("data-slot")).toBe("page-frame");
    expect(frame.className.split(" ")).toEqual(
      expect.arrayContaining(["flex", "h-full", "min-h-0", "flex-col"]),
    );
    expect(body.contains(screen.getByRole("heading", { name: "Agenda" }))).toBe(false);
  });

  it("sin navegación (null) no renderiza el <nav>", () => {
    render(<Harness navigation={null} />);

    expect(screen.queryByRole("navigation")).toBeNull();
  });
});

describe("StatusPage", () => {
  it("muestra título, descripción y la acción", () => {
    render(
      <StatusPage
        code="404"
        title="No encontrado"
        description="La página no existe."
        action={<a href="/">Volver al inicio</a>}
      />,
    );

    expect(screen.getByRole("heading", { name: "No encontrado" })).toBeTruthy();
    expect(screen.getByText("La página no existe.")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Volver al inicio" })).toBeTruthy();
  });
});

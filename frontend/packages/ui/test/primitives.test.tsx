import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import {
  Badge,
  Checkbox,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Switch,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  Textarea,
  ToggleGroup,
  ToggleGroupItem,
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "../src";

describe("Table", () => {
  it("usa la semántica de tabla con encabezados de columna", () => {
    render(
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Servicio</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow data-state="selected">
            <TableCell>Corte</TableCell>
          </TableRow>
        </TableBody>
      </Table>,
    );

    expect(screen.getByRole("columnheader", { name: "Servicio" }).getAttribute("scope")).toBe(
      "col",
    );
    expect(screen.getByRole("cell", { name: "Corte" })).toBeTruthy();
  });

  it("envuelve la tabla en un contenedor con scroll horizontal (360 px)", () => {
    const { container } = render(
      <Table>
        <TableBody />
      </Table>,
    );

    expect(container.querySelector("[data-slot='table-container']")).not.toBeNull();
  });
});

describe("Badge", () => {
  it("muestra el texto y admite variantes sin perder el contenido", () => {
    render(
      <>
        <Badge>Activo</Badge>
        <Badge variant="muted">Pausado</Badge>
      </>,
    );

    expect(screen.getByText("Activo")).toBeTruthy();
    expect(screen.getByText("Pausado").getAttribute("data-variant")).toBe("muted");
  });
});

describe("Checkbox y Switch", () => {
  it("el checkbox se marca con el teclado y avisa el valor", async () => {
    const onCheckedChange = vi.fn();
    render(<Checkbox aria-label="Activo" onCheckedChange={onCheckedChange} />);
    const user = userEvent.setup();

    await user.tab();
    await user.keyboard(" ");

    expect(onCheckedChange).toHaveBeenCalledWith(true);
    expect(screen.getByRole("checkbox", { name: "Activo" }).getAttribute("aria-checked")).toBe(
      "true",
    );
  });

  it("el switch alterna con role switch y no actúa si está deshabilitado (adversarial)", async () => {
    const onCheckedChange = vi.fn();
    render(
      <>
        <Switch aria-label="Visible" onCheckedChange={onCheckedChange} />
        <Switch aria-label="Bloqueado" disabled onCheckedChange={onCheckedChange} />
      </>,
    );
    const user = userEvent.setup();

    await user.click(screen.getByRole("switch", { name: "Visible" }));
    await user.click(screen.getByRole("switch", { name: "Bloqueado" }));

    expect(onCheckedChange).toHaveBeenCalledTimes(1);
    expect(screen.getByRole("switch", { name: "Visible" }).getAttribute("aria-checked")).toBe(
      "true",
    );
  });
});

describe("Textarea", () => {
  it("es un cuadro de texto asociado a su etiqueta y marca el error", () => {
    render(
      <label>
        Notas
        <Textarea aria-invalid="true" defaultValue="hola" />
      </label>,
    );

    const field = screen.getByRole("textbox", { name: "Notas" });
    expect(field.getAttribute("aria-invalid")).toBe("true");
    expect((field as HTMLTextAreaElement).value).toBe("hola");
  });
});

describe("Select", () => {
  it("elige una opción y avisa el valor", async () => {
    const onValueChange = vi.fn();
    render(
      <Select onValueChange={onValueChange}>
        <SelectTrigger aria-label="Moneda">
          <SelectValue placeholder="Elija" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="NIO">Córdoba</SelectItem>
          <SelectItem value="USD">Dólar</SelectItem>
        </SelectContent>
      </Select>,
    );
    const user = userEvent.setup();

    await user.click(screen.getByRole("combobox", { name: "Moneda" }));
    await user.click(await screen.findByRole("option", { name: "Dólar" }));

    expect(onValueChange).toHaveBeenCalledWith("USD");
  });

  it("deshabilitado no abre la lista (adversarial)", async () => {
    render(
      <Select disabled>
        <SelectTrigger aria-label="Moneda">
          <SelectValue placeholder="Elija" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="NIO">Córdoba</SelectItem>
        </SelectContent>
      </Select>,
    );
    const user = userEvent.setup();

    await user.click(screen.getByRole("combobox", { name: "Moneda" }));

    expect(screen.queryByRole("option")).toBeNull();
  });
});

describe("ToggleGroup (filtros tipo chip)", () => {
  function Filters() {
    const [value, setValue] = useState("active");
    return (
      <ToggleGroup value={value} onValueChange={setValue} aria-label="Filtrar por estado">
        <ToggleGroupItem value="active">Activos</ToggleGroupItem>
        <ToggleGroupItem value="paused">Pausados</ToggleGroupItem>
      </ToggleGroup>
    );
  }

  it("cada chip expone aria-pressed y cambia al elegir otro", async () => {
    render(<Filters />);
    const user = userEvent.setup();

    const group = screen.getByRole("group", { name: "Filtrar por estado" });
    expect(
      within(group).getByRole("button", { name: "Activos" }).getAttribute("aria-pressed"),
    ).toBe("true");
    await user.click(within(group).getByRole("button", { name: "Pausados" }));

    expect(
      within(group).getByRole("button", { name: "Pausados" }).getAttribute("aria-pressed"),
    ).toBe("true");
    expect(
      within(group).getByRole("button", { name: "Activos" }).getAttribute("aria-pressed"),
    ).toBe("false");
  });

  it("volver a pulsar el chip activo no deja el grupo sin selección", async () => {
    render(<Filters />);
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "Activos" }));

    expect(screen.getByRole("button", { name: "Activos" }).getAttribute("aria-pressed")).toBe(
      "true",
    );
  });
});

describe("Tooltip", () => {
  it("aparece con el foco del teclado y desaparece con Escape", async () => {
    render(
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <button type="button">Agenda</button>
          </TooltipTrigger>
          <TooltipContent>Ir a la agenda</TooltipContent>
        </Tooltip>
      </TooltipProvider>,
    );
    const user = userEvent.setup();

    await user.tab();
    expect((await screen.findByRole("tooltip")).textContent).toContain("Ir a la agenda");
    await user.keyboard("{Escape}");

    expect(screen.queryByRole("tooltip")).toBeNull();
  });
});

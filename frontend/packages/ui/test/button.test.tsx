import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { Button } from "../src";

describe("Button", () => {
  it("es un botón accesible por su nombre y responde al clic", async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Guardar</Button>);

    await userEvent.click(screen.getByRole("button", { name: "Guardar" }));

    expect(onClick).toHaveBeenCalledOnce();
  });

  it("deshabilitado no dispara el clic", async () => {
    const onClick = vi.fn();
    render(
      <Button disabled onClick={onClick}>
        Guardar
      </Button>,
    );

    await userEvent.click(screen.getByRole("button", { name: "Guardar" }));

    expect(onClick).not.toHaveBeenCalled();
  });

  it("en carga se anuncia ocupado y no admite otro clic", async () => {
    const onClick = vi.fn();
    render(
      <Button loading onClick={onClick}>
        Entrar
      </Button>,
    );
    const button = screen.getByRole("button", { name: "Entrar" });

    await userEvent.click(button);

    expect(button.getAttribute("aria-busy")).toBe("true");
    expect(onClick).not.toHaveBeenCalled();
  });

  it("usa los tokens semánticos en sus variantes", () => {
    render(<Button variant="destructive">Eliminar</Button>);

    expect(screen.getByRole("button").className).toMatch(/bg-destructive/);
  });

  it("asChild pinta el enlace con el estilo del botón", () => {
    render(
      <Button asChild>
        <a href="/agenda">Ir a la agenda</a>
      </Button>,
    );

    expect(screen.getByRole("link", { name: "Ir a la agenda" }).className).toMatch(/bg-primary/);
  });
});

import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
  Toaster,
  toast,
} from "../src";

describe("Dialog", () => {
  it("se abre con nombre y descripción accesibles y se cierra con Escape", async () => {
    render(
      <Dialog>
        <DialogTrigger asChild>
          <Button>Abrir</Button>
        </DialogTrigger>
        <DialogContent closeLabel="Cerrar">
          <DialogHeader>
            <DialogTitle>Cerrar todas las sesiones</DialogTitle>
            <DialogDescription>Se cerrará la sesión en todos los dispositivos.</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button>Confirmar</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>,
    );

    await userEvent.click(screen.getByRole("button", { name: "Abrir" }));
    const dialog = await screen.findByRole("dialog", { name: "Cerrar todas las sesiones" });
    expect(dialog.getAttribute("aria-describedby")).toBeTruthy();

    await userEvent.keyboard("{Escape}");

    expect(screen.queryByRole("dialog")).toBeNull();
  });
});

describe("DropdownMenu", () => {
  it("se opera con teclado y entrega la selección", async () => {
    const onSelect = vi.fn();
    const onValueChange = vi.fn();
    render(
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button>Cuenta</Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent>
          <DropdownMenuLabel>Sucursal</DropdownMenuLabel>
          <DropdownMenuRadioGroup value="a" onValueChange={onValueChange}>
            <DropdownMenuRadioItem value="a">Centro</DropdownMenuRadioItem>
            <DropdownMenuRadioItem value="b">Altamira</DropdownMenuRadioItem>
          </DropdownMenuRadioGroup>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={onSelect}>Salir</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>,
    );

    screen.getByRole("button", { name: "Cuenta" }).focus();
    await userEvent.keyboard("{Enter}");
    await userEvent.click(await screen.findByRole("menuitemradio", { name: "Altamira" }));

    expect(onValueChange).toHaveBeenCalledWith("b");
  });
});

describe("Toaster", () => {
  it("anuncia el aviso en una región de estado", async () => {
    render(<Toaster />);

    toast("Cambios guardados");

    expect(await screen.findByText("Cambios guardados")).toBeTruthy();
  });
});

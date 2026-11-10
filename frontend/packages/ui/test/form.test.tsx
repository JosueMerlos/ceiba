import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useForm } from "react-hook-form";
import { describe, expect, it } from "vitest";
import {
  Button,
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  Input,
} from "../src";

function Sample({ onValid }: { onValid: (values: { email: string }) => void }) {
  const form = useForm({ defaultValues: { email: "" } });
  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onValid)} noValidate>
        <FormField
          control={form.control}
          name="email"
          rules={{ required: "Escriba su correo" }}
          render={({ field }) => (
            <FormItem>
              <FormLabel>Correo</FormLabel>
              <FormControl>
                <Input {...field} />
              </FormControl>
              <FormDescription>Con el que se registró</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
        <Button type="submit">Enviar</Button>
      </form>
    </Form>
  );
}

describe("Form", () => {
  it("asocia la etiqueta con el campo", () => {
    render(<Sample onValid={() => {}} />);

    expect(screen.getByLabelText("Correo")).toBeTruthy();
  });

  it("el error se asocia al campo (aria-invalid + aria-describedby) y se anuncia", async () => {
    render(<Sample onValid={() => {}} />);

    await userEvent.click(screen.getByRole("button", { name: "Enviar" }));

    const input = screen.getByLabelText("Correo");
    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toBe("Escriba su correo");
    expect(input.getAttribute("aria-invalid")).toBe("true");
    expect(input.getAttribute("aria-describedby")).toContain(alert.id);
  });

  it("la descripción también describe al campo", () => {
    render(<Sample onValid={() => {}} />);

    const input = screen.getByLabelText("Correo");
    const description = screen.getByText("Con el que se registró");
    expect(input.getAttribute("aria-describedby")).toContain(description.id);
  });
});

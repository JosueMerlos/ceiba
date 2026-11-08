// Configuración compartida de ESLint (flat config) para todas las apps y paquetes del frontend.
// Uso en cada workspace:  export { default } from "@ceiba/config/eslint";
import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["**/dist/**", "**/coverage/**", "**/node_modules/**", "**/*.tsbuildinfo"] },

  js.configs.recommended,
  tseslint.configs.recommended,
  reactHooks.configs.flat.recommended,

  {
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
    rules: {
      "no-console": ["error", { allow: ["warn", "error"] }],
      "@typescript-eslint/consistent-type-imports": ["error", { fixStyle: "inline-type-imports" }],
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },

  // Desactiva las reglas de estilo que chocarían con Prettier. Debe ir al final.
  prettier,
);

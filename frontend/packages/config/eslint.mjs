// Configuración compartida de ESLint (flat config) para todas las apps y paquetes del frontend.
// Uso en cada workspace:  export { default } from "@ceiba/config/eslint";
import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import reactHooks from "eslint-plugin-react-hooks";
import i18next from "eslint-plugin-i18next";
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

  // Ningún texto de UI fuera de i18n (M0.12): el JSX de las apps y de packages/ui solo muestra `t("...")` o props.
  // `jsx-only` revisa el texto y los atributos (placeholder, aria-label, title, alt...); className, type, role, etc. no cuentan.
  // Los tests y los archivos de stories/config quedan fuera: ahí el texto literal es el dato de la prueba.
  {
    files: ["apps/*/src/**/*.tsx", "packages/ui/src/**/*.tsx"],
    ignores: ["**/*.test.tsx", "**/test/**"],
    plugins: { i18next },
    rules: { "i18next/no-literal-string": ["error", { mode: "jsx-only" }] },
  },

  // Desactiva las reglas de estilo que chocarían con Prettier. Debe ir al final.
  prettier,
);

// Configuración compartida de ESLint (flat config) para todas las apps y paquetes del frontend.
// Uso en cada workspace:  export { default } from "@ceiba/config/eslint";
import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import reactHooks from "eslint-plugin-react-hooks";
import i18next from "eslint-plugin-i18next";
import globals from "globals";
import tseslint from "typescript-eslint";

// Atributos JSX cuyo valor ve o escucha el usuario (lectores de pantalla incluidos).
// Incluye las props de texto de los componentes de packages/ui (description, summary, fallback, skipLinkLabel,
// navigationLabel, triggerLabel, closeLabel... y cualquier `*Label`).
const TEXT_PROPS = "alt|title|label|placeholder|description|summary|fallback|[a-zA-Z]+Label";
const TEXT_ATTRIBUTES = [
  `^(${TEXT_PROPS})$`,
  "^aria-(label|description|placeholder|roledescription|valuetext)$",
];

// `no-literal-string` no revisa template literals ni los avisos (toast): se cubren con selectores.
const TEXT_ATTRIBUTE_NAMES = `${TEXT_PROPS}|aria-(label|description|placeholder|roledescription|valuetext)`;
const TEMPLATE_MESSAGE = "Texto de UI fuera de i18n: use t(...) en vez de un template literal.";
const TOAST_CALL = "CallExpression:matches([callee.name='toast'], [callee.object.name='toast'])";
const UI_TEXT_SELECTORS = [
  // Template literal como hijo del JSX, directo o dentro de un ternario / && / ||.
  { selector: "JSXElement > JSXExpressionContainer > TemplateLiteral", message: TEMPLATE_MESSAGE },
  {
    selector: "JSXElement > JSXExpressionContainer > ConditionalExpression > TemplateLiteral",
    message: TEMPLATE_MESSAGE,
  },
  {
    selector: "JSXElement > JSXExpressionContainer > LogicalExpression > TemplateLiteral",
    message: TEMPLATE_MESSAGE,
  },
  // ... y en los atributos de texto (incluidos los aria-*).
  {
    selector: `JSXAttribute[name.name=/^(${TEXT_ATTRIBUTE_NAMES})$/] > JSXExpressionContainer > TemplateLiteral`,
    message: TEMPLATE_MESSAGE,
  },
  {
    selector: `JSXAttribute[name.name=/^(${TEXT_ATTRIBUTE_NAMES})$/] > JSXExpressionContainer > ConditionalExpression > TemplateLiteral`,
    message: TEMPLATE_MESSAGE,
  },
  // Avisos: ni literales, ni template literals, ni concatenaciones, ni ternarios con literales.
  {
    selector: `${TOAST_CALL} > :matches(Literal, TemplateLiteral).arguments:first-child`,
    message: "Aviso con texto fuera de i18n: use toast(t(...)) o toast.<tipo>(t(...)).",
  },
  {
    selector: `${TOAST_CALL} > BinaryExpression.arguments:first-child`,
    message: "Aviso con texto concatenado: use una clave de i18n con interpolación.",
  },
  {
    selector: `${TOAST_CALL} > ConditionalExpression.arguments:first-child > :matches(Literal, TemplateLiteral)`,
    message: "Aviso con texto fuera de i18n: use t(...) en cada rama.",
  },
];

export default tseslint.config(
  {
    ignores: [
      "**/dist/**",
      "**/playwright-report/**",
      "**/test-results/**",
      "**/coverage/**",
      "**/node_modules/**",
      "**/*.tsbuildinfo",
    ],
  },

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
    rules: {
      "i18next/no-literal-string": [
        "error",
        {
          mode: "jsx-only",
          // Solo los atributos que un usuario lee o escucha; data-*, aria-hidden, className, type... no son texto.
          "jsx-attributes": { include: TEXT_ATTRIBUTES },
        },
      ],
    },
  },

  {
    files: ["apps/*/src/**/*.{ts,tsx}", "packages/ui/src/**/*.{ts,tsx}"],
    ignores: ["**/*.test.{ts,tsx}", "**/test/**"],
    rules: { "no-restricted-syntax": ["error", ...UI_TEXT_SELECTORS] },
  },

  // Desactiva las reglas de estilo que chocarían con Prettier. Debe ir al final.
  prettier,
);

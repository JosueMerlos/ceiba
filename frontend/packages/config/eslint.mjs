// Shared ESLint configuration (flat config) for all front-end apps and packages.
// Usage in each workspace:  export { default } from "@ceiba/config/eslint";
import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import reactHooks from "eslint-plugin-react-hooks";
import i18next from "eslint-plugin-i18next";
import globals from "globals";
import tseslint from "typescript-eslint";

// JSX attributes whose value the user sees or hears (screen readers included).
// Includes the text props of packages/ui components (description, summary, fallback, skipLinkLabel, navigationLabel,
// triggerLabel, closeLabel... and any `*Label`).
const TEXT_PROPS = "alt|title|label|placeholder|description|summary|fallback|[a-zA-Z]+Label";
const TEXT_ATTRIBUTES = [
  `^(${TEXT_PROPS})$`,
  "^aria-(label|description|placeholder|roledescription|valuetext)$",
];

// `no-literal-string` does not check template literals or toasts: selectors cover them.
const TEXT_ATTRIBUTE_NAMES = `${TEXT_PROPS}|aria-(label|description|placeholder|roledescription|valuetext)`;
const TEMPLATE_MESSAGE = "Texto de UI fuera de i18n: use t(...) en vez de un template literal.";
const TOAST_CALL = "CallExpression:matches([callee.name='toast'], [callee.object.name='toast'])";
const UI_TEXT_SELECTORS = [
  // Template literal as a JSX child, direct or inside a ternary / && / ||.
  { selector: "JSXElement > JSXExpressionContainer > TemplateLiteral", message: TEMPLATE_MESSAGE },
  {
    selector: "JSXElement > JSXExpressionContainer > ConditionalExpression > TemplateLiteral",
    message: TEMPLATE_MESSAGE,
  },
  {
    selector: "JSXElement > JSXExpressionContainer > LogicalExpression > TemplateLiteral",
    message: TEMPLATE_MESSAGE,
  },
  // ... and in text attributes (aria-* included).
  {
    selector: `JSXAttribute[name.name=/^(${TEXT_ATTRIBUTE_NAMES})$/] > JSXExpressionContainer > TemplateLiteral`,
    message: TEMPLATE_MESSAGE,
  },
  {
    selector: `JSXAttribute[name.name=/^(${TEXT_ATTRIBUTE_NAMES})$/] > JSXExpressionContainer > ConditionalExpression > TemplateLiteral`,
    message: TEMPLATE_MESSAGE,
  },
  // Toasts: no literals, template literals, concatenations or ternaries with literals.
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

  // No UI text outside i18n: app and packages/ui JSX only shows `t("...")` or props.
  // `jsx-only` checks text and attributes (placeholder, aria-label, title, alt...); className, type, role, etc. do not count.
  // Tests and stories/config files are excluded: literal text there is the test data.
  {
    files: ["apps/*/src/**/*.tsx", "packages/ui/src/**/*.tsx"],
    ignores: ["**/*.test.tsx", "**/test/**"],
    plugins: { i18next },
    rules: {
      "i18next/no-literal-string": [
        "error",
        {
          mode: "jsx-only",
          // Only attributes a user reads or hears; data-*, aria-hidden, className, type... are not text.
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

  // Disables style rules that would clash with Prettier. Must stay last.
  prettier,
);

// Shared Prettier configuration.
// Usage in each workspace:  export { default } from "@ceiba/config/prettier";
/** @type {import("prettier").Config} */
export default {
  printWidth: 100,
  singleQuote: false,
  trailingComma: "all",
  semi: true,
};

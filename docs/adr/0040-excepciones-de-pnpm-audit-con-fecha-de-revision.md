# ADR-0040: Excepciones de `pnpm audit` por aviso, con motivo y fecha de revisión obligatorios

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-18 |
| Origen | Fallo de `frontend-security` en `main` desde el 2026-11-17, que bloqueaba todos los PR. El desarrollador eligió esta opción el 2026-11-18 |

## Contexto

- `frontend-security` corre `pnpm audit --audit-level=high` y es un check obligatorio de `main`.
- [GHSA-fc5q-39xc-vjpf](https://github.com/advisories/GHSA-fc5q-39xc-vjpf) (high, ReDoS) afecta a `picomatch <=4.0.7`. La 4.0.7 es la última versión publicada y el aviso no tiene parche, así que ni un bump ni un override lo resuelven: las versiones vigentes de vite, vitest y tinyglobby siguen dependiendo de picomatch 4.
- El ataque exige controlar el patrón glob. En ceiba, picomatch llega por herramientas de desarrollo (vite, vitest, typescript-eslint); las configuraciones del repositorio no usan extglobs y las dependencias de producción de `panel` y `booking` no lo incluyen.
- `pnpm audit --prod` también lo reporta, porque `@ceiba/config` declara sus herramientas en `dependencies`.
- pnpm permite ignorar avisos, pero sin vencimiento: un ignorado olvidado sería permanente. El backend ya resolvió lo mismo para `bundler-audit` con `# revisar: AAAA-MM-DD | motivo: ...`.
- pnpm acepta ignorados desde varias fuentes (`audit.ignore`, la grafía antigua `auditConfig.ignoreGhsas`, variables de entorno, configuración global), así que validar solo un bloque del archivo dejaría pasar las demás.

## Decisión

Los avisos de `pnpm audit` se ignoran uno por uno en `audit.ignore` de `frontend/pnpm-workspace.yaml`, cada uno en su línea con `# revisar: AAAA-MM-DD | motivo: ...`. Antes del audit, `frontend/bin/ci-security` pasa la configuración efectiva (`pnpm config get audit --json`) a `packages/config/audit-ignores.mjs`: cada aviso que pnpm vaya a ignorar debe tener esa línea, con motivo y con una fecha válida y no vencida. Si no, o si la configuración no se puede leer, el check falla.

Se ignora GHSA-fc5q-39xc-vjpf con revisión el 2026-12-18. El nivel del audit y su alcance no cambian.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Ignorar el GHSA con fecha de revisión (elegida) | Excepción mínima; el audit sigue cubriendo todo lo demás; misma política que el backend | Hay que mantener un validador pequeño; el ignorado cubre cualquier ruta futura de ese aviso |
| `--prod` y mover las dependencias de `@ceiba/config` a `devDependencies` | Sin excepciones que mantener | CI deja de detectar avisos altos en todo el tooling, de forma permanente |
| `--ignore-unfixable` | Una sola bandera | Oculta cualquier aviso alto futuro sin parche, también en producción |
| Esperar el parche o usar un fork | No debilita el check | Mantiene bloqueados los PR sin fecha; un fork añade riesgo de cadena de suministro |

## Consecuencias

- **Positivas:** `main` y los PR se desbloquean sin apagar el check; cada excepción queda justificada y caduca.
- **Negativas / costos aceptados:** al vencer la fecha, `frontend-security` falla en todos los PR hasta revisar el aviso. Mientras dure el ignorado, este aviso no se reporta aunque aparezca por una ruta nueva. La fecha no tiene tope, igual que en el backend: la revisión del PR debe juzgar si es razonable. El control no cubre un `.pnpmfile.cjs` que cambie la configuración con `updateConfig`, porque `pnpm config get` no lo refleja: hoy no existe ninguno, y añadirlo exige un cambio de código revisado, igual que alterar `ci-security`.
- **Qué obliga a hacer:** revisar el aviso antes de la fecha; quitar la entrada en cuanto exista una versión corregida, o renovarla con un motivo actualizado.

## Cuándo revisarla

Al publicarse una versión corregida de picomatch, al llegar la fecha de revisión, o si picomatch entra en las dependencias de producción de `panel` o `booking`.

# ADR-0008: Permisos como datos, declarados por los módulos

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos; sustituye a `UserRole(user_id, role_id, scope_id)` de `plans/` |

## Contexto

El plan definía roles con alcance, pero las policies preguntarían por nombres de rol. Cada módulo nuevo obligaría a tocar todas las policies y los roles, y los roles personalizados (P3) exigirían reescribir la autorización. Además, `UserRole.scope_id` no tenía tipo ni integridad referencial.

## Decisión

- Los **manifiestos** de los módulos declaran sus permisos (`<modulo>.<recurso>.<accion>`).
- `roles` agrupa permisos (`role_permissions`); los roles de sistema son plantillas sembradas.
- `memberships(organization_id, user_id, role_id, company_id NULL, branch_id NULL, scope_level)` con FKs reales y un CHECK de coherencia.
- Las policies preguntan `principal.can?(permission_key, scope)`, **nunca** por un nombre de rol.

## Consecuencias

- **Positivas:** un módulo nuevo trae sus permisos sin tocar la plataforma; los roles personalizados son solo filas nuevas.
- **Negativas:** una consulta de permisos efectivos por request (memorizada).
- **Obliga a:** sincronizar permisos al desplegar; un linter que prohíba nombres de rol en las policies; la suite de matriz de autorización.

## Cuándo revisarla

No se prevé.

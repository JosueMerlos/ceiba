# Playbook: agregar un módulo nuevo

> Objetivo: que un módulo nuevo (p. ej. `loyalty`) se integre **declarándolo**, sin modificar `platform/`. Si algún paso exige tocar la plataforma, se justifica en un ADR: es una señal de que falta una capacidad o un punto de extensión.
> Referencias: [02](../architecture/02-modular-monolith.md), [05](../architecture/05-module-system.md), [06](../architecture/06-events-and-jobs.md), [04](../architecture/04-access-control.md).

## 0. Antes de escribir código

- [ ] ¿Es realmente un **módulo** (funcionalidad activable por empresa) y no configuración de uno existente ni una capacidad de plataforma? ([ADR-0011](../adr/0011-el-giro-no-es-un-modulo.md))
- [ ] Definir el `key` estable (snake_case, en inglés, **nunca** se renombra).
- [ ] Listar: qué eventos de otros módulos necesita, qué eventos publicará, qué capacidades de plataforma usa (clientes, notificaciones…).
- [ ] Si necesita datos de otro módulo de negocio: **solo por eventos**. Si necesita una respuesta síncrona de otro módulo, el diseño está mal o falta una capacidad de plataforma.
- [ ] ADR del módulo: propósito, límites y datos sensibles (¿requiere un consentimiento nuevo según la Ley 787?).
- [ ] Hitos en `docs/milestones/F<n>-<modulo>/` con la plantilla.

## 1. Esqueleto

```bash
bin/rails g pack modules/loyalty
```

Genera `package.yml` (capa `modules`, privacidad activa, dependencias en `platform/*`), `manifest.rb`, `config/locales/es-NI.yml` y specs base.

- [ ] `packwerk check` en verde con el pack vacío.

## 2. Manifiesto

- [ ] `name`, `version "1.0"`, `requires` (si depende de que otro módulo esté activo).
- [ ] **Permisos** `loyalty.<recurso>.<accion>` y `role_grants` por defecto para los roles de sistema.
- [ ] **Scopes de API** `read:loyalty` / `write:loyalty`.
- [ ] **Settings**: JSON Schema con `default` en cada propiedad y `settings_levels`.
- [ ] **Eventos** publicados (con su JSON Schema en `app/public/loyalty/events/`) y suscripciones.
- [ ] **Navegación** con el permiso requerido.
- [ ] Hooks `on_enable` (sembrar datos por defecto) y `on_disable` (detener envíos o jobs; **conservar** los datos).
- [ ] La spec del manifiesto pasa (el registro valida todo lo anterior).

## 3. Datos

- [ ] Migraciones en `packs/modules/loyalty/db/migrate` usando `create_tenant_table` y `tenant_reference` (FKs compuestas).
- [ ] Dinero en `*_minor` + `currency`; tiempos en `timestamptz`; PII cifrada si aplica.
- [ ] Invariantes críticas como restricciones de BD.
- [ ] Factories que derivan `organization_id` del padre. La **suite de aislamiento** las exige: si falta una, falla.

## 4. Dominio y API

- [ ] Casos de uso en servicios; transacción + `Events.publish` + `Audit.record` juntos.
- [ ] Controladores bajo `/api/v1/organizations/:organization_id/companies/:company_id/loyalty/...` con `RequiresModule(:loyalty)`.
- [ ] Policies en el pack que preguntan por **permisos**, nunca por roles.
- [ ] Specs de rswag por endpoint → regenerar OpenAPI y `api-client`.
- [ ] Errores con `code` estable (`loyalty.<error>`) y traducción en `es-NI`.

## 5. Suscriptores

- [ ] Uno por evento escuchado, en `app/subscribers/`, idempotente (lo garantiza `processed_events`; el efecto también debe ser seguro ante repetición).
- [ ] Spec: el mismo evento dos veces produce un solo efecto; con el módulo inactivo para la empresa, no se entrega.

## 6. Frontend

- [ ] `frontend/apps/panel/src/modules/loyalty/index.ts` con rutas lazy, navegación y permisos.
- [ ] Registrar en `modules/registry.ts`.
- [ ] Hooks sobre `packages/api-client`; componentes presentacionales con tests.
- [ ] Textos en i18n.

## 7. Matriz de autorización

- [ ] Añadir los permisos del módulo a la matriz de [04](../architecture/04-access-control.md) y a la tabla de casos de la suite de autorización.

## 8. Verificación final

- [ ] Las 6 suites de plataforma en verde (aislamiento, RLS, autorización, cobertura de módulos, contrato, eventos).
- [ ] Con el módulo **inactivo**: no aparece en `/me`, sus rutas dan `404` y no recibe eventos.
- [ ] Al **activarlo** en una empresa de seeds: `on_enable` deja datos por defecto coherentes.
- [ ] **Cero cambios en `packs/platform/`**, o un ADR que los justifique.
- [ ] Docs: ADR del módulo, `domain/<modulo>.md`, glosario actualizado.

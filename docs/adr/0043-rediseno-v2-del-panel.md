# ADR-0043: Rediseño v2 del panel: agenda en filas, catálogos en modal, paneles flotantes y componentes propios de fecha y hora

| Campo | Valor |
| --- | --- |
| Estado | aceptada (enmienda el ítem 4 de [ADR-0032](0032-lenguaje-visual-marco-y-hoja.md) y la excepción de PII de [ADR-0033](0033-autorizacion-y-pii-de-clientes-y-servicios.md)) |
| Fecha | 2026-11-24 |
| Origen | Pruebas del panel con datos reales tras cerrar M2.01–M2.04; prototipos aprobados por el desarrollador el 2026-11-24 en el lienzo de diseño, página [«Rediseño v2»](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#page-rediseno); decisiones cerradas del desarrollador del mismo día |

## Contexto

Al cargar el panel con datos de un negocio real aparecieron siete problemas:

1. **La agenda con profesionales en columnas no escala.** Con más de 5–6 profesionales las columnas se estrechan, la página no tiene scroll propio, la información de la cita se pierde y el encabezado salta de línea con nombres largos. [ADR-0032](0032-lenguaje-visual-marco-y-hoja.md) ya pedía revisar si una sucursal pasaba de 8 profesionales.
2. **Los formularios de catálogo viven en el panel lateral derecho** (ítem 4 de ADR-0032): poco ancho y, en el profesional, hasta cuatro botones de guardar (perfil, servicios, sucursales, horario).
3. **Horarios y fechas con inputs nativos** (`type="time"`, `type="date"`, `datetime-local` en `weekly-schedule-editor.tsx`, `slot-fields.tsx` y `time-off-form.tsx`): formato `dd/mm/aaaa`, selector azul del navegador ajeno a la marca, y un horario de sucursal que desperdicia espacio.
4. **La ficha del cliente se ve vacía** y su historial mezcla citas futuras y pasadas.
5. **El selector de sucursal está duplicado:** además del selector global (que ya ofrece «Todas las sucursales», `context-selector.tsx`), Servicios y Recursos tienen su propio «Sucursal de trabajo» (`BranchPicker` y dos hooks `useWorkingBranch`, uno en `platform/context` y otro en `modules/appointments/lib`). Con «Todas» se muestran servicios sin decir de qué sucursal son los valores.
6. **La recepción ve ayudas de edición** que no le aplican: su acceso a los catálogos es de solo lectura.
7. **Desbordes:** scroll innecesario en la pantalla de Marca y el horario de recursos y profesionales se sale del panel lateral.

Restricciones que condicionan la solución:

- El presupuesto de JS crítico del panel es de **220 KiB** gzip y hoy se miden **198.5 KiB** ([08-frontend](../architecture/08-frontend.md#presupuesto-de-bundle-y-e2e)): quedan ~21 KiB de holgura.
- `@event-calendar/core` 5.19.0 ya está instalado detrás de `AgendaView` ([ADR-0014](0014-calendario-gratuito-con-adaptador.md)); el contrato `AgendaViewProps` es estable y aísla la librería.
- `radix-ui` 1.8.1 (paraguas, con `Popover` y `Tabs`) ya está en `packages/ui`.
- La tabla `professionals` no tiene teléfono ni correo y `services` no tiene categoría (`backend/db/structure.sql`). Los overrides de servicio solo se leen por sucursal (`GET …/branches/:branch_id/service_overrides`). El historial del cliente vive en el pack de citas (`CustomerAppointmentsController`) porque `platform` no puede depender de `modules`.

## Decisión

Rediseñamos el panel con cinco principios y un conjunto de elecciones concretas, repartidas en los hitos [M2.05](../milestones/F2-agenda-interna/M2.05-base-de-componentes.md), [M2.06](../milestones/F2-agenda-interna/M2.06-agenda-en-filas.md), [M2.07](../milestones/F2-agenda-interna/M2.07-catalogos-en-modal.md) y [M2.08](../milestones/F2-agenda-interna/M2.08-horarios-ficha-de-cliente-y-variacion-por-sucursal.md).

**Principios**

1. **Los paneles laterales flotan** sobre el contenido (no le roban ancho) y no son modales.
2. **Crear y editar catálogos se hace en un modal central** con **un solo botón de guardar visible**.
3. **Lo que el rol no puede cambiar se muestra como lectura limpia:** sin botones de crear, sin acciones por fila, sin ayudas de edición.
4. **La sucursal se elige solo en el selector global.**
5. **Todo con los tokens actuales de `@ceiba/ui`** ([ADR-0031](0031-tokens-de-diseno-en-tres-capas.md)); la marca de cada empresa recolorea el primario ([ADR-0025](0025-branding-en-companies.md)).

**Elecciones concretas**

1. **Alto fijo con scroll interno.** El `AppLayout` ocupa exactamente la ventana (`h-svh`); el marco y la barra lateral quedan estáticos y cada pantalla desplaza solo su cuerpo. La agenda, las tablas y el cuerpo de los modales tienen su propio scroll.
2. **Agenda en filas** con el plugin `ResourceTimeline` de `@event-calendar/core` 5.19.0 (vista `resourceTimelineDay`, `slotWidth`): profesionales (o recursos) en filas, horas en columnas. Tarjetas en tres niveles según su ancho (nombre + servicio / nombre / iniciales con tooltip), densidad cómoda y compacta, chips de estado que son leyenda **y** filtro, línea de «ahora» vertical en `--destructive` con etiqueta en el encabezado, título corto de fecha que abre el calendario. La vista Semana muestra **un profesional a la vez** (días en columnas, como hoy) con selector de profesional. En el celular la agenda es una lista por profesional (chips de profesional + «Todos», huecos libres tocables, botón flotante «Nueva cita»). Todo detrás del mismo `AgendaViewProps`.
3. **Paneles flotantes:** «Próximas llegadas» y el detalle de la cita son paneles flotantes sobre la agenda; el detalle rápido de un elemento de catálogo para la recepción también.
4. **Modal con pasos o pestañas.** Crear = pasos (profesional: Perfil → Servicios → Sucursal y horario → Ausencias; el paso 1 crea el registro y los siguientes se pueden omitir). Editar = pestañas, con un solo «Guardar cambios» por pestaña. Cliente y Servicio tienen un paso; Recurso, dos (datos y horario). Listas largas de servicios: grupos plegables por categoría, contador «x de N», seleccionar o quitar todos por grupo, filtro «Solo seleccionados» y búsqueda fija, **sin paginación** y con scroll dentro del cuerpo del modal.
5. **Fecha con `react-day-picker`** (el `Calendar` de shadcn/ui), versión exacta fijada y **cargado de forma diferida** (no se exporta estáticamente desde el barrel crítico de `@ceiba/ui`). Es la única dependencia nueva del rediseño.
6. **Hora, franja y duración hechas a mano sobre Radix `Popover`:** `TimeField` (lista cada 15 min en la que también se puede escribir), rango compacto y `DurationField` (−/+ y atajos). Desaparecen todos los inputs nativos de fecha y hora del panel.
7. **Un solo formato de hora en todo el panel: «9:00 a. m.»** (12 h, locale `es-NI`), y fechas como «lun 14 dic 2026». Un único helper en `@ceiba/i18n` reemplaza las tres rutas actuales (`formats.ts`, `agenda-time.ts`, `zoned-time.ts`).
8. **Selector de sucursal global único:** se eliminan `BranchPicker` y los `useWorkingBranch` por pantalla. Con «Todas las sucursales», los servicios muestran los valores base de la empresa y la etiqueta «varía en N sucursales», que abre un modal con la tabla por sucursal (valor propio resaltado, base tachado). La recepción ve ese modal en solo lectura.
9. **Recepción en solo lectura** en los catálogos (principio 3).
10. **Editor de horarios en bloques**, reutilizable para sucursal, profesional y recurso: días en filas y de 6 a. m. a 9 p. m. en columnas, modo lectura por defecto, edición arrastrando bordes o arrastrando en vacío para crear, clic en un bloque abre un popover Desde/Hasta/Quitar, barra fija «Guardar horario» y «Copiar día a…». Se construye sobre el mismo `ResourceTimeline` (días de la semana como recursos, `selectable`/`editable`) **tras un spike de 1–2 h**; **plan B:** bloques solo editables por popover, sin arrastre.
11. **Ficha de cliente compacta:** contacto en chips en el encabezado, franja de cifras (citas, asistió x de y, no asistió, última visita), pestañas Próximas/Pasadas agrupadas por mes; un cliente nuevo tiene la misma estructura con estados vacíos. Solo se **muestra** el estado del consentimiento: los botones para registrarlo y la lista «Completar la ficha» son de [M3.01](../milestones/F3-reserva-publica/M3.01-notificaciones-y-consentimiento.md).
12. **Cifras del cliente por sucursal** en un endpoint nuevo del pack de citas, junto a `CustomerAppointmentsController`, con el mismo alcance y la misma política que el historial (`AppointmentPolicy#customer_history?`): no cambia la autorización. «Asistió» = `completed` + `checked_in`. Se calculan con un solo `COUNT … FILTER` sobre el índice existente `idx_appointments_customer`.
13. **Overrides de toda la empresa en una llamada:** endpoint nuevo (sin publicar) de empresa que devuelve los overrides por sucursal de todos los servicios, para el modal «varía en N sucursales». No amplía el acceso: cada principal recibe solo los de las sucursales donde ya puede leerlos (véase la decisión delegada en M2.08).
14. **`services.category`:** columna nueva, opcional, de texto libre, con sugerencias tomadas de las categorías existentes, editable en el modal de servicio. Habilita los grupos plegables y el filtro por categoría.
15. **Teléfono y correo del profesional:** columnas nuevas, opcionales, cifradas como las del cliente. Se rigen por la enmienda a ADR-0033 de abajo.

**Enmiendas**

- **[ADR-0032](0032-lenguaje-visual-marco-y-hoja.md), ítem 4.** El panel contextual a la derecha deja de ser el único patrón y deja de estar acoplado: **flota** sobre la hoja sin robarle ancho, sigue siendo no modal y colapsable con un botón visible. Los catálogos ya no se editan en él sino en un **modal central** con pasos o pestañas. La pantalla de Marca conserva el panel acoplado, porque es un editor con vista previa en vivo que necesita ver ambos a la vez.
- **[ADR-0033](0033-autorizacion-y-pii-de-clientes-y-servicios.md), excepción de PII.** El teléfono y el correo del **profesional** son PII fuera del recurso cliente. Solo los lee quien tiene `appointments.professional.manage` (hoy el `company_manager`, [ADR-0034](0034-horarios-ausencias-y-permisos-de-profesionales-y-recursos.md)), y **solo** en el detalle de empresa (`GET …/professionals/:professional_id`) y en las respuestas de sus propias escrituras. Nunca en el listado, en el perfil visto desde la sucursal (`show_in_branch`), en la reserva pública, en logs, en eventos ni en la auditoría, que es por id y nombre de campo, nunca por valor. Para cualquier otro principal el campo es `null`. Ya están cubiertos por `filter_parameters` (`:phone`, `:email`), lo que un spec fija.

Prototipos por tablero: [R-Agenda](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Agenda) · [R-Agenda-Semana](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Agenda-Semana) · [R-Agenda-Movil](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Agenda-Movil) · [R-Profesional-Modal](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Profesional-Modal) · [R-Horario](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Horario) · [R-Componentes](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Componentes) · [R-Cliente](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Cliente) · [R-Cliente-Nuevo](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Cliente-Nuevo) · [R-Catalogo](https://claude.ai/artifact/WtdEAxnNRBqKiYPFLY2P4N#artboard-R-Catalogo).

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| **Agenda en filas con `ResourceTimeline` de la librería ya instalada** | Escala a 15+ profesionales con scroll vertical; sin dependencias nuevas; el adaptador ya aísla la librería | Cambian las tarjetas, el encabezado y los E2E de la agenda; hay que confirmar el plugin en 5.19.0. **Elegida** |
| Mantener columnas con scroll horizontal | Sin cambios de vista | Sigue sin leerse el nombre del cliente; el scroll en dos ejes es incómodo en la recepción |
| Grilla CSS propia (plan B de ADR-0014) | Control total | Rehace arrastre, selección y zonas horarias que la librería ya resuelve |
| **Modal central con pasos/pestañas para catálogos** | Ancho suficiente; un solo botón de guardar; flujo guiado al crear | Tapa la lista mientras se edita. **Elegida** |
| Seguir en el panel lateral, más ancho | Menos cambio | Le roba aún más ancho a la tabla y no resuelve los cuatro botones de guardar |
| Página propia por elemento | Todo el espacio | Pierde el contexto de la lista y suma rutas |
| **`react-day-picker` diferido para la fecha + hora/duración propias sobre Radix** | Es el `Calendar` de shadcn/ui; la hora y la duración son simples y no justifican otra dependencia | Una dependencia nueva y componentes propios que mantener. **Elegida** |
| Inputs nativos con estilos | Sin dependencias | No se pueden estilizar el selector ni el formato de forma consistente entre navegadores |
| Librería completa de fecha y hora (p. ej. un date-time picker) | Todo hecho | Más peso que la holgura de ~21 KiB y otra API que aprender |
| **Editor de horarios sobre `ResourceTimeline`, con spike y plan B** | Reutiliza la librería y la interacción de la agenda | Depende de que `selectable`/`editable` sirvan para días como recursos. **Elegida** |
| Editor de bloques propio con eventos de puntero | Sin depender de la librería | Más código y más pruebas para arrastrar y redimensionar |
| **Endpoint de empresa para los overrides** | Una llamada en lugar de N; sin ampliar el acceso | Un endpoint más. **Elegida** |
| N llamadas a `branches/:id/service_overrides` | Sin cambios de API | N peticiones por carga con «Todas las sucursales» |
| **Columna `services.category`** | Agrupa y filtra servicios de forma real | Cambio de esquema de una tabla existente (aprobado). **Elegida** |
| Agrupar por prefijo del nombre o sin grupos | Sin migración | Frágil o inútil con 50+ servicios |
| **Teléfono y correo del profesional solo en el detalle, para quien gestiona** | Minimiza la exposición de PII nueva | Recepción no puede llamar a un profesional desde el panel. **Elegida** |
| Visibles a todo el staff de la sucursal | Más práctico | Expone PII a roles que no la necesitan; contradice la minimización de ADR-0033 |

## Consecuencias

- **Positivas:** la agenda se lee con 15+ profesionales; un solo botón de guardar por paso o pestaña; ningún input nativo de fecha u hora; un solo formato de hora; un solo selector de sucursal; la recepción ve una interfaz que no le promete acciones que no tiene; la ficha del cliente resume su relación con el negocio; los paneles ya no estrechan la pantalla.
- **Negativas / costos aceptados:** una dependencia nueva (`react-day-picker`); componentes de hora y duración propios que mantener; dos columnas nuevas en tablas existentes y un dato personal nuevo (el contacto del profesional) con su excepción escrita; dos endpoints nuevos; cambian las capturas y buena parte de los E2E del panel; el alto fijo obliga a revisar el scroll de todas las pantallas.
- **Qué obliga a hacer:**
  - `bin/ci-bundle` sigue en ≤ 220 KiB de JS crítico; `react-day-picker`, la vista de timeline y los modales de catálogo van en chunks diferidos. Se mide al cerrar M2.05 y M2.06 y se anota en [08-frontend](../architecture/08-frontend.md#presupuesto-de-bundle-y-e2e).
  - Una regla de lint o un test impide volver a usar `type="time"`, `type="date"` o `datetime-local` en `apps/panel` y `packages/ui`.
  - Un test fija el texto exacto «9:00 a. m.» y «lun 14 dic 2026» del helper único (normalizando los espacios que inserta ICU).
  - Specs de autorización por rol para el contacto del profesional (`null` para quien no tiene `appointments.professional.manage`; ausente del listado y de `show_in_branch`), para las cifras del cliente (mismo resultado que `customer_history?`) y para el endpoint de overrides de empresa (solo las sucursales legibles). `bin/api-generate` tras cada cambio de contrato.
  - Migraciones aditivas (columnas `NULL`) según [rails.md](../harness/rails.md) y [seguridad.md](../harness/seguridad.md), con `structure.sql` y los roles `app_owner`/`app_user`.
  - `packwerk check` en verde: las cifras del cliente viven en `modules/appointments`.
  - [08-frontend](../architecture/08-frontend.md) describe el panel flotante, el modal de catálogo, el alto fijo y los componentes de fecha y hora.

## Cuándo revisarla

- Si `ResourceTimeline` no cumple en el spike de M2.06 (la agenda en filas pasa a una grilla propia y se escribe otro ADR) o en el de M2.08 (el editor de horarios queda en el plan B).
- Si el JS crítico del panel supera los 220 KiB por este rediseño.
- Si la recepción necesita el contacto del profesional, o si el profesional necesita ver o editar su propio teléfono y correo.
- Si los pilotos de F4 reportan que el modal tapa información que necesitan ver mientras editan.

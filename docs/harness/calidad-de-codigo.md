# Reglas de calidad de código para agentes

> Adaptado de `ticket-harness/core/rules/code-quality.md`. Las reglas de capas y packs están en
> [`02-modular-monolith`](../architecture/02-modular-monolith.md); las de datos en
> [`09-data-conventions`](../architecture/09-data-conventions.md).

## Disciplina de alcance

- Completa el resultado pedido y su verificación. No conviertas una tarea acotada en una campaña de refactor, cobertura,
  rendimiento o documentación. Un hallazgo fuera de alcance se reporta, no se arregla de paso.
- Lee el dueño, los llamadores y los tests relevantes antes de editar. Haz el cambio completo más pequeño.
- Sin abstracciones especulativas, envoltorios que solo reenvían ni limpieza no relacionada. Los límites de complejidad son
  para quitar complejidad accidental, no para partir el código en helpers que solo reenvían llamadas.
- Sigue los patrones, nombres y capas del código vecino y del pack dueño. Usa los mecanismos existentes (serializers de Alba,
  `problem+json`, paginación por cursor, policies de Pundit, outbox, `Tenancy.with_context`) en vez de inventar una capa.
- Los controladores se limitan a transporte y autorización; las capas inferiores no dependen de request, sesión ni controlador.
- Un pack solo usa la API pública (`app/public`) de otro pack; Packwerk lo verifica.

## Barrido de llamadas (al cambiar algo que ya existe)

Una operación lógica suele tener varias puertas: panel, booking, endpoints de la API, jobs, seeds, consola, el cliente TS generado.
Un cambio que cubre una sola puerta deja rotas las demás. Antes de cambiar un campo, parámetro, método, endpoint o columna:

1. Busca en cada superficie con cada grafía (`snake_case`, `camelCase` del cliente TS, claves string, nombres en OpenAPI).
2. Clasifica cada hallazgo como productor (construye o envía el dato) o consumidor (lo lee, persiste o serializa).
3. Reporta la cobertura como "N de M sitios cubiertos" y justifica cada sitio que quede fuera. Nunca dejes sin mencionar un
   sitio descubierto.

Se omite solo en código 100 % nuevo sin consumidores previos.

## Comentarios

- Un comentario se queda solo si justifica una decisión: por qué X y no Y, por qué existe una guarda, una rareza externa, un
  invariante no obvio, una trampa de concurrencia o de zona horaria.
- Una línea si se puede, dos como mucho; más solo para documentar la cabecera de una clase o script como ya hace el código de
  ceiba. Nunca un bloque que narre el código.
- Borra los comentarios que repiten el código, narran el cambio o el proceso ("añadido por la revisión", "antes era X"),
  separan secciones o son TODOs genéricos.
- Desempate: si al borrarlo un revisor preguntaría "¿por qué está así?", se queda; si solo parafrasea el código, se va.
- **En inglés**, siempre (los nuevos y los que modifiques). Los comentarios en español heredados se migran en una pasada de
  limpieza dedicada: no traduzcas los de líneas que no tocas. Puede citar un ADR o un hito si el comentario se entiende sin
  abrirlo.
- Los comentarios de los tests siguen la misma regla y no repiten los del código de producción.

## Autocorrect y codemods

Los formateadores y autocorrectores (`rubocop -A`, `prettier --write`, `eslint --fix`, `bin/api-generate`, el volcado de
`structure.sql`) actúan sobre el archivo o el repo entero, no sobre tus líneas.

- Tras correr uno, revisa el diff y revierte cada bloque que no sea tuyo.
- Prefiere corridas acotadas (una regla, un archivo nuevo). Corrige ofensas en código existente solo dentro de tus líneas.
- Un generador que toca archivos generados ajenos: conserva solo el cambio buscado, revierte el ruido.

## Errores, datos y secretos en el código

- Los textos visibles para el usuario pasan por i18n (Rails I18n en backend; `packages/i18n` en frontend, también en `aria-*`,
  regla de ESLint). La PII y los campos cifrados quedan fuera de respuestas, logs, auditoría y mensajes de error.
- Las cargas externas usan identificadores seguros (UUIDv7, slug o token firmado), nunca ids secuenciales.
- Nunca credenciales en el código; se leen de variables de entorno que el proceso ya tiene y se falla nombrando la clave que
  falta (ver [`seguridad.md`](seguridad.md)).

## Eliminar código

Cuando algo se elimina, se borra por completo (código, tests, docs, config, entradas del manifiesto de módulos) y no se
agrega nada en su lugar. Ver [`testing.md`](testing.md#las-eliminaciones-son-borrados).

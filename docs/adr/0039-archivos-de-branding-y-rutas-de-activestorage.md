# ADR-0039: Archivos de branding: subida por el PATCH autenticado y solo el proxy GET de variantes bajo `/api/storage`

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-17 |
| Origen | M2.04 (branding por empresa), decisiones 1 y 2 del desarrollador y revisión independiente del plan |

## Contexto

[ADR-0025](0025-branding-en-companies.md) fija el modelo: columnas en `companies` y logo, banner y favicon como adjuntos de
Active Storage, sin SVG. Faltaba decidir cómo entran y cómo salen los archivos:

- Rails en modo API con `config.active_storage.draw_routes = false` (M0.07): las rutas de Active Storage no pasan por
  `Api::BaseController`, así que las subidas directas habrían quedado abiertas sin sesión. Con las rutas apagadas desaparecen
  también los helpers `direct`/`resolve` que las acompañan.
- Los logos son públicos (la página `/c/:slug` los muestra a anónimos): la lectura no puede exigir sesión.
- `ApiRequestGuard` exige `application/json` en toda mutación; un archivo no viaja en JSON.
- Caddy solo envía `/api/*` a Rails; `/rails/active_storage/*` iría al panel.
- ActiveStorage encola trabajos (`AnalyzeJob`, `PurgeJob`, `TransformJob`) directo a Sidekiq, saltándose el outbox. Y toda
  petición de la API corre dentro de una transacción (`Tenancy.with_context`).

## Decisión

1. **Subida solo por `PATCH /api/v1/organizations/:o/companies/:c/branding`**, autenticado, con `platform.branding.update` y
   `multipart/form-data` (o JSON si solo cambian textos). No hay subidas directas ni `PUT` del disco.
2. **Excepción estrecha en `ApiRequestGuard`:** `multipart/form-data` se acepta únicamente en `PATCH` de esa ruta (UUIDs de
   organización y empresa); en cualquier otro método, ruta o tipo sigue el `415`, y la query string sigue prohibida. No debilita
   la barrera cross-site de [11](../architecture/11-security.md): un formulario HTML de otro sitio solo puede enviar `GET` o
   `POST`, nunca `PATCH`, y un `fetch` `PATCH` cross-origin exige un preflight que la API no concede; siguen vigentes Origin,
   `SameSite` y el token CSRF.
3. **Solo se sirve la variante, nunca el original.** La única ruta de Active Storage es
   `GET /api/storage/representations/proxy/:signed_blob_id/:variation_key/*filename` (helper
   `rails_blob_representation_proxy`), dibujada a mano. No existe ruta para el blob original: el archivo subido no tiene URL.
   Las variantes se re-codifican con libvips (WebP el logo y el banner, PNG el favicon; metadatos fuera) y se **renderizan al
   guardar**. El controlador (`Tenancy::Storage::RepresentationsController`) responde `404` si la variante no existe: un `GET`
   anónimo nunca ejecuta vips ni escribe. Una transformación que el servidor no firmó tampoco se puede pedir (su clave no pasa
   la verificación de firma). La ruta está limitada por IP en Rack::Attack (300 por minuto).
4. **Validación por contenido real** (`Tenancy::BrandingFile`): el tipo sale de los bytes mágicos (nunca del nombre ni del tipo
   declarado), solo PNG, JPEG y WebP; tamaño (logo 2 MB, banner 5 MB, favicon 200 KB) y dimensiones (4096 px por lado, leídas
   de la cabecera antes de decodificar, defensa contra bombas de descompresión). Se almacena el tipo detectado
   (`identify: false`). Un SVG renombrado a `.png` se rechaza.
5. **Tablas de Active Storage globales** (sin `organization_id`, como `users` y `sessions`), con PK y `record_id` `uuid`. El
   aislamiento lo da el registro dueño (`companies`, tabla tenant) y la firma de los ids. La migración vive en el pack
   `tenancy`.
6. **Sin trabajos de Active Storage:** `analyzers = []`, adjuntos con `dependent: false`, blobs con `analyzed` preestablecido,
   variantes renderizadas por el caso de uso justo después del commit de la transacción más externa y blobs reemplazados purgados
   en ese mismo momento (`ActiveRecord.after_all_transactions_commit`), de forma síncrona. Un rollback no deja variantes ni
   purgas. Un spec comprueba que nada se encola.
7. **URLs versionadas y revalidación:** un archivo nuevo es un blob nuevo, así que sus URLs cambian; el proxy responde con
   `Cache-Control: public, max-age=…, immutable`. El endpoint público de marca (`GET /api/public/v1/c/:slug/branding`)
   responde `Cache-Control: public, no-cache` con `ETag` (versión de la empresa y blobs adjuntos): el navegador siempre
   revalida (un `304` barato) y nunca muestra una marca vieja tras un cambio.
8. **Almacenamiento:** `local` por defecto; `ACTIVE_STORAGE_SERVICE=r2` activa el servicio S3-compatible de `storage.yml`
   (gem `aws-sdk-s3`, claves por `ENV.fetch`, que falla nombrando la que falte).

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| A. PATCH multipart autenticado + solo el proxy GET de variantes (elegida) | Superficie mínima: nada anónimo escribe; URL estable por blob; pasa por Caddy `/api/*` | Los archivos atraviesan Rails (hasta 5 MB); en producción conviene un CDN delante |
| B. Reactivar todas las rutas de Active Storage con un envoltorio autenticado para subidas directas | Menos carga en Rails | Más superficie y autenticación propia sobre controladores de Rails; poco beneficio con archivos ≤ 5 MB |
| C. Modo redirect (URLs firmadas que expiran) | Rails no transmite bytes | La URL cambia en cada respuesta: rompe la caché y el JSON público |
| D. Procesar variantes bajo demanda | Menos trabajo al guardar | Un `GET` anónimo ejecutaría vips y escribiría; superficie de denegación de servicio |
| E. Variantes y purgas con jobs de Active Storage | Estándar de Rails | Encolan en Sidekiq fuera del outbox; salen del control de la transacción |

## Consecuencias

- **Positivas:** una sola vía de escritura, auditada; el original nunca sale; la marca nueva se ve sin limpiar la caché.
- **Negativas / costos aceptados:** guardar procesa seis variantes en la petición (imágenes pequeñas, validadas antes); un fallo
  de vips tras el commit deja el cambio guardado con la petición en error; el `multipart` rompe la regla "todo es JSON" en un
  punto, acotado y probado.
- **Qué obliga a hacer:** el spec de `authentication_spec` solo admite el `GET` del proxy como ruta de Active Storage; todo
  código que adjunte un archivo a un modelo debe precargar `analyzed` en el blob (si no, Active Storage encola un análisis); el
  contrato OpenAPI documenta el `PATCH` multipart pero no el proxy (no es JSON).

## Cuándo revisarla

Si los archivos de branding crecen (más tipos, vídeo, tamaños mayores) o la subida pasa por Rails con carga relevante: valorar
subidas directas autenticadas y un CDN; si aparecen otros adjuntos en la plataforma, generalizar la regla de la excepción.

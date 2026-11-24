# ADR-0042: Importación de clientes, servicios y profesionales desde CSV

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-23 |
| Origen | Hito [M2.03](../milestones/F2-agenda-interna/M2.03-clientes-e-importacion-csv.md); decisiones del desarrollador del 2026-11-18 (D1–D4) y del 2026-11-23 (D5–D11) |

## Contexto

Un negocio que llega a Ceiba trae su lista de clientes, servicios y profesionales en una hoja de cálculo, casi siempre Excel
en español: Windows-1252, separador `;`, fin de línea CRLF, teléfonos que Excel convierte en notación científica. Cargarla
a mano es la principal barrera de adopción. La importación toca datos personales (teléfono, correo, notas), escribe en
bloque en tablas de tenant y puede sobreescribir registros existentes, así que su forma necesita decisiones explícitas de
privacidad, autorización y tenancy.

## Decisión

1. **Un pack de plataforma, `platform/imports`, con importadores registrados por los packs dueños de los datos.** El pack
   lee el archivo, guarda la previsualización y aplica las filas; cada tipo (`customers`, `services`, `professionals`)
   registra su importador y su política en `Imports::Registry`. Servicios y profesionales exigen el módulo de citas activo.
2. **Flujo en dos pasos: previsualizar y confirmar.** El job aplica las filas a nombre de quien confirmó (`confirmed_by_id`),
   que puede no ser quien subió el archivo. El `POST` lee el archivo (UTF-8, UTF-16 o Windows-1252 por BOM o
   detección; separador `;`, `,` o tabulador; máximo 5000 filas y 5 MB), valida cada fila sin aplicar ninguna y devuelve el
   lote `previewed` con las 20 primeras filas. Confirmar encola el lote: un job lo aplica en tramos de 200 filas, cada uno
   en su transacción y encadenado por eventos del outbox. Un solo lote de cada tipo corre a la vez en la empresa (índice
   único parcial). El archivo viaja en base64 dentro del JSON, porque las mutaciones solo aceptan `application/json`
   (decisión delegada).
3. **Consentimiento (D1).** La importación no registra consentimiento para recordatorios: todos los clientes entran sin él.
   Si el archivo trae una columna de consentimiento, la previsualización avisa (`consent_not_recorded`). M3.01 añade la
   columna con su fuente.
4. **Permiso propio (D2).** Importar clientes exige `platform.customer.import` (company_manager y branch_manager) además de
   `platform.customer.read`, en la sucursal desde la que se actúa. Servicios y profesionales piden
   `appointments.service.manage` y `appointments.professional.manage` en la empresa.
5. **Retención de datos personales (D3).** Las celdas de cada fila se guardan cifradas (`encrypts :payload`) y se borran al
   aplicar la fila y al terminar el lote. Un lote sin confirmar vence a las 24 h y una purga horaria lo marca `expired`, borra sus filas y conserva sus
   conteos; un lote atascado más de 24 h se marca `failed` y borra su contenido. Cada lote se purga en su propio job y
   transacción, con el lote bloqueado y su estado comprobado de nuevo. Un error inesperado de la base al aplicar una fila
   la deja `failed` con un código genérico, sin guardar ni propagar el mensaje (puede citar los valores). El reporte final conserva solo
   número de fila y códigos de error, nunca el valor. El parámetro `content_base64` está en `filter_parameters`.
6. **Dinero (D4).** El precio acepta `150`, `150.50` y `150,50`; un separador de miles se rechaza en vez de adivinarse.
   Moneda vacía es la de la empresa; otra moneda es un error.
7. **Excepción de PII de ADR-0033 ampliada (D5).** Los endpoints de importación devuelven los valores de las filas solo
   mientras el lote está `previewed` y no ha vencido, y solo a quien tiene `platform.customer.import` y
   `platform.customer.read`. Tras
   confirmar, lote y filas salen sin valores.
8. **Purga entre organizaciones (D6).** `Imports::CrossTenant` solo lee qué organizaciones tienen lotes vencidos o atascados
   (entrada en `AllowedFiles` de `Ceiba/TenantBypass`); un cron sin tenant encola un job por lote, que purga dentro del
   tenant de su organización.
9. **Historial por sucursal (D7).** La ficha del cliente muestra solo las citas de la sucursal activa, y lo dice.
10. **Duplicados (D8, D9).** Clientes se identifican por teléfono normalizado. `skip` no toca a los existentes ni a los
    archivados y los reporta como omitidos; `update` escribe las celdas no vacías y restaura a los archivados. Servicios y
    profesionales solo admiten `skip`, por nombre normalizado entre los no archivados. Un duplicado dentro del archivo se
    rechaza.
11. **Gema `csv` 3.3.2 declarada (D10)**, porque desde Ruby 3.4 no es una gema por defecto.
12. **Inserción en bloque de la previsualización (D11).** `Imports::CreateBatch` inserta las filas con `insert_all!` en
    bloques de 1000 y `organization_id` explícito; el archivo está en `AllowedFiles` de `Ceiba/TenantBypass`.
    `Tenancy::TenantWriteGuard` sigue siendo el control en ejecución: rechaza cualquier fila cuyo tenant no sea el activo.
    Medido en test: 5000 filas fila a fila, 8,5 s; en bloque, 0,9 s.
13. **Plantillas en el repo.** `frontend/apps/panel/public/import-templates/{clientes,servicios,profesionales}.csv`, en
    UTF-8 con BOM y `;`. El contrato publica las columnas de cada tipo (`x-template-columns` en `ImportUpload`, generado
    desde los importadores) y un test del panel comprueba que cada plantilla trae exactamente esas columnas.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Subida `multipart/form-data` | Sin el 33 % de base64 | Abrir otro tipo de contenido en las mutaciones es una decisión de seguridad aparte |
| Aplicar todo en un solo job y transacción | Más simple | Una transacción de 5000 filas bloquea y, si falla, no deja progreso visible |
| Analizar el archivo en un job (`analyzing`) | Petición corta | Guarda el archivo completo cifrado más tiempo y añade otro estado y otro sondeo |
| Inserción fila a fila sin `AllowedFiles` | Sin ruta privilegiada nueva | 8,5 s dentro de la petición con 5000 filas |
| Registrar el consentimiento del archivo | El cliente llega completo | Sin evidencia de cómo se obtuvo; lo decide M3.01 |

## Consecuencias

- **Positivas:** un negocio carga su lista en minutos; cada error se ve con su fila y su motivo antes de escribir nada;
  los datos personales del archivo no sobreviven al lote.
- **Negativas / costos aceptados:** dos rutas privilegiadas más en `AllowedFiles` (lectura entre organizaciones de la purga
  e inserción en bloque); los clientes importados no tienen consentimiento hasta M3.01; el formato real de Excel se probó
  con un fixture equivalente en bytes, no con un archivo exportado por Excel.
- **Qué obliga a hacer:** todo importador nuevo se registra en `Imports::Registry`, declara sus columnas y su política, y
  añade su plantilla; los specs de tenancy cubren las tablas `import_batches` e `import_rows`; las dos rutas privilegiadas
  quedan en el alcance de `judgment-day`.

## Cuándo revisarla

Si hacen falta archivos de más de 5000 filas o 5 MB, otros formatos (XLSX), importar citas, o si M3.01 define cómo se
registra el consentimiento importado.

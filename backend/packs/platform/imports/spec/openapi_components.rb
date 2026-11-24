# OpenAPI schemas of the imports pack.
OpenapiComponents.register(
  ImportUpload: {
    type: :object,
    description: "Archivo CSV a importar, codificado en base64",
    properties: {
      kind: { type: :string, enum: %w[customers services professionals] },
      content_base64: { type: :string, description: "Bytes del archivo en base64 (máximo 5 MB decodificado)" }
    },
    required: %i[kind content_base64],
    additionalProperties: false,
    # The columns each kind reads, from the registered importers: the panel's downloadable templates are checked against it.
    "x-template-columns": Imports::Registry.entries.transform_values { it.importer_class::COLUMNS.keys }
  },
  ImportConfirmation: {
    type: :object,
    properties: { duplicate_mode: { type: :string, enum: %w[skip update], description: "`update` solo para clientes" } },
    required: %i[duplicate_mode],
    additionalProperties: false
  },
  ImportRow: {
    type: :object,
    description: "Una fila de datos del archivo. `row_number` es su línea en la hoja (el encabezado es la 1).",
    properties: {
      row_number: { type: :integer, minimum: 2 },
      status: { type: :string, enum: %w[ready rejected created updated restored skipped failed] },
      error_codes: { type: :object, additionalProperties: { type: :string }, description: "Columna => código del error, nunca el valor" },
      values: { type: :object, nullable: true, additionalProperties: { type: :string, nullable: true },
                description: "Celdas de la fila por columna; solo mientras el lote está en previsualización y no ha vencido" }
    },
    required: %i[row_number status error_codes values],
    additionalProperties: false
  },
  ImportBatch: {
    type: :object,
    description: "Un archivo importado, de la previsualización al reporte. Solo conteos y códigos.",
    properties: {
      id: { type: :string, format: :uuid },
      kind: { type: :string, enum: %w[customers services professionals] },
      status: { type: :string, enum: %w[previewed queued processing completed failed expired] },
      duplicate_mode: { type: :string, enum: %w[skip update], nullable: true },
      duplicate_modes: { type: :array, items: { type: :string, enum: %w[skip update] }, description: "Modos que admite el tipo" },
      columns: { type: :array, items: { type: :string }, description: "Columnas que reconoce el tipo" },
      required_columns: { type: :array, items: { type: :string } },
      warnings: { type: :array, items: { type: :string, enum: %w[consent_not_recorded] } },
      total_count: { type: :integer }, ready_count: { type: :integer }, rejected_count: { type: :integer },
      created_count: { type: :integer }, updated_count: { type: :integer }, restored_count: { type: :integer },
      skipped_count: { type: :integer }, failed_count: { type: :integer },
      expires_at: { type: :string, format: "date-time", description: "UTC; vencimiento de la previsualización" },
      confirmed_at: { type: :string, format: "date-time", nullable: true },
      finished_at: { type: :string, format: "date-time", nullable: true },
      created_at: { type: :string, format: "date-time" },
      preview: { type: :array, items: { "$ref" => "#/components/schemas/ImportRow" }, description: "Las primeras 20 filas" }
    },
    required: %i[id kind status duplicate_mode duplicate_modes columns required_columns warnings total_count ready_count rejected_count
                 created_count updated_count restored_count skipped_count failed_count expires_at confirmed_at finished_at created_at preview],
    additionalProperties: false
  }
)

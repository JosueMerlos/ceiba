# Imports domain errors that the API translates to problem+json (see Api::ErrorRegistry). Their messages carry counts and
# column names only, never a cell value, so the detail is the message.
Rails.application.config.to_prepare do
  detail = ->(error) { error.message }
  Api::ErrorRegistry.register(Imports::FileTooLarge, status: :content_too_large, code: "import.file_too_large", detail:)
  Api::ErrorRegistry.register(Imports::TooManyRows, status: :unprocessable_content, code: "import.too_many_rows", detail:)
  Api::ErrorRegistry.register(Imports::EmptyFile, status: :unprocessable_content, code: "import.empty_file", detail:)
  Api::ErrorRegistry.register(Imports::UnreadableFile, status: :unprocessable_content, code: "import.unreadable_file", detail:)
  Api::ErrorRegistry.register(Imports::DuplicateColumns, status: :unprocessable_content, code: "import.duplicate_columns", detail:)
  Api::ErrorRegistry.register(Imports::MissingColumns, status: :unprocessable_content, code: "import.missing_columns", detail:)
  Api::ErrorRegistry.register(Imports::UnknownKind, status: :unprocessable_content, code: "import.unknown_kind", detail:)
  Api::ErrorRegistry.register(Imports::DuplicateModeNotAllowed, status: :unprocessable_content, code: "import.duplicate_mode_not_allowed", detail:)
  Api::ErrorRegistry.register(Imports::NothingToImport, status: :unprocessable_content, code: "import.nothing_to_import", detail:)
  Api::ErrorRegistry.register(Imports::NotConfirmable, status: :conflict, code: "import.not_confirmable", detail:)
  Api::ErrorRegistry.register(Imports::AlreadyRunning, status: :conflict, code: "import.already_running", detail:)
end

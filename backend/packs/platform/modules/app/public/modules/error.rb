module Modules
  # Root of the pack's errors: `rescue Modules::Error` catches the whole modules domain.
  class Error < StandardError; end
end

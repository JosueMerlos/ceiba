module Imports
  # The uploaded file cannot become a batch. Messages carry counts and column names only, never cell values.
  class InvalidFile < Error; end
end

module Api
  # Multipart body above the cap, or of unknown length. Answers 413 (see ApiRequestGuard).
  class PayloadTooLarge < StandardError; end
end

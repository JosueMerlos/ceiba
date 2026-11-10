module Modules
  # A manifest breaks the rules. Fails boot (or the test) with ALL problems found, not just the first, so they get fixed at once.
  class InvalidManifest < Error
    attr_reader :key, :problems

    def initialize(key, problems)
      @key = key.to_s
      @problems = Array(problems).freeze
      super("Manifiesto #{@key.inspect} inválido:\n#{@problems.map { |problem| "- #{problem}" }.join("\n")}")
    end
  end
end

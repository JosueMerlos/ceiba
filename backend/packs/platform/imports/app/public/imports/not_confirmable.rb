module Imports
  class NotConfirmable < Error
    def initialize = super("La importación ya no se puede confirmar: ya se confirmó o su previsualización venció")
  end
end

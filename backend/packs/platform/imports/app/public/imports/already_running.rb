module Imports
  class AlreadyRunning < Error
    def initialize = super("Ya hay una importación de este tipo en curso en la empresa: espera a que termine")
  end
end

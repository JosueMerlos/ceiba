ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Provisional: RSpec sustituye a minitest en M0.02 y estos tests se migran.

# Servidor TCP que acepta conexiones y nunca responde: simula una dependencia colgada
# (como `docker compose pause db`) sin necesidad de stubs.
module BlackholeServer
  def with_blackhole
    server = TCPServer.new("127.0.0.1", 0)
    connections = []
    acceptor = Thread.new { loop { connections << server.accept } }
    yield server.addr[1]
  ensure
    acceptor&.kill
    connections&.each(&:close)
    server&.close
  end
end

ActiveSupport::TestCase.include BlackholeServer

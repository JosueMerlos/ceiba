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

RSpec.configure { |config| config.include BlackholeServer }

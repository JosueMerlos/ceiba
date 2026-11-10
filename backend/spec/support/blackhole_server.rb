# TCP server that accepts connections and never answers: simulates a hung dependency (like `docker compose pause db`)
# without stubs.
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

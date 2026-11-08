# Espía los puntos de entrada del pool de Active Record por los que se obtiene una conexión.
# Con fixtures transaccionales el hilo del test ya tiene una conexión arrendada, así que vigilar
# solo `checkout` no detectaría un uso: también hay que vigilar `lease_connection` y
# `with_connection` (`connection` ya no existe en Rails 8.1).
module ConnectionPoolSpy
  POOL_ENTRY_POINTS = %i[checkout with_connection lease_connection].freeze

  def spy_on_connection_pool
    ActiveRecord::Base.connection_pool.tap do |pool|
      POOL_ENTRY_POINTS.each { |method| allow(pool).to receive(method).and_call_original }
    end
  end

  def expect_connection_pool_untouched(pool)
    POOL_ENTRY_POINTS.each { |method| expect(pool).not_to have_received(method) }
  end
end

RSpec.configure { |config| config.include ConnectionPoolSpy }

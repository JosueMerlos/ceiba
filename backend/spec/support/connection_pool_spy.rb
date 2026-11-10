# Spies on the Active Record pool entry points through which a connection is obtained. With transactional fixtures the
# test thread already has a leased connection, so watching only `checkout` would not detect a use: `lease_connection`
# and `with_connection` must be watched too (`connection` no longer exists in Rails 8.1).
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

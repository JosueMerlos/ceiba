# Redis URL shared by Sidekiq and /api/ready, resolved with the same default as the production cache store (RedisSettings).
require Rails.root.join("config/redis_settings").to_s

redis_url = RedisSettings.url

# In test ALWAYS use database 15, whatever REDIS_URL says (compose gives database 0 to every container, including the
# development worker): specs with real Redis run flushdb and wipe the cron, and a development worker would consume the
# suite's jobs.
if Rails.env.test?
  test_url = URI(redis_url)
  test_url.path = "/15"
  redis_url = test_url.to_s
end

Rails.application.config.x.redis_url = redis_url

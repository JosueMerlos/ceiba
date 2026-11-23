# Each chunk of a confirmed import runs as a delivery of its own event, in the default queue: a 5000-row import must not
# hold the critical queue the relay and the other deliveries use.
Rails.application.config.to_prepare do
  Events.subscribe(Imports::ProcessChunk::EVENT, as: "imports.process_chunk", queue: "default") do |event|
    batch_id = event.payload["import_batch_id"]
    Imports::ProcessChunk.call(batch_id:) if batch_id
  end
end

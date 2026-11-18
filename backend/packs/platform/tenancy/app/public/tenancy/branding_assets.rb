module Tenancy
  # The company's branding images (logo, banner and favicon) as ONE table, and the Active Storage work around them, so the
  # callers that change a brand never touch Active Storage internals.
  #
  # The table is the single source of the kinds, their size limits and the variants served for each (in publication order). The
  # variants are the only thing ever served; they are re-encoded, so an original (with its metadata) is never exposed.
  #
  # Active Storage's own jobs are never used (they would be enqueued on Sidekiq, outside the outbox): originals are uploaded
  # without identification or analysis, variants are rendered by `render!` and replaced blobs are removed by `purge!`, both meant
  # to run right after the outermost transaction commits. Attachments do not touch their company (see
  # config.active_storage.touch_attachment_records): `touch!` is the one place the company's version changes for an image, and
  # that version is what the public ETag follows.
  #
  #   assets = Tenancy::BrandingAssets.new(company)
  #   blobs = assets.stage(uploads, content_types:)  # originals uploaded; undone by discard! if the transaction rolls back
  #   replaced = assets.attach(blobs)                # takes effect when the company is saved
  #   removed = assets.detach(%i[banner])
  #   company.save!
  #   assets.touch!
  class BrandingAssets
    WEBP = { format: :webp, saver: { strip: true } }.freeze
    PNG = { format: :png, saver: { strip: true } }.freeze

    ASSETS = {
      logo: { max_bytes: 2.megabytes, variants: { x1: { resize_to_limit: [ nil, 64 ], **WEBP }, x2: { resize_to_limit: [ nil, 128 ], **WEBP } } },
      banner: { max_bytes: 5.megabytes, variants: { wide: { resize_to_fill: [ 1600, 900 ], **WEBP }, standard: { resize_to_fill: [ 1200, 900 ], **WEBP } } },
      favicon: { max_bytes: 200.kilobytes, variants: { icon32: { resize_to_fill: [ 32, 32 ], **PNG }, icon180: { resize_to_fill: [ 180, 180 ], **PNG } } }
    }.freeze
    KINDS = ASSETS.keys.freeze

    def self.max_bytes(kind) = ASSETS.fetch(kind).fetch(:max_bytes)
    def self.variant_names(kind) = ASSETS.fetch(kind).fetch(:variants).keys

    def initialize(company)
      @company = company
      @staged = []
      @changed = false
    end

    # Uploads the original of each (already validated) file; returns { kind => blob }. `identify: false` and the preset metadata
    # stop Active Storage from identifying it again by name or enqueueing an analysis.
    def stage(files, content_types:)
      files.slice(*content_types.keys).to_h do |kind, upload|
        blob = ActiveStorage::Blob.create_and_upload!(
          io: upload.tempfile, filename: upload.original_filename, content_type: content_types.fetch(kind), identify: false,
          metadata: { "identified" => true, "analyzed" => true }
        )
        @staged << blob
        [ kind, blob ]
      end
    end

    # Assigning a blob swaps the attachment when the company is saved; returns the blobs that were replaced, to be purged.
    def attach(blobs)
      blobs.filter_map do |kind, blob|
        @changed = true
        previous = @company.public_send(kind).blob if @company.public_send(kind).attached?
        @company.public_send(:"#{kind}=", blob)
        previous
      end
    end

    # Detaches the kinds that have an image, at once; returns { kind => blob } of what was detached, to be purged.
    def detach(kinds)
      kinds.filter_map do |kind|
        attachment = @company.public_send(kind)
        next unless attachment.attached?

        @changed = true
        [ kind, attachment.blob.tap { attachment.detach } ]
      end.to_h
    end

    # Bumps the company's version when an image was attached or detached, even if no column changed.
    def touch!
      @company.touch if @changed
    end

    # The variants of the given kinds, resolved now (inside the tenant) to be rendered after the commit.
    def variants(kinds) = kinds.flat_map { |kind| @company.branding_variants(kind).values }

    def render!(variants) = variants.each(&:processed)

    # Variant records and their rendered files first (their own purge would enqueue a job), then the original.
    def purge!(blobs)
      blobs.each { |blob| purge(blob) }
    end

    # The originals of a rolled-back change: the rows go with the transaction, the files would stay.
    def discard!
      @staged.each { |blob| blob.service.delete(blob.key) }
    rescue StandardError => error
      Rails.error.report(error, handled: true)
    end

    private

    def purge(blob)
      blob.variant_records.includes(image_attachment: :blob).each do |variant|
        rendered = variant.image_attachment&.blob
        variant.image_attachment&.delete
        variant.delete
        rendered&.purge
      end
      blob.purge
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { blob_id: blob.id })
    end
  end
end

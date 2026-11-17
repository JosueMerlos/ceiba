module Access
  # The one write path of a company's branding: text, colors, font and the logo, banner and favicon images.
  #
  #   Access::UpdateBranding.call(company:, attributes: { primary_color: "#FFFF00" }, files: { logo: upload }, remove: %w[banner])
  #
  # - EVERYTHING is validated before anything is written (fields and every file, each by what its bytes are), so a bad file
  #   next to valid colors saves nothing: ActiveRecord::RecordInvalid with the errors of the fields and the files together.
  # - Each original is uploaded inside the caller's transaction (it is never served). Its variants, the only thing ever served,
  #   are rendered right AFTER the outermost transaction commits, still inside the request: a variant's file is uploaded by an
  #   after-commit callback that reads a temporary file closed by then if the render ran inside a transaction. So no job is
  #   needed, and a rollback leaves neither variants nor purged images.
  # - The change is audited in the same transaction. A request that changes nothing is not audited.
  # - Replaced and removed blobs are purged after that same commit, synchronously. ActiveStorage's own purge enqueues jobs on
  #   Sidekiq, outside the outbox, so it is not used.
  class UpdateBranding
    def self.call(...) = new(...).call

    def initialize(company:, attributes:, files: {}, remove: [])
      @company = company
      @attributes = attributes
      @files = files.compact
      @remove = remove.map(&:to_sym) - @files.keys
      unknown = (@files.keys + @remove) - Tenancy::BrandingFile::KINDS
      raise ArgumentError, "adjuntos de marca desconocidos: #{unknown.join(', ')}" if unknown.any?
    end

    def call
      ApplicationRecord.transaction(requires_new: true) do
        @company.assign_attributes(@attributes)
        content_types = validate!
        before = snapshot
        assets = store(content_types)
        replaced = replace(assets) + detach_removed(assets)
        @company.save!
        @company.touch if assets.value?(nil)
        audit(before, assets)
        after_commit(assets, replaced)
      end
      @company
    rescue StandardError
      discard(@uploaded || [])
      raise
    end

    private

    # Fields and files together; returns { kind => detected content type }.
    def validate!
      @company.validate
      content_types = @files.filter_map do |kind, upload|
        [ kind, Tenancy::BrandingFile.call(upload, kind:) ]
      rescue Tenancy::BrandingFile::Rejected => error
        @company.errors.add(kind, error.code, message: error.message)
        nil
      end.to_h
      raise ActiveRecord::RecordInvalid, @company if @company.errors.any?

      content_types
    end

    def snapshot = Tenancy::Company::Branding::ATTRIBUTES.index_with { |name| @company.attribute_in_database(name) }

    # The original is uploaded now (the variants are rendered from it); it is never served. `identify: false` and the
    # preset metadata stop Active Storage from identifying it again by name or enqueueing an analysis.
    def store(content_types)
      @uploaded = []
      @files.slice(*content_types.keys).to_h do |kind, upload|
        blob = ActiveStorage::Blob.create_and_upload!(
          io: upload.tempfile, filename: upload.original_filename, content_type: content_types.fetch(kind), identify: false,
          metadata: { "identified" => true, "analyzed" => true }
        )
        @uploaded << blob
        [ kind, blob ]
      end
    end

    # Assigning an attached blob swaps the attachment on save; the previous blob is returned to be purged.
    def replace(assets)
      assets.filter_map do |kind, blob|
        previous = @company.public_send(kind).blob if @company.public_send(kind).attached?
        @company.public_send(:"#{kind}=", blob)
        previous
      end
    end

    def detach_removed(assets)
      @remove.filter_map do |kind|
        attachment = @company.public_send(kind)
        next unless attachment.attached?

        assets[kind] = nil
        attachment.blob.tap { attachment.detach }
      end
    end

    def audit(before, assets)
      after = Tenancy::Company::Branding::ATTRIBUTES.index_with { |name| @company.public_send(name) }
      return if before == after && assets.empty?

      Audit.record(
        action: "company.branding_updated", subject: @company, before:, after:,
        metadata: assets.empty? ? {} : { assets: assets.transform_values { |blob| blob && { filename: blob.filename.to_s, byte_size: blob.byte_size, checksum: blob.checksum } } }
      )
    end

    # Runs once the outermost transaction committed (at once if there is none). Variants are only rendered for the images that
    # were uploaded now; a failure here surfaces to the caller, the change being already committed.
    def after_commit(assets, replaced)
      variants = assets.compact.keys.flat_map { |kind| Tenancy::Company::Branding::VARIANTS.fetch(kind).map { |name| @company.public_send(kind).variant(name) } }
      return if variants.empty? && replaced.empty?

      ActiveRecord.after_all_transactions_commit do
        variants.each(&:processed)
        replaced.each { |blob| purge(blob) }
      end
    end

    # Variant records and their rendered files first (their own purge would enqueue a job), then the original.
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

    # The original of a rolled-back change: the row goes with the transaction, the file would stay.
    def discard(blobs)
      blobs.each { |blob| blob.service.delete(blob.key) }
    rescue StandardError => error
      Rails.error.report(error, handled: true)
    end
  end
end

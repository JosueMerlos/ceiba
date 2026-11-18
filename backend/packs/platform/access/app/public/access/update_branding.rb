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
      @company = Tenancy::Directory.company_for_branding!(company.id)
      @assets = Tenancy::BrandingAssets.new(@company)
      @attributes = attributes
      @files = files.compact
      @remove = remove.map(&:to_sym) - @files.keys
      unknown = (@files.keys + @remove) - Tenancy::BrandingAssets::KINDS
      raise ArgumentError, "adjuntos de marca desconocidos: #{unknown.join(', ')}" if unknown.any?
    end

    def call
      ApplicationRecord.transaction(requires_new: true) do
        @company.assign_attributes(@attributes)
        content_types = validate!
        before = @company.persisted_branding_attributes
        staged = @assets.stage(@files, content_types:)
        replaced = @assets.attach(staged)
        removed = @assets.detach(@remove)
        @company.save!
        @assets.touch!
        audit(before, staged.merge(removed.transform_values { nil }))
        after_commit(staged.keys, replaced + removed.values)
      end
      @company
    rescue StandardError
      @assets.discard!
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

    def audit(before, assets)
      after = @company.branding_attributes
      return if before == after && assets.empty?

      Audit.record(
        action: "company.branding_updated", subject: @company, before:, after:,
        metadata: assets.empty? ? {} : { assets: assets.transform_values { |blob| blob && { filename: blob.filename.to_s, byte_size: blob.byte_size, checksum: blob.checksum } } }
      )
    end

    # Runs once the outermost transaction committed (at once if there is none). Variants are only rendered for the images that
    # were uploaded now; a failure here surfaces to the caller, the change being already committed.
    def after_commit(uploaded_kinds, replaced)
      variants = @assets.variants(uploaded_kinds)
      return if variants.empty? && replaced.empty?

      ActiveRecord.after_all_transactions_commit do
        @assets.render!(variants)
        @assets.purge!(replaced)
      end
    end
  end
end

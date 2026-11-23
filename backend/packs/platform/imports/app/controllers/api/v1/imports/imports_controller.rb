module Api
  module V1
    module Imports
      # CSV imports of the route's company, uploaded from the route's branch. Each kind is authorized by its owner pack's policy
      # and, when a module owns it, only answers while that module is active in the company (404 otherwise, like a module's
      # own routes). Batches are searched among the route's company AND branch: another one's is a 404, never a 403.
      # Inside this namespace `Imports` is Api::V1::Imports: the pack's own constants are always written `::Imports`.
      #
      # Not idempotent on purpose: the stored replay would keep the preview's personal data beyond the batch's retention.
      class ImportsController < ::Api::BaseController
        PREVIEW_ROWS = 20
        # Base64 inflates by 4/3: anything longer cannot decode to a file within the size limit, so it is refused before
        # decoding.
        MAX_ENCODED_BYTES = ((::Imports::CreateBatch::MAX_BYTES * 4) / 3) + 4

        def create
          values = typed_params(kind: String, content_base64: String)
          entry = registry_entry(values[:kind])
          authorize ::Imports::Batch.new(company_id:, kind: entry.kind), :create?, policy_class: entry.policy_class
          batch = ::Imports::CreateBatch.call(kind: entry.kind, bytes: file_bytes(values[:content_base64]), company_id:,
                                              branch_id: Current.context.branch.id, created_by_id: Current.principal.id)
          render_batch(batch, status: :created)
        end

        def show
          authorize_batch(:show?)
          render_batch(batch)
        end

        def rows
          authorize_batch(:show?)
          page = ::Api::Pagination::Cursor.paginate(filtered_rows, limit: params[:limit], after: params[:after])
          render json: { data: ::Imports::RowSerializer.new(page.records, params: { values: batch.previewed? }).serializable_hash, page: page.meta }
        end

        def confirm
          authorize_batch(:create?)
          ::Imports::ConfirmBatch.call(batch:, duplicate_mode: typed_params(duplicate_mode: String)[:duplicate_mode])
          render_batch(batch, status: :accepted)
        end

        private

        def company_id = Current.context.company.id

        def batch
          @batch ||= ::Imports::Batch.find_by!(id: params[:import_id], company_id:, branch_id: Current.context.branch.id)
        end

        def authorize_batch(action)
          registry_entry(batch.kind).then { authorize batch, action, policy_class: it.policy_class }
        end

        # The module gate goes BEFORE authorization, as in the modules' own controllers.
        def registry_entry(kind)
          entry = ::Imports::Registry.fetch(kind)
          raise ActiveRecord::RecordNotFound, "No se encontró el recurso" if entry.module_key && !::Modules.enabled?(company_id, entry.module_key)

          entry
        end

        def file_bytes(encoded)
          raise ::Imports::EmptyFile if encoded.blank?
          raise ::Imports::FileTooLarge.new(max_bytes: ::Imports::CreateBatch::MAX_BYTES) if encoded.bytesize > MAX_ENCODED_BYTES

          Base64.strict_decode64(encoded)
        rescue ArgumentError
          raise ::Imports::UnreadableFile
        end

        def filtered_rows
          status = params[:status]
          raise ActionController::BadRequest, "status no es un estado de fila" unless status.nil? || ::Imports::Row::STATUSES.include?(status)

          scope = batch.rows.unscope(:order)
          status ? scope.where(status:) : scope
        end

        def render_batch(batch, status: :ok)
          preview = ::Imports::RowSerializer.new(batch.rows.limit(PREVIEW_ROWS), params: { values: batch.previewed? }).serializable_hash
          importer = ::Imports::Registry.fetch(batch.kind).importer_class.new(company_id: batch.company_id)
          data = ::Imports::BatchSerializer.new(batch, params: { importer: }).serializable_hash.merge(preview:)
          render json: { data: }, status:
        end
      end
    end
  end
end

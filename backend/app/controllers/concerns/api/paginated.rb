module Api
  # Standard paginated response: { data: [...], page: { next_cursor, has_more } }.
  #
  #   def index = render_page(company_scope, serializer: CompanySerializer)
  module Paginated
    private

    def render_page(scope, serializer:, status: :ok)
      page = Pagination::Cursor.paginate(scope, limit: params[:limit], after: params[:after])
      render json: { data: serializer.new(page.records).serializable_hash, page: page.meta }, status:
    end
  end
end

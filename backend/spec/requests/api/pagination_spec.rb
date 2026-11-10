require "rails_helper"

# The pagination HTTP contract: { data: [...], page: { next_cursor, has_more } } and 400 problem+json errors.
RSpec.describe "Paginación por cursor en la API" do
  include_context "con endpoints de prueba de la API"

  def page_of(query = {})
    get "/api/v1/probes/organizations", params: query
    response.parsed_body
  end

  it "responde data + page.{next_cursor,has_more} y se recorre con ?after=" do
    ids = Array.new(5) { create(:organization).id }

    first = page_of(limit: 2)
    second = page_of(limit: 2, after: first.dig("page", "next_cursor"))
    third = page_of(limit: 2, after: second.dig("page", "next_cursor"))

    expect(first["page"]).to include("has_more" => true)
    expect(third["page"]).to eq("next_cursor" => nil, "has_more" => false)
    expect([ first, second, third ].flat_map { |page| page["data"].pluck("id") }).to eq(ids)
  end

  it "responde 400 problem+json ante un cursor manipulado" do
    page_of(after: "cursor-falso")

    expect(response).to have_http_status(:bad_request)
    expect(response.media_type).to eq("application/problem+json")
    expect(response.parsed_body).to include("code" => "pagination.invalid_cursor", "status" => 400, "request_id" => be_present)
  end

  it "responde 400 problem+json ante un limit inválido" do
    page_of(limit: 1000)

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to include("code" => "pagination.invalid_limit")
  end
end

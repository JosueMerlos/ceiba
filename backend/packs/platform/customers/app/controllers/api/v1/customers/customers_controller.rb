module Api
  module V1
    module Customers
      # Customers of the route's company, managed from the route's branch (permissions are checked at the branch's scope).
      # Everything is searched inside the route's company, so a customer of another company is a 404, never a 403.
      # Inside this namespace `Customers` is Api::V1::Customers: the pack's own constants are always written `::Customers`.
      class CustomersController < ::Api::BaseController
        include ::Idempotency::Idempotent

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so authorizing in it
        # would fail verify_authorized and would skip the permission check for a principal whose access was revoked.
        before_action :authorize_creation, only: :create
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent :create, required: false

        def index
          authorize company_customers, :index?, policy_class: ::Customers::CustomerPolicy
          customers = policy_scope(company_customers.active, policy_scope_class: ::Customers::CustomerPolicy::Scope)
          customers = customers.with_phone(text_param(:phone)) if text_param(:phone)
          customers = customers.name_prefix(text_param(:name_prefix)) if text_param(:name_prefix)
          render_page(customers, serializer: ::Customers::CustomerSerializer)
        end

        def show
          customer = company_customers.find(params[:id])
          authorize customer, :show?, policy_class: ::Customers::CustomerPolicy
          render_customer(customer)
        end

        def create
          customer = ::Customers::Create.call(company_id:, attributes: customer_params)
          render_customer(customer, status: :created)
        end

        def update
          customer = company_customers.find(params[:id])
          authorize customer, :update?, policy_class: ::Customers::CustomerPolicy
          render_customer(::Customers::Update.call(customer:, attributes: customer_params))
        end

        def destroy
          customer = company_customers.find(params[:id])
          authorize customer, :destroy?, policy_class: ::Customers::CustomerPolicy
          ::Customers::Archive.call(customer:)
          head :no_content
        end

        private

        def authorize_creation
          authorize ::Customers::Customer.new(company_id:), :create?, policy_class: ::Customers::CustomerPolicy
        end

        def company_id = Current.context.company.id

        def company_customers = ::Customers::Customer.where(company_id:)

        def render_customer(customer, status: :ok)
          render json: { data: ::Customers::CustomerSerializer.new(customer).serializable_hash }, status:
        end

        def customer_params = typed_params(full_name: String, phone_e164: String, email: String, notes: String)

        def text_param(name)
          value = params[name]
          raise ActionController::BadRequest, "#{name} debe ser texto" unless value.nil? || (value.is_a?(String) && !value.include?("\u0000"))

          value.presence
        end
      end
    end
  end
end

# Readiness: 200 solo si las dependencias críticas (PostgreSQL y Redis) responden.
class ReadyController < ApplicationController
  def show
    result = ReadinessCheck.new.call

    render json: result.to_h, status: result.ready? ? :ok : :service_unavailable
  end
end

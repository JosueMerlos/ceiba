# Readiness: 200 only if the critical dependencies (PostgreSQL and Redis) respond.
class ReadyController < ApplicationController
  def show
    result = ReadinessCheck.new.call

    render json: result.to_h, status: result.ready? ? :ok : :service_unavailable
  end
end

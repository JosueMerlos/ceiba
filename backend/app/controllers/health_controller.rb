# Liveness: the process responds. Deliberately does not touch the database or Redis.
class HealthController < ApplicationController
  def show
    render json: { status: "ok" }
  end
end

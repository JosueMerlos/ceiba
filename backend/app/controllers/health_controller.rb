# Liveness: el proceso responde. No toca la base de datos ni Redis a propósito.
class HealthController < ApplicationController
  def show
    render json: { status: "ok" }
  end
end

class DemoController < ApplicationController
  def index
    # Render the main page with buttons
    Rails.logger.info "Rendering demo page path=#{request.path}"
  end

  def log_action
    # Create log entries at different levels
    Rails.logger.info "User triggered log event type=manual"
    Rails.logger.debug "Debug details: request_id=#{request.request_id}"

    render json: {
      message: "Log entries created successfully",
      timestamp: Time.current,
      log_levels: ["info", "debug"]
    }
  end

  def slow_action
    tracer = OpenTelemetry.tracer_provider.tracer('demo')

    tracer.in_span('slow_operation') do |span|
      span.set_attribute('operation.type', 'database_simulation')
      duration = rand(0.5..2.0)

      Rails.logger.info "Starting slow operation expected_duration=#{duration}"
      sleep(duration)
      Rails.logger.info "Completed slow operation actual_duration=#{duration}"
    end

    render json: { message: "Slow action completed", duration: "variable" }
  end

  def error_action
    tracer = OpenTelemetry.tracer_provider.tracer('demo')

    tracer.in_span('risky_operation') do |span|
      begin
        Rails.logger.warn "About to perform risky operation"
        raise StandardError, "Simulated error for testing"
      rescue => e
        span.record_exception(e)
        span.status = OpenTelemetry::Trace::Status.error(e.message)

        Rails.logger.error "Error occurred: #{e.message} error_class=#{e.class.name}"

        render json: { error: e.message }, status: :internal_server_error
        return
      end
    end
  end
end

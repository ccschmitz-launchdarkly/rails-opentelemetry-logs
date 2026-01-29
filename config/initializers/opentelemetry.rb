require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'
require 'opentelemetry-logs-sdk'
require 'opentelemetry/exporter/otlp_logs'

OTEL_ENDPOINT = ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT')
PROJECT_ID = ENV.fetch('LAUNCHDARKLY_PROJECT_ID')
OTEL_SERVICE_NAME = ENV.fetch('OTEL_SERVICE_NAME', 'rails-opentelemetry-demo')
OTEL_SERVICE_VERSION = ENV.fetch('OTEL_SERVICE_VERSION', '1.0.0')

if PROJECT_ID.blank?
  raise "LAUNCHDARKLY_PROJECT_ID is not set"
end

# Shared resource with project ID
OTEL_RESOURCE = OpenTelemetry::SDK::Resources::Resource.create(
  'service.name' => OTEL_SERVICE_NAME,
  'service.version' => OTEL_SERVICE_VERSION,
  'launchdarkly.project_id' => PROJECT_ID
)

# ----- Configure Traces + Logger Bridge -----
OpenTelemetry::SDK.configure do |c|
  c.service_name = OTEL_SERVICE_NAME
  c.service_version = OTEL_SERVICE_VERSION
  c.resource = OTEL_RESOURCE

  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: "#{OTEL_ENDPOINT}/v1/traces"
      )
    )
  )

  # Enable all auto-instrumentation (Rails, ActiveRecord, Net::HTTP, Logger, etc.)
  # Note: use_all includes the Logger instrumentation which bridges Rails.logger to OTel logs
  c.use_all
end

# ----- Configure Logs Pipeline (experimental) -----
logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new(resource: OTEL_RESOURCE)

logs_processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(
  OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(
    endpoint: "#{OTEL_ENDPOINT}/v1/logs"
  )
)

logger_provider.add_log_record_processor(logs_processor)

# Set global logger provider so the Logger bridge can export
OpenTelemetry.logger_provider = logger_provider if OpenTelemetry.respond_to?(:logger_provider=)

# Ensure logs are flushed on shutdown
at_exit { logger_provider.shutdown }

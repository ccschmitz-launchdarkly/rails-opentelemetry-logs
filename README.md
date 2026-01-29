# Rails OpenTelemetry Example

A reference implementation for instrumenting a Rails application with OpenTelemetry to export **traces** and **logs** via OTLP. Copy this project as a starting point for adding observability to your own Rails apps.

## What This Example Demonstrates

- **Trace exporting** via OTLP (stable)
- **Log exporting** via OTLP (experimental)
- **Rails.logger bridge** to automatically export logs as OTel log records
- **Auto-instrumentation** for Rails, ActiveRecord, Net::HTTP, and more
- **Log/trace correlation** with automatic `trace_id` and `span_id` injection
- **Custom spans** with attributes and exception recording

## Quick Start

```bash
# Clone and install
git clone <this-repo>
cd rails-opentelemetry
bundle install

# Configure your endpoint (optional - defaults to LaunchDarkly staging)
export OTEL_EXPORTER_OTLP_ENDPOINT=https://your-otel-collector:4318
export LAUNCHDARKLY_PROJECT_ID=your-project-id

# Start the server
rails server
```

Visit http://localhost:3000 to see the demo UI with buttons to trigger different telemetry events.

---

## How to Add OpenTelemetry to Your Rails App

### Step 1: Add the Gems

Add these to your `Gemfile`:

```ruby
# OpenTelemetry - Traces (stable)
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
gem "opentelemetry-instrumentation-all"

# OpenTelemetry - Logs (experimental)
gem "opentelemetry-logs-sdk"
gem "opentelemetry-exporter-otlp-logs"

# Bridge Ruby Logger (used by Rails) -> OTel Logs
gem "opentelemetry-instrumentation-logger"
```

Then run `bundle install`.

### Step 2: Create the Initializer

Create `config/initializers/opentelemetry.rb`:

```ruby
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'
require 'opentelemetry-logs-sdk'
require 'opentelemetry/exporter/otlp_logs'

# Configuration
OTEL_ENDPOINT = ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://localhost:4318')
PROJECT_ID = ENV.fetch('LAUNCHDARKLY_PROJECT_ID', 'your-project-id')

# Shared resource - customize these attributes for your service
OTEL_RESOURCE = OpenTelemetry::SDK::Resources::Resource.create(
  'service.name' => 'your-service-name',
  'service.version' => '1.0.0',
  'highlight.project_id' => PROJECT_ID  # Routes telemetry to your project
)

# ----- Configure Traces -----
OpenTelemetry::SDK.configure do |c|
  c.service_name = 'your-service-name'
  c.service_version = '1.0.0'
  c.resource = OTEL_RESOURCE

  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: "#{OTEL_ENDPOINT}/v1/traces"
      )
    )
  )

  # Enable all auto-instrumentation (Rails, ActiveRecord, Net::HTTP, Logger, etc.)
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
```

### Step 3: Use It

That's it! With the initializer in place:

- **Automatic instrumentation** captures Rails requests, database queries, HTTP calls, etc.
- **Rails.logger calls** are automatically bridged to OTel logs
- **Logs inside spans** get `trace_id` and `span_id` for correlation

---

## Creating Custom Spans

For more granular tracing, create custom spans:

```ruby
class MyController < ApplicationController
  def my_action
    tracer = OpenTelemetry.tracer_provider.tracer('my-app')

    tracer.in_span('custom_operation') do |span|
      # Add attributes
      span.set_attribute('user.id', current_user.id)
      span.set_attribute('operation.type', 'data_processing')

      # Your code here
      result = perform_operation

      # Logs inside the span automatically include trace context
      Rails.logger.info "Operation completed result=#{result}"
    end
  end
end
```

## Recording Errors

Exceptions can be recorded on spans for debugging:

```ruby
tracer.in_span('risky_operation') do |span|
  begin
    dangerous_operation
  rescue => e
    # Record the exception on the span
    span.record_exception(e)
    span.status = OpenTelemetry::Trace::Status.error(e.message)
    
    Rails.logger.error "Operation failed: #{e.message}"
    raise
  end
end
```

---

## Demo Endpoints

This example app includes demo endpoints for testing:

| Endpoint | Description |
|----------|-------------|
| `GET /` | Demo UI with buttons to trigger events |
| `GET /log` | Creates log entries at multiple levels |
| `GET /slow` | Simulates a slow operation (0.5-2s) with custom span |
| `GET /error` | Demonstrates error recording in traces |
| `GET /health` | Health check endpoint |

### Testing with curl

```bash
curl http://localhost:3000/log
curl http://localhost:3000/slow
curl http://localhost:3000/error
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `https://otel.observability.ld-stg.launchdarkly.com:4318` | OTLP collector endpoint (HTTP) |
| `LAUNCHDARKLY_PROJECT_ID` | `61b799a14714e00e3ef9c2fa` | Project ID for routing telemetry |

### Resource Attributes

The `highlight.project_id` resource attribute routes telemetry to the correct project in the LaunchDarkly observability backend. Update this to your project ID.

Standard semantic conventions for resource attributes:
- `service.name` - Logical name of your service
- `service.version` - Version of your service
- `deployment.environment` - Environment (production, staging, etc.)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Rails Application                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Rails.logger ──► Logger Instrumentation ──► OTel Logs Pipeline │
│                                                                  │
│  HTTP Requests ──► Rails Instrumentation ──► OTel Traces        │
│                                                                  │
│  Custom Spans ──────────────────────────────► OTel Traces       │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│            BatchSpanProcessor    BatchLogRecordProcessor         │
└──────────────────────┬──────────────────────┬───────────────────┘
                       │                      │
                       ▼                      ▼
              ┌────────────────┐    ┌────────────────┐
              │  /v1/traces    │    │   /v1/logs     │
              └────────┬───────┘    └────────┬───────┘
                       │                      │
                       ▼                      ▼
              ┌──────────────────────────────────────┐
              │         OTLP Collector               │
              │  (e.g., otel.observability.ld.com)   │
              └──────────────────────────────────────┘
```

---

## Stack

- **Ruby**: 3.1.7
- **Rails**: 7.1.6
- **OpenTelemetry SDK**: Latest stable
- **OpenTelemetry Logs SDK**: Experimental

## Notes

- **Logs are experimental**: The OpenTelemetry Logs SDK for Ruby is still experimental. APIs may change.
- **Batching**: Both traces and logs use batch processors for efficient export
- **Graceful shutdown**: The `at_exit` hook ensures logs are flushed before the process exits
- **Auto-instrumentation**: `use_all` enables instrumentation for Rails, ActiveRecord, Net::HTTP, Faraday, Redis, Sidekiq, and more

## Troubleshooting

### Traces/logs not appearing?

1. Check the endpoint is reachable: `curl -v $OTEL_EXPORTER_OTLP_ENDPOINT/v1/traces`
2. Verify your project ID is correct
3. Check Rails logs for OTel errors on startup
4. Ensure the collector accepts HTTP (port 4318), not gRPC (port 4317)

### Logger bridge not working?

Make sure `opentelemetry-instrumentation-logger` is installed and `use_all` is called, which includes the Logger instrumentation.

---

## License

MIT

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

# Configure environment variables (required)
cp .env.example .env
# Edit .env with your project ID

# Start the server
rails server
```

The `.env` file must contain:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.observability.app.launchdarkly.com:4318
LAUNCHDARKLY_PROJECT_ID=your-project-id
OTEL_SERVICE_NAME=rails-opentelemetry-demo  # optional
OTEL_SERVICE_VERSION=1.0.0                   # optional
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

> **Note**: This example uses `dotenv-rails` to load environment variables from `.env` in development/test environments.

### Step 2: Create the Initializer

Create `config/initializers/opentelemetry.rb`. See the full implementation in [`config/initializers/opentelemetry.rb`](config/initializers/opentelemetry.rb).

The initializer:
1. Loads required environment variables (`OTEL_EXPORTER_OTLP_ENDPOINT`, `LAUNCHDARKLY_PROJECT_ID`)
2. Creates a shared resource with service name, version, and project ID
3. Configures the trace pipeline with a batch span processor and OTLP exporter
4. Enables auto-instrumentation for Rails, ActiveRecord, Net::HTTP, Logger, etc.
5. Configures the logs pipeline (experimental) with a batch log record processor
6. Sets up graceful shutdown to flush logs on exit

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
| `GET /log` | Creates log entries at info and debug levels |
| `GET /slow` | Simulates a slow operation (0.5-2s) with custom span |
| `GET /error` | Demonstrates error recording in traces |

### Testing with curl

```bash
curl http://localhost:3000/log
curl http://localhost:3000/slow
curl http://localhost:3000/error
```

---

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Yes | - | OTLP collector endpoint (HTTP), e.g. `https://otel.observability.app.launchdarkly.com:4318` |
| `LAUNCHDARKLY_PROJECT_ID` | Yes | - | Project ID for routing telemetry |
| `OTEL_SERVICE_NAME` | No | `rails-opentelemetry-demo` | Logical name of your service |
| `OTEL_SERVICE_VERSION` | No | `1.0.0` | Version of your service |

### Resource Attributes

The `highlight.project_id` resource attribute routes telemetry to the correct project in the LaunchDarkly observability backend. This is set automatically from the `LAUNCHDARKLY_PROJECT_ID` environment variable.

Standard semantic conventions for resource attributes (set via environment variables):
- `service.name` - Logical name of your service (`OTEL_SERVICE_NAME`)
- `service.version` - Version of your service (`OTEL_SERVICE_VERSION`)
- `deployment.environment` - Environment (production, staging, etc.) - add to initializer if needed

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
              ┌───────────────────────────────────────────────────┐
              │                OTLP Collector                      │
              │  (e.g., otel.observability.app.launchdarkly.com)   │
              └───────────────────────────────────────────────────┘
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

### App won't start?

1. Ensure `OTEL_EXPORTER_OTLP_ENDPOINT` and `LAUNCHDARKLY_PROJECT_ID` are set (both are required)
2. Copy `.env.example` to `.env` and fill in your values
3. Check that `LAUNCHDARKLY_PROJECT_ID` is not blank

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

# Logging with Metrics Integration

This module provides seamless integration between the logging and metrics frameworks, allowing automatic collection of metrics from log events.

## Overview

The `logging_metrics` module extends the standard logging functionality with automatic metrics extraction, providing insights into application behavior through both logs and metrics simultaneously.

## Features

- **Automatic metrics extraction** from log events
- **Performance tracking** (duration, response times)
- **Error rate monitoring**
- **Custom metrics extractors**
- **Span-based tracing** with duration metrics
- **Module-specific metrics**
- **Thread-safe operations**
- **Multiple export formats**

## Basic Usage

```nim
import nim_libaspects/[logging, metrics, logging_metrics]

# Create a metrics registry
let registry = newMetricsRegistry()

# Create a logger with metrics integration
let logger = newMetricsLogger("myapp", registry)

# Log events - metrics are collected automatically
logger.info("Request processed", %*{
  "duration_ms": 150.5,
  "endpoint": "/api/users",
  "status_code": 200
})
```

## Configuration

The logging-metrics integration can be configured with various options:

```nim
var config = defaultMetricsConfig()
config.enableAutoMetrics = true
config.enableLevelMetrics = true
config.enableModuleMetrics = true
config.moduleFilter = @["api", "database"]

let logger = newMetricsLogger("myapp", registry, config)
```

### Configuration Options

- `enableAutoMetrics`: Automatically create standard metrics (logs_total, errors_total)
- `enableLevelMetrics`: Create per-level counters (logs_debug_total, logs_info_total, etc.)
- `enableModuleMetrics`: Create per-module counters
- `moduleFilter`: List of modules to track (empty = all modules)
- `extractors`: Custom metric extraction patterns

## Automatic Metrics

The following metrics are created automatically:

### Log Counters
- `logs_total`: Total number of log messages
- `logs_<level>_total`: Per-level counters (debug, info, warning, error)
- `<module>_logs_total`: Per-module counters
- `errors_total`: Total error count

### Performance Metrics
Fields ending with `_ms`, `_seconds`, `_duration` are automatically extracted as histograms:
- `duration_ms`
- `response_time_ms`
- `processing_time_ms`

### Error Tracking
Error logs automatically extract:
- `error_type` as labeled counter
- `error_code` as labeled counter
- `retry_count` as counter

## Custom Extractors

Define custom patterns for metric extraction:

```nim
var config = defaultMetricsConfig()
config.extractors = @[
  MetricsExtractor(
    pattern: ".*payment.*",
    histograms: @["amount", "processing_time"],
    counters: @["payment_method", "currency"],
    gauges: @["active_transactions"]
  ),
  MetricsExtractor(
    pattern: ".*auth.*",
    counters: @["auth_type", "success"],
    gauges: @["active_sessions"]
  )
]

let logger = newMetricsLogger("app", registry, config)
```

## Span Tracing

Track operation durations with spans:

```nim
# Start a span
let span = logger.startSpan("database_query")

# Do work...
let result = performDatabaseQuery()

# Log within the span
span.logger.info("Query executed", %*{
  "query": "SELECT * FROM users",
  "rows": result.rowCount
})

# End span - duration is recorded automatically
let duration = span.finish()
```

This creates:
- `span_duration_ms`: Overall span durations
- `span_<operation>_duration_ms`: Per-operation histograms

## Advanced Usage

### Thread-Safe Operations

All operations are thread-safe by default:

```nim
import std/threadpool

proc worker(logger: MetricsLogger) =
  for i in 0..100:
    logger.info("Processing", %*{"item": i})

let logger = newMetricsLogger("concurrent", registry)
parallel:
  for i in 0..3:
    spawn worker(logger)
```

### Metric Filtering

Control which metrics are created:

```nim
proc shouldExtractMetric(key: string, value: JsonNode): bool =
  # Only extract numeric values over 10
  result = value.kind in {JInt, JFloat} and value.getFloat() > 10

config.metricFilter = shouldExtractMetric
```

### Export Formats

Export metrics in various formats:

```nim
# JSON format
let jsonData = registry.exportMetrics(MetricsFormat.Json)

# Prometheus format
let promData = registry.exportMetrics(MetricsFormat.Prometheus)

# Graphite format
let graphiteData = registry.exportMetrics(MetricsFormat.Graphite)
```

## Performance Considerations

- Metrics extraction happens during log calls, so keep extractors efficient
- Use module filtering to reduce overhead
- Consider sampling for high-volume logs
- Histograms have configurable bucket sizes

## Best Practices

1. **Consistent naming**: Use standard suffixes (_ms, _total, _count)
2. **Label cardinality**: Keep label values bounded
3. **Module organization**: Group related metrics by module
4. **Error handling**: Always include error_type for errors
5. **Performance data**: Include duration_ms for timed operations

## Examples

### Web Application Metrics

```nim
let logger = newMetricsLogger("webapp", registry)

# Request handling
logger.info("Request handled", %*{
  "method": "GET",
  "endpoint": "/api/users",
  "duration_ms": 45.5,
  "status_code": 200,
  "user_agent": "Mozilla/5.0"
})

# Error tracking
logger.error("Request failed", %*{
  "method": "POST",
  "endpoint": "/api/orders",
  "error_type": "validation_error",
  "status_code": 400,
  "duration_ms": 12.3
})
```

### Background Job Metrics

```nim
let logger = newMetricsLogger("jobs", registry)

# Job execution
let span = logger.startSpan("process_payment")
try:
  # Process payment...
  span.logger.info("Payment processed", %*{
    "amount": 99.99,
    "currency": "USD",
    "payment_method": "credit_card"
  })
finally:
  span.finish()
```

### Database Metrics

```nim
let logger = newMetricsLogger("database", registry)

# Query tracking
logger.info("Query executed", %*{
  "query_type": "SELECT",
  "table": "users",
  "duration_ms": 23.4,
  "rows_returned": 42,
  "cache_hit": false
})
```

## API Reference

### Types

```nim
type
  MetricsLogger* = ref object
    logger*: Logger
    registry*: MetricsRegistry
    config*: MetricsConfig
    
  MetricsConfig* = object
    enableAutoMetrics*: bool
    enableLevelMetrics*: bool
    enableModuleMetrics*: bool
    moduleFilter*: seq[string]
    extractors*: seq[MetricsExtractor]
    
  MetricsExtractor* = object
    pattern*: string
    counters*: seq[string]
    gauges*: seq[string]
    histograms*: seq[string]
    
  SpanContext* = ref object
    logger*: MetricsLogger
    operation*: string
    startTime*: Time
```

### Functions

- `newMetricsLogger(module: string, registry: MetricsRegistry, config = defaultConfig): MetricsLogger`
- `startSpan(logger: MetricsLogger, operation: string): SpanContext`
- `finish(span: SpanContext): float`
- `defaultMetricsConfig(): MetricsConfig`
- `startTimer(): Timer`

### Logger Methods

All standard logging methods are available:
- `debug(msg: string, data: JsonNode = nil)`
- `info(msg: string, data: JsonNode = nil)`
- `warning(msg: string, data: JsonNode = nil)`
- `error(msg: string, data: JsonNode = nil)`

## Troubleshooting

### Metrics not appearing
- Check configuration settings
- Verify metric name patterns
- Ensure registry is shared between components

### High memory usage
- Reduce histogram bucket counts
- Limit label cardinality
- Use sampling for high-volume logs

### Performance overhead
- Disable unused metric types
- Use module filtering
- Optimize custom extractors
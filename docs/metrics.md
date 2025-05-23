# Metrics Module

The metrics module provides a comprehensive metrics collection system for monitoring and observability.

## Features

- Multiple metric types: Counter, Gauge, Histogram, Summary, and Timer
- Label support for dimensional metrics
- Thread-safe operations
- Prometheus format export
- Automatic metrics reporting
- Template support for automatic timing

## Metric Types

### Counter
A counter is a cumulative metric that represents a single numerical value that only ever goes up.

```nim
let counter = registry.counter("http_requests_total", @["method", "status"])
counter.inc(@["GET", "200"])
counter.inc(@["POST", "201"], 2.0)
```

### Gauge
A gauge is a metric that represents a single numerical value that can arbitrarily go up and down.

```nim
let gauge = registry.gauge("memory_usage_bytes")
gauge.set(1024.0)
gauge.inc(512.0)
gauge.dec(256.0)
```

### Histogram
A histogram samples observations and counts them in configurable buckets. It also provides a sum of all observed values.

```nim
let histogram = registry.histogram("request_duration_seconds", 
                                 buckets = @[0.1, 0.5, 1.0, 5.0])
histogram.observe(0.25)
let stats = histogram.getStatistics()
```

### Summary
A summary samples observations and provides configurable quantiles over a sliding time window.

```nim
let summary = registry.summary("request_size_bytes")
summary.observe(512.0)
let quantiles = summary.getQuantiles(@[0.5, 0.9, 0.99])
```

### Timer
A timer measures durations and is essentially a histogram optimized for timing measurements.

```nim
let timer = registry.timer("operation_duration_seconds")
let ctx = timer.start()
# ... do some work ...
let duration = ctx.stop()
```

## Usage

### Basic Usage

```nim
import nim_libaspects/metrics

# Create a metrics registry
let registry = newMetricsRegistry()

# Create and use a counter
let requests = registry.counter("requests_total")
requests.inc()

# Create and use a gauge
let connections = registry.gauge("active_connections")
connections.set(42.0)

# Create and use a histogram
let durations = registry.histogram("request_duration_seconds")
durations.observe(0.123)

# Export metrics in Prometheus format
echo registry.exportPrometheus()
```

### With Labels

```nim
# Create metrics with labels
let httpRequests = registry.counter("http_requests_total", @["method", "status"])

# Use with label values
httpRequests.inc(@["GET", "200"])
httpRequests.inc(@["POST", "404"])

# Query by labels
echo httpRequests.value(@["GET", "200"])
```

### Automatic Timing

```nim
# Using the metricsTimer template
proc processRequest() =
  metricsTimer("request_processing_time"):
    # Your code here
    sleep(100)
    
# Or manually
let timer = registry.timer("manual_timer")
let ctx = timer.start()
# ... do work ...
discard ctx.stop()
```

### Metrics Reporter

The metrics reporter allows periodic export of metrics:

```nim
# Create a reporter that logs metrics every 60 seconds
let reporter = newMetricsReporter(registry) do (r: MetricsRegistry):
  echo "Current metrics:"
  echo r.exportPrometheus()
  
# Start the reporter
reporter.start(interval = 60000)  # 60 seconds

# ... your application runs ...

# Stop the reporter
reporter.stop()
```

## Thread Safety

All metric operations are thread-safe. The module uses locks to ensure concurrent access is properly synchronized.

## Best Practices

1. Use descriptive metric names following the convention: `<namespace>_<name>_<unit>`
2. Keep the number of label dimensions reasonable (high cardinality can impact performance)
3. Use appropriate metric types:
   - Counter for things that only increase
   - Gauge for values that can go up and down
   - Histogram for measuring distributions
   - Summary for calculating quantiles
   - Timer for measuring durations
4. Document what each metric measures
5. Set up proper metric retention policies

## Integration with Monitoring Systems

The module provides Prometheus format export, making it easy to integrate with:
- Prometheus
- Grafana
- AlertManager
- Other Prometheus-compatible monitoring systems

## Example Application

```nim
import nim_libaspects/metrics
import std/[asyncdispatch, asynchttpserver]

let registry = newMetricsRegistry()
let requestCount = registry.counter("http_requests_total", @["method", "path"])
let requestDuration = registry.histogram("http_request_duration_seconds", @["method", "path"])

proc handler(req: Request): Future[void] {.async.} =
  let timer = requestDuration.start(@[req.reqMethod.`$`, req.url.path])
  defer: discard timer.stop()
  
  requestCount.inc(@[req.reqMethod.`$`, req.url.path])
  
  if req.url.path == "/metrics":
    await req.respond(Http200, registry.exportPrometheus())
  else:
    await req.respond(Http200, "Hello, World!")

# Set up HTTP server
var server = newAsyncHttpServer()
waitFor server.serve(Port(8080), handler)
```

## Performance Considerations

- Metrics collection has minimal overhead
- Use sampling for high-frequency operations
- Consider metric cardinality (number of label combinations)
- Pre-allocate label arrays when possible
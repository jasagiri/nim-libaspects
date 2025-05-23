## Logging with Metrics Integration Example
##
## This example demonstrates how to use the logging-metrics integration
## to automatically collect metrics from log events.

import std/[json, times, strformat, os]
import nim_libaspects/[logging, metrics, logging_metrics]

proc main() =
  echo "Logging with Metrics Integration Example"
  echo "=" * 40

  # Create a metrics registry
  let registry = newMetricsRegistry()

  # Create a metrics logger with default configuration
  let logger = newMetricsLogger("example_app", registry)

  # Basic logging with automatic metrics
  echo "\n1. Basic logging with automatic metrics:"
  logger.info("Application started")
  logger.debug("Debug information")
  logger.warning("This is a warning")
  logger.error("An error occurred")

  # Log with performance metrics
  echo "\n2. Performance metrics:"
  logger.info("Request processed", %*{
    "endpoint": "/api/users",
    "method": "GET",
    "duration_ms": 145.5,
    "response_time_ms": 120.0,
    "status_code": 200
  })

  # Log errors with additional context
  echo "\n3. Error tracking:"
  logger.error("Database connection failed", %*{
    "error_type": "connection_timeout",
    "database": "postgres",
    "retry_count": 3,
    "duration_ms": 5000
  })

  # Use spans for operation tracking
  echo "\n4. Span-based tracking:"
  let span = logger.startSpan("process_order")
  
  # Simulate some work
  sleep(50)
  
  span.logger.info("Order validated", %*{
    "order_id": "12345",
    "items": 3,
    "total": 99.99
  })
  
  sleep(30)
  
  span.logger.info("Payment processed", %*{
    "payment_method": "credit_card",
    "transaction_id": "ABC123"
  })
  
  let duration = span.finish()
  echo &"  Span duration: {duration:.2f}ms"

  # Custom metrics configuration
  echo "\n5. Custom metrics extraction:"
  var config = defaultMetricsConfig()
  config.extractors = @[
    MetricsExtractor(
      pattern: ".*payment.*",
      histograms: @["amount", "processing_time"],
      counters: @["payment_method", "currency"]
    ),
    MetricsExtractor(
      pattern: ".*user.*",
      counters: @["action", "role"],
      gauges: @["active_sessions"]
    )
  ]
  
  let customLogger = newMetricsLogger("custom_app", registry, config)
  
  customLogger.info("payment processed", %*{
    "amount": 150.00,
    "processing_time": 45.5,
    "payment_method": "paypal",
    "currency": "USD",
    "user_id": "USER123"
  })
  
  customLogger.info("user logged in", %*{
    "action": "login",
    "role": "admin",
    "active_sessions": 42,
    "ip": "192.168.1.1"
  })

  # Module-specific logging
  echo "\n6. Module-specific metrics:"
  let apiLogger = newMetricsLogger("api", registry)
  let dbLogger = newMetricsLogger("database", registry)
  
  apiLogger.info("API request", %*{"endpoint": "/health"})
  dbLogger.info("Query executed", %*{"query": "SELECT COUNT(*) FROM users"})
  apiLogger.error("API error", %*{"error": "Invalid token"})

  # Display collected metrics
  echo "\n7. Collected metrics summary:"
  let metrics = registry.getAllMetrics()
  
  for name, metric in metrics:
    case metric.kind
    of mtCounter:
      echo &"  Counter {name}: {metric.counter.get(@[])}"
    of mtGauge:
      echo &"  Gauge {name}: {metric.gauge.get(@[])}"
    of mtHistogram:
      let stats = metric.histogram.getStatistics()
      echo &"  Histogram {name}: count={stats.count}, sum={stats.sum:.2f}, mean={stats.mean:.2f}"
    of mtTimer:
      echo &"  Timer {name}: {metric.timer.count(@[])} calls"
    else:
      echo &"  {name}: {metric.kind}"

  # Export metrics in different formats
  echo "\n8. Export formats:"
  
  # JSON export
  let jsonExport = registry.exportMetrics(MetricsFormat.Json)
  echo "\nJSON format:"
  echo jsonExport.pretty()
  
  # Prometheus export
  echo "\nPrometheus format:"
  let promExport = registry.exportMetrics(MetricsFormat.Prometheus)
  echo promExport
  
  # Graphite export
  echo "\nGraphite format:"
  let graphiteExport = registry.exportMetrics(MetricsFormat.Graphite)
  echo graphiteExport

  # Performance testing
  echo "\n9. Performance test:"
  let perfLogger = newMetricsLogger("performance", registry)
  
  let startTime = epochTime()
  for i in 0..999:
    perfLogger.info(&"Event {i}", %*{
      "event_id": i,
      "processing_time": float(i mod 100),
      "category": &"cat_{i mod 5}"
    })
  let endTime = epochTime()
  
  echo &"  Logged 1000 events with metrics in {(endTime - startTime) * 1000:.2f}ms"
  
  # Show final summary
  echo "\n10. Final metrics summary:"
  let summary = registry.getSummary()
  echo summary.pretty()

when isMainModule:
  main()
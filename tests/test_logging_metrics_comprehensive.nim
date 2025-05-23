## tests/test_logging_metrics_comprehensive.nim
## 包括的なロギング・メトリクス統合テスト

import std/[unittest, json, times, tables, options, os, strformat]
import nim_libaspects/[logging, metrics, logging_metrics]

suite "Logging Metrics Integration - Comprehensive":

  test "Log level metrics tracking":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("test", registry)
    
    # Log at different levels
    logger.debug("Debug message")
    logger.info("Info message")
    logger.warning("Warning message")
    logger.error("Error message")
    
    # Check level-specific counters
    let metrics = registry.getAllMetrics()
    check "logs_total" in metrics
    check "logs_debug_total" in metrics
    check "logs_info_total" in metrics
    check "logs_warning_total" in metrics
    check "logs_error_total" in metrics
    
    # Verify counter values
    let logsTotal = metrics["logs_total"].counter
    let debugTotal = metrics["logs_debug_total"].counter
    let infoTotal = metrics["logs_info_total"].counter
    check logsTotal.get(@[]) == 4.0
    check debugTotal.get(@[]) == 1.0
    check infoTotal.get(@[]) == 1.0

  test "Module-based metrics":
    let registry = newMetricsRegistry()
    let logger1 = newMetricsLogger("module1", registry)
    let logger2 = newMetricsLogger("module2", registry)
    
    # Log from different modules
    logger1.info("Message from module1")
    logger2.info("Message from module2")
    logger1.error("Error from module1")
    
    # Check module-specific counters are created
    let metrics = registry.getAllMetrics()
    check "module1_logs_total" in metrics
    check "module2_logs_total" in metrics
    check "module1_errors_total" in metrics

  test "Performance metrics extraction":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("perf", registry)
    
    # Log with performance data
    logger.info("Request processed", %*{
      "duration_ms": 123.45,
      "response_time_ms": 100.0,
      "processing_time_ms": 23.45,
      "endpoint": "/api/users",
      "method": "GET"
    })
    
    # Check histograms were created
    let metrics = registry.getAllMetrics()
    check "duration_ms" in metrics
    check "response_time_ms" in metrics
    check "processing_time_ms" in metrics
    
    # Verify histogram data
    let durationHist = metrics["duration_ms"].histogram
    let stats = durationHist.getStatistics()
    check stats.count == 1
    check stats.sum == 123.45

  test "Error metrics extraction":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("errors", registry)
    
    # Log various errors
    logger.error("Database connection failed", %*{
      "error_type": "connection_timeout",
      "database": "postgres",
      "retry_count": 3
    })
    
    logger.error("API call failed", %*{
      "error_type": "http_error",
      "status_code": 500,
      "service": "user-service"
    })
    
    # Check error counters
    let metrics = registry.getAllMetrics()
    check "errors_total" in metrics
    check "errors_error_type_total" in metrics
    
    # Verify counter labels
    let errorTypeCounter = metrics["errors_error_type_total"].counter
    check errorTypeCounter.get(@["connection_timeout"]) == 1.0
    check errorTypeCounter.get(@["http_error"]) == 1.0

  test "Custom metrics extractors":
    let registry = newMetricsRegistry()
    
    # Configure custom extractors
    var config = defaultMetricsConfig()
    config.extractors = @[
      MetricsExtractor(
        pattern: ".*payment.*",
        histograms: @["amount", "processing_time"],
        counters: @["payment_method", "currency"]
      ),
      MetricsExtractor(
        pattern: ".*auth.*",
        counters: @["auth_type", "success"],
        gauges: @["active_sessions"]
      )
    ]
    
    let logger = newMetricsLogger("business", registry, config)
    
    # Log payment event
    logger.info("payment processed", %*{
      "amount": 99.99,
      "processing_time": 45.5,
      "payment_method": "credit_card",
      "currency": "USD",
      "customer_id": "12345"
    })
    
    # Log auth event
    logger.info("auth completed", %*{
      "auth_type": "oauth",
      "success": "true",
      "active_sessions": 42,
      "user_id": "67890"
    })
    
    # Check extracted metrics
    let metrics = registry.getAllMetrics()
    check "amount" in metrics
    check "processing_time" in metrics
    check "payment_method_total" in metrics
    check "currency_total" in metrics
    check "auth_type_total" in metrics
    check "active_sessions" in metrics

  test "Span tracing metrics":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("tracing", registry)
    
    # Start a span
    let span = logger.startSpan("database_query")
    sleep(5)  # Simulate work
    
    # Log within span
    span.logger.info("Executing query", %*{
      "query": "SELECT * FROM users",
      "table": "users"
    })
    
    # End span
    let duration = span.finish()
    
    # Check span metrics
    let metrics = registry.getAllMetrics()
    check "span_duration_ms" in metrics
    check "span_database_query_duration_ms" in metrics
    
    # Verify duration was recorded
    let spanHist = metrics["span_duration_ms"].histogram
    let stats = spanHist.getStatistics()
    check stats.count == 1
    check stats.sum >= 5.0  # At least 5ms

  test "Metric aggregation and filtering":
    let registry = newMetricsRegistry()
    
    # Configure with filters
    var config = defaultMetricsConfig()
    config.enableAutoMetrics = true
    config.enableModuleMetrics = true
    config.moduleFilter = @["api", "database"]
    
    let apiLogger = newMetricsLogger("api", registry, config)
    let dbLogger = newMetricsLogger("database", registry, config)
    let cacheLogger = newMetricsLogger("cache", registry, config)
    
    # Log from different modules
    apiLogger.info("API request")
    dbLogger.info("Query executed")
    cacheLogger.info("Cache hit")  # Should be filtered out
    
    # Check only allowed modules have metrics
    let metrics = registry.getAllMetrics()
    check "api_logs_total" in metrics
    check "database_logs_total" in metrics
    check "cache_logs_total" notin metrics

  test "Metrics export formats":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("export", registry)
    
    # Generate some metrics
    logger.info("Test message")
    logger.error("Test error")
    logger.info("Request", %*{"duration_ms": 50.0})
    
    # Export in different formats
    let jsonExport = registry.exportMetrics(MetricsFormat.Json)
    let prometheusExport = registry.exportMetrics(MetricsFormat.Prometheus)
    let graphiteExport = registry.exportMetrics(MetricsFormat.Graphite)
    
    # Verify exports contain expected data
    check jsonExport["logs_total"]["value"].getFloat() == 2.0
    check "logs_total 2" in prometheusExport
    check "export.logs_total 2" in graphiteExport

  test "Thread-safe logging with metrics":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("concurrent", registry)
    
    var threads: array[4, Thread[void]]
    
    proc logWorker() {.thread.} =
      for i in 0..9:
        logger.info(&"Message {i}", %*{"thread_id": getThreadId()})
        sleep(1)
    
    # Start threads
    for i in 0..3:
      createThread(threads[i], logWorker)
    
    # Wait for completion
    joinThreads(threads)
    
    # Verify all messages were counted
    let metrics = registry.getAllMetrics()
    let logsTotal = metrics["logs_total"].counter
    check logsTotal.get(@[]) == 40.0  # 4 threads * 10 messages

  test "Memory efficiency with large datasets":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("memory", registry)
    
    # Log many events with metrics
    for i in 0..999:
      logger.info(&"Event {i}", %*{
        "event_id": i,
        "processing_time": float(i mod 100),
        "category": &"cat_{i mod 10}"
      })
    
    # Check metrics were aggregated efficiently
    let metrics = registry.getAllMetrics()
    check "logs_total" in metrics
    check "processing_time" in metrics
    
    # Verify histogram buckets
    let procTimeHist = metrics["processing_time"].histogram
    let stats = procTimeHist.getStatistics()
    check stats.count == 1000
    
    # Category counters should only have 10 unique values
    let catCounter = metrics["category_total"].counter
    var uniqueCategories = 0
    for i in 0..9:
      if catCounter.get(@[&"cat_{i}"]) > 0:
        uniqueCategories.inc()
    check uniqueCategories == 10

  test "Error handling and recovery":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("errors", registry)
    
    # Test with invalid metric names
    logger.info("Test", %*{
      "invalid-metric-name!": 42,
      "valid_metric": 100
    })
    
    # Should only create valid metric
    let metrics = registry.getAllMetrics()
    check "valid_metric" in metrics
    check "invalid-metric-name!" notin metrics
    
    # Test with nil/empty data
    logger.info("Empty data", newJNull())
    logger.info("No data")
    
    # Should still count logs
    let logsTotal = metrics["logs_total"].counter
    check logsTotal.get(@[]) >= 3.0
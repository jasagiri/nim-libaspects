## tests/test_logging_metrics_simple.nim
## シンプルなロギング・メトリクス統合テスト

import std/[unittest, json, times, tables, os]
import nim_libaspects/[logging, metrics, logging_metrics]

suite "Logging Metrics Integration - Simple":
  
  test "Create metrics logger":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("test", registry)
    
    check logger.logger.module == "test"
    check logger.registry == registry
  
  test "Log with auto metrics":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("test", registry)
    
    # Log a message
    logger.info("Test message")
    
    # Check that log level metrics were created
    let metrics = registry.getAllMetrics()
    check "logs_total" in metrics
  
  test "Log with performance metrics":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("test", registry)
    
    # Log with duration
    logger.info("Request completed", %*{
      "duration_ms": 150,
      "endpoint": "/api/test"
    })
    
    # Check histogram was created
    let metrics = registry.getAllMetrics()
    check metrics.hasKey("request_duration_ms")
  
  test "Log errors with metrics":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("test", registry)
    
    # Log an error
    logger.error("Something failed", %*{
      "error": "timeout",
      "retry_count": 3
    })
    
    # Check error counter
    let metrics = registry.getAllMetrics()
    check metrics.hasKey("errors_total")
  
  test "Custom metrics extraction":
    let registry = newMetricsRegistry()
    
    # Define custom extractors
    var config = defaultMetricsConfig()
    config.extractors = @[
      MetricsExtractor(
        pattern: ".*request.*",
        histograms: @["response_time_ms"],
        counters: @["status"]
      )
    ]
    
    let logger = newMetricsLogger("test", registry, config)
    
    # Log matching pattern
    logger.info("request completed", %*{
      "response_time_ms": 200,
      "status": "200"
    })
    
    # Check metrics were extracted
    let metrics = registry.getAllMetrics()
    check metrics.hasKey("response_time_ms")
  
  test "Timer helper":
    let timer = startTimer()
    sleep(10)  # Sleep for 10ms
    let elapsed = timer.elapsed()
    
    check elapsed.inMilliseconds >= 10
  
  test "Metrics summary":
    let registry = newMetricsRegistry()
    let logger = newMetricsLogger("test", registry)
    
    # Generate some metrics
    logger.info("Test 1")
    logger.error("Test error")
    logger.info("Test 2", %*{"duration_ms": 100})
    
    # Get summary
    let summary = registry.getSummary()
    check summary.kind == JObject
    check summary.hasKey("counters")
    check summary.hasKey("histograms")
    check summary.hasKey("gauges")
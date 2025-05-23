## BDD Specification for Metrics Collection Framework
##
## Given: A metrics collection system
## When: Various metrics are recorded
## Then: They should be collected, aggregated, and retrievable

import std/[unittest, times, strformat, tables, options, os, strutils]
import nim_libaspects/metrics

suite "Metrics Collection Framework":
  setup:
    let metrics = newMetricsRegistry()
  
  test "Counter metrics - increment and get value":
    ## Given: A counter metric
    let counter = metrics.counter("api.requests")
    
    ## When: Incrementing the counter
    counter.inc()
    counter.inc()
    counter.inc(@[], 5)
    
    ## Then: The counter value should be correct
    check counter.value == 7
  
  test "Counter metrics - with labels":
    ## Given: A counter with labels
    let httpRequests = metrics.counter("http.requests", @["method", "status"])
    
    ## When: Incrementing with different label values
    httpRequests.inc(@["GET", "200"])
    httpRequests.inc(@["GET", "200"]) 
    httpRequests.inc(@["POST", "201"])
    httpRequests.inc(@["GET", "404"])
    
    ## Then: Each labeled metric should have its own value
    check httpRequests.value(@["GET", "200"]) == 2
    check httpRequests.value(@["POST", "201"]) == 1
    check httpRequests.value(@["GET", "404"]) == 1
  
  test "Gauge metrics - set and get value":
    ## Given: A gauge metric
    let memoryUsage = metrics.gauge("memory.usage")
    
    ## When: Setting gauge values
    memoryUsage.set(100.5)
    memoryUsage.inc(10.5)
    memoryUsage.dec(5.0)
    
    ## Then: The gauge value should be correct
    check memoryUsage.value == 106.0
  
  test "Histogram metrics - record observations":
    ## Given: A histogram for response times
    let responseTime = metrics.histogram("response.time", buckets = @[0.1, 0.5, 1.0, 5.0])
    
    ## When: Recording various response times
    responseTime.observe(0.05)
    responseTime.observe(0.2)
    responseTime.observe(0.7)
    responseTime.observe(1.5)
    responseTime.observe(0.3)
    
    ## Then: The histogram should track distribution
    let stats = responseTime.getStatistics()
    check stats.count == 5
    check stats.sum > 0
    check stats.mean > 0
    check stats.buckets[0.1] == 1  # One value <= 0.1
    check stats.buckets[0.5] == 3  # Three values <= 0.5
    check stats.buckets[1.0] == 4  # Four values <= 1.0
  
  test "Summary metrics - track quantiles":
    ## Given: A summary metric
    let processingTime = metrics.summary("processing.time")
    
    ## When: Recording multiple values
    for i in 1..100:
      processingTime.observe(float(i))
    
    ## Then: Quantiles should be calculated
    let quantiles = processingTime.getQuantiles(@[0.5, 0.9, 0.99])
    check quantiles[0.5] == 50.0 or quantiles[0.5] == 51.0  # Median
    check quantiles[0.9] >= 90.0 and quantiles[0.9] <= 91.0
    check quantiles[0.99] >= 99.0 and quantiles[0.99] <= 100.0
  
  test "Timer metrics - measure duration":
    ## Given: A timer metric
    let requestDuration = metrics.timer("request.duration")
    
    ## When: Measuring a code block
    let timer = requestDuration.start()
    # Simulate some work
    sleep(10)
    let duration = timer.stop()
    
    ## Then: Duration should be recorded
    check duration > 0
    check requestDuration.count == 1
    check requestDuration.totalTime > 0
  
  test "Metrics registry - get all metrics":
    ## Given: Multiple metrics registered
    let cpu = metrics.gauge("cpu.usage")
    let requests = metrics.counter("requests.total")
    let latency = metrics.histogram("request.latency")
    
    ## When: Getting all metrics
    let allMetrics = metrics.getAllMetrics()
    
    ## Then: All metrics should be retrievable
    check allMetrics.len == 3
    check "cpu.usage" in allMetrics
    check "requests.total" in allMetrics
    check "request.latency" in allMetrics
  
  test "Metrics export - Prometheus format":
    ## Given: Metrics with values
    let requests = metrics.counter("http_requests_total", @["method"])
    requests.inc(@["GET"])
    requests.inc(@["POST"])
    
    let memory = metrics.gauge("memory_usage_bytes")
    memory.set(1024.0)
    
    ## When: Exporting to Prometheus format
    let output = metrics.exportPrometheus()
    
    ## Then: Output should be in Prometheus format
    check "http_requests_total{method=\"GET\"} 1" in output
    check "http_requests_total{method=\"POST\"} 1" in output
    check "memory_usage_bytes 1024" in output
  
  test "Metrics reporter - periodic reporting":
    ## Given: A metrics reporter
    var reportCount = 0
    let reporter = newMetricsReporter(metrics) do (m: MetricsRegistry):
      reportCount.inc()
    
    ## When: Starting the reporter
    reporter.start(interval = 100)  # 100ms interval
    sleep(250)  # Wait for at least 2 reports
    reporter.stop()
    
    ## Then: Reporter should have run multiple times
    check reportCount >= 2
  
  test "Metrics middleware - automatic timing":
    ## Given: A function wrapped with metrics
    var callCount = 0
    
    proc myFunction() =
      let timer = metrics.timer("function.duration")
      let ctx = timer.start()
      callCount.inc()
      sleep(5)
      discard ctx.stop()
    
    ## When: Calling the function
    myFunction()
    myFunction()
    
    ## Then: Timing metrics should be recorded
    let timer = metrics.getTimer("function.duration")
    check timer.count == 2
    check timer.totalTime > 0
    check callCount == 2
## Example usage of the metrics module
##
## This example demonstrates various metrics types and their usage patterns

import std/[os, times, strformat, random, tables, strutils]
import ../src/nim_libaspects/metrics

proc simulateWebApplication() =
  # Create metrics registry
  let registry = newMetricsRegistry()
  
  # Define metrics
  let httpRequests = registry.counter("http_requests_total", @["method", "status", "path"])
  let activeConnections = registry.gauge("active_connections")
  let requestDuration = registry.histogram("request_duration_seconds", @["method", "path"],
                                         buckets = @[0.01, 0.05, 0.1, 0.5, 1.0, 5.0])
  let responseSize = registry.summary("response_size_bytes", @["path"])
  let dbQueryTime = registry.timer("db_query_duration_seconds", @["query_type"])
  
  # Set up metrics reporter
  let reporter = newMetricsReporter(registry) do (r: MetricsRegistry):
    echo "\n=== Metrics Report ==="
    echo r.exportPrometheus()
    echo "==================\n"
  
  reporter.start(interval = 5000)  # Report every 5 seconds
  
  # Simulate application behavior
  var connections = 0
  
  for minute in 1..2:  # Run for 2 minutes
    echo &"Minute {minute}..."
    
    for _ in 1..30:  # 30 requests per minute
      # Simulate incoming request
      let methods = @["GET", "POST", "PUT", "DELETE"]
      let paths = @["/api/users", "/api/orders", "/api/products", "/health"]
      let statuses = @["200", "201", "404", "500"]
      
      let httpMethod = sample(methods)
      let httpPath = sample(paths)
      let httpStatus = if rand(1.0) > 0.1: sample(@["200", "201"]) else: sample(@["404", "500"])
      
      # Track request
      httpRequests.inc(@[httpMethod, httpStatus, httpPath])
      
      # Simulate connection
      connections.inc()
      activeConnections.set(float(connections))
      
      # Measure request duration
      let duration = rand(0.001..2.0)
      requestDuration.observe(duration, @[httpMethod, httpPath])
      
      # Track response size
      let size = rand(100.0..10000.0)
      responseSize.observe(size, @[httpPath])
      
      # Simulate database query
      let queryType = sample(@["select", "insert", "update", "delete"])
      let queryTimer = dbQueryTime.start(@[queryType])
      sleep(int(rand(1.0..50.0)))  # Simulate query time
      discard queryTimer.stop()
      
      # Close connection after processing
      connections.dec()
      activeConnections.set(float(connections))
      
      sleep(100)  # 100ms between requests
    
    echo &"Completed minute {minute}, current connections: {connections}"
  
  # Stop reporter
  reporter.stop()
  
  # Final metrics summary
  echo "\n=== Final Metrics Summary ==="
  
  # Show request counts by status
  echo "\nRequest counts by status:"
  # Since values is private, we'll use the Prometheus export to see the metrics
  let exportData = registry.exportPrometheus()
  for line in exportData.splitLines():
    if line.startsWith("http_requests_total") and line.len > 0:
      echo &"  {line}"
  
  # Show duration statistics
  echo "\nRequest duration statistics:"
  let stats = requestDuration.getStatistics(@[])  # Use empty labels to get overall stats
  echo &"  Count: {stats.count}"
  echo &"  Mean: {stats.mean:.3f}s"
  echo &"  Percentiles:"
  for bucket, count in stats.buckets:
    let percentage = if stats.count > 0: (count.float / stats.count.float * 100) else: 0.0
    echo &"    <= {bucket}s: {count} ({percentage:.1f}%)"
  
  # Show database query times
  echo "\nDatabase query times:"
  # Since durations is private, we'll show a summary
  echo "  (See metrics export for detailed timing information)"

proc demonstrateMetricsAnnotation() =
  ## Demonstrate the metricsTimer template
  
  proc slowOperation() =
    metricsTimer("slow_operation_duration"):
      echo "Starting slow operation..."
      sleep(500)
      echo "Slow operation completed"
  
  proc fastOperation() =
    metricsTimer("fast_operation_duration"):
      echo "Fast operation"
      sleep(10)
  
  # Run operations
  slowOperation()
  fastOperation()
  fastOperation()
  
  # Check the metrics
  let slowTimer = defaultMetricsRegistry.getTimer("slow_operation_duration")
  let fastTimer = defaultMetricsRegistry.getTimer("fast_operation_duration")
  
  echo &"\nSlow operation: {slowTimer.count} calls, total {slowTimer.totalTime:.3f}s, avg {slowTimer.averageTime:.3f}s"
  echo &"Fast operation: {fastTimer.count} calls, total {fastTimer.totalTime:.3f}s, avg {fastTimer.averageTime:.3f}s"

when isMainModule:
  randomize()
  
  echo "=== Metrics Module Example ==="
  echo "1. Simulating web application metrics..."
  simulateWebApplication()
  
  echo "\n2. Demonstrating metrics annotation..."
  demonstrateMetricsAnnotation()
  
  echo "\nExample completed!"
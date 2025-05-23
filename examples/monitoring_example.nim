## Example of using the monitoring module for comprehensive system monitoring

import std/[asyncdispatch, times, json, strformat, os, random]
import nim_libaspects/monitoring

# Simulate system metrics
proc getMemoryUsage(): float = 65.5 + rand(20.0)
proc getCpuUsage(): float = 45.0 + rand(30.0)
proc getDiskUsage(): float = 70.0 + rand(15.0)
proc getQueueSize(): int = 100 + rand(500)

# Simulate service checks
var dbConnected = true
var apiResponsive = true

proc main() {.async.} =
  echo "Starting monitoring example..."
  
  # Create monitoring system
  let monitor = newMonitoringSystem()
  
  # 1. Set up health checks
  echo "\n1. Setting up health checks..."
  
  # Database health check
  let dbCheck = newHealthCheck("database", "Check database connectivity")
  dbCheck.checkFn = proc(): Future[HealthCheckResult] {.async.} =
    await sleepAsync(100)  # Simulate check delay
    if dbConnected:
      return HealthCheckResult(
        status: HealthStatus.Healthy,
        message: "Database is connected",
        metadata: %*{
          "version": "PostgreSQL 14.5",
          "connections": 42
        }
      )
    else:
      return HealthCheckResult(
        status: HealthStatus.Unhealthy,
        message: "Database connection failed",
        metadata: %*{"error": "Connection timeout"}
      )
  
  monitor.registerHealthCheck(dbCheck)
  
  # API health check
  let apiCheck = newHealthCheck("api", "Check API responsiveness")
  apiCheck.checkFn = proc(): Future[HealthCheckResult] {.async.} =
    await sleepAsync(50)  # Simulate API call
    if apiResponsive:
      return HealthCheckResult(
        status: HealthStatus.Healthy,
        message: "API is responding",
        metadata: %*{
          "response_time_ms": 50,
          "version": "1.2.3"
        }
      )
    else:
      return HealthCheckResult(
        status: HealthStatus.Degraded,
        message: "API is slow",
        metadata: %*{"response_time_ms": 2000}
      )
  
  monitor.registerHealthCheck(apiCheck)
  
  # 2. Set up resource monitoring
  echo "\n2. Setting up resource monitoring..."
  
  # Memory monitor
  let memoryMonitor = newResourceMonitor("memory", ResourceType.Memory)
  memoryMonitor.collectFn = proc(): ResourceMetrics =
    return ResourceMetrics(
      name: "memory",
      value: getMemoryUsage(),
      unit: "percent",
      timestamp: getTime(),
      metadata: %*{
        "total": "16GB",
        "available": "5.5GB"
      }
    )
  
  monitor.registerResourceMonitor(memoryMonitor)
  
  # CPU monitor
  let cpuMonitor = newResourceMonitor("cpu", ResourceType.CPU)
  cpuMonitor.collectFn = proc(): ResourceMetrics =
    return ResourceMetrics(
      name: "cpu",
      value: getCpuUsage(),
      unit: "percent",
      timestamp: getTime(),
      metadata: %*{
        "cores": 8,
        "model": "Intel Core i7"
      }
    )
  
  monitor.registerResourceMonitor(cpuMonitor)
  
  # Disk monitor
  let diskMonitor = newResourceMonitor("disk", ResourceType.Disk)
  diskMonitor.collectFn = proc(): ResourceMetrics =
    return ResourceMetrics(
      name: "disk",
      value: getDiskUsage(),
      unit: "percent",
      timestamp: getTime(),
      metadata: %*{
        "total": "500GB",
        "type": "SSD"
      }
    )
  
  monitor.registerResourceMonitor(diskMonitor)
  
  # Custom monitor for job queue
  let queueMonitor = newResourceMonitor("job_queue", ResourceType.Custom)
  queueMonitor.collectFn = proc(): ResourceMetrics =
    return ResourceMetrics(
      name: "job_queue",
      value: float(getQueueSize()),
      unit: "items",
      timestamp: getTime(),
      metadata: %*{
        "workers": 4,
        "processing_rate": "50/min"
      }
    )
  
  monitor.registerResourceMonitor(queueMonitor)
  
  # 3. Set up alert rules
  echo "\n3. Setting up alert rules..."
  
  # High memory alert
  let highMemoryRule = newAlertRule(
    name = "high_memory",
    severity = AlertSeverity.Warning,
    condition = AlertCondition(
      metric: "memory",
      operator: ComparisonOperator.GreaterThan,
      threshold: 80.0
    )
  )
  
  monitor.registerAlertRule(highMemoryRule)
  
  # Critical CPU alert
  let criticalCpuRule = newAlertRule(
    name = "critical_cpu",
    severity = AlertSeverity.Critical,
    condition = AlertCondition(
      metric: "cpu",
      operator: ComparisonOperator.GreaterThan,
      threshold: 90.0
    )
  )
  
  monitor.registerAlertRule(criticalCpuRule)
  
  # Queue backlog alert
  let queueBacklogRule = newAlertRule(
    name = "queue_backlog",
    severity = AlertSeverity.Info,
    condition = AlertCondition(
      metric: "job_queue",
      operator: ComparisonOperator.GreaterThan,
      threshold: 500.0
    )
  )
  
  monitor.registerAlertRule(queueBacklogRule)
  
  # 4. Set up alert handler
  echo "\n4. Setting up alert handler..."
  
  monitor.onAlert = proc(alert: Alert) {.gcsafe.} =
    echo &"\n🚨 ALERT: {alert.rule}"
    echo &"   Severity: {alert.severity}"
    echo &"   Message: {alert.message}"
    echo &"   Metadata: {alert.metadata}"
    
    # In real app: send to notification system
    case alert.severity
    of AlertSeverity.Critical:
      echo "   → Would send PagerDuty alert"
    of AlertSeverity.Warning:
      echo "   → Would send Slack notification"
    of AlertSeverity.Info:
      echo "   → Would log to monitoring system"
  
  # 5. Set up custom metrics
  echo "\n5. Setting up custom metrics..."
  
  let requestCounter = newCustomMetric(
    name = "http_requests",
    description = "Total HTTP requests",
    metricType = MetricType.Counter
  )
  
  monitor.registerCustomMetric(requestCounter)
  
  let errorRate = newCustomMetric(
    name = "error_rate",
    description = "Request error rate",
    metricType = MetricType.Gauge
  )
  
  monitor.registerCustomMetric(errorRate)
  
  # 6. Set up lifecycle hooks
  echo "\n6. Setting up lifecycle hooks..."
  
  monitor.onStart = proc() {.gcsafe.} =
    echo "\n✅ Monitoring system started"
  
  monitor.onStop = proc() {.gcsafe.} =
    echo "\n🛑 Monitoring system stopped"
  
  monitor.onHealthCheckComplete = proc(name: string, result: HealthCheckResult) {.gcsafe.} =
    echo &"\nHealth check completed: {name} - {result.status}"
  
  # 7. Start monitoring
  echo "\n7. Starting monitoring system..."
  monitor.startMonitoring(interval = initDuration(seconds = 5))
  
  # 8. Simulate application activity
  echo "\n8. Simulating application activity..."
  
  # Update application state
  monitor.appState.setState("server", "running")
  monitor.appState.setState("maintenance_mode", "false")
  
  # Simulate requests and errors
  for i in 1..10:
    await sleepAsync(1000)
    
    # Update custom metrics
    monitor.recordMetric("http_requests", 10.0)  # 10 requests
    monitor.recordMetric("error_rate", float(rand(5)))  # 0-5% error rate
    
    # Occasionally simulate issues
    if i == 5:
      echo "\n⚠️  Simulating high memory usage..."
      let highMemMonitor = newResourceMonitor("memory", ResourceType.Memory)
      highMemMonitor.collectFn = proc(): ResourceMetrics =
        return ResourceMetrics(
          name: "memory",
          value: 85.0,  # Above threshold
          unit: "percent",
          timestamp: getTime()
        )
      monitor.registerResourceMonitor(highMemMonitor)
    
    if i == 7:
      echo "\n⚠️  Simulating database failure..."
      dbConnected = false
    
    if i == 9:
      echo "\n✅ Database recovered..."
      dbConnected = true
  
  # 9. Get monitoring summary
  echo "\n9. Getting monitoring summary..."
  let summary = monitor.getSummary()
  echo "Summary:"
  echo pretty(summary)
  
  # 10. Get dashboard data
  echo "\n10. Getting dashboard data..."
  let dashboardData = monitor.getDashboardData()
  echo "Dashboard Data:"
  echo "  Health Checks: ", dashboardData["health_checks"]
  echo "  Resources: ", dashboardData["resources"]
  echo "  Recent Alerts: ", dashboardData["alerts"]
  echo "  App State: ", dashboardData["application_state"]
  
  # 11. Save monitoring state
  echo "\n11. Saving monitoring state..."
  let state = monitor.saveState()
  writeFile("monitoring_state.json", pretty(state))
  echo "State saved to monitoring_state.json"
  
  # 12. Stop monitoring
  echo "\n12. Stopping monitoring..."
  monitor.stopMonitoring()
  
  # 13. Display final metrics
  echo "\n13. Final metrics:"
  echo &"  Total HTTP requests: {monitor.getMetricValue(\"http_requests\")}"
  echo &"  Last error rate: {monitor.getMetricValue(\"error_rate\")}%"
  
  echo "\nMonitoring example completed!"

when isMainModule:
  randomize()
  waitFor main()
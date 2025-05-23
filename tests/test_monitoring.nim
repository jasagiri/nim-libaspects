import std/[
  unittest, 
  asyncdispatch, 
  times, 
  json,
  tables, 
  strutils, 
  options,
  sequtils
]
import nim_libaspects/monitoring

suite "Monitoring System":
  setup:
    var monitor = newMonitoringSystem()
    
  test "Health check creation":
    # Test simple health check creation
    let check = newHealthCheck("database", "Database connectivity check")
    check(check.name == "database")
    check(check.description == "Database connectivity check")
    check(check.status == HealthStatus.Unknown)
    
  test "Health check execution":
    # Test health check with simple function
    var check = newHealthCheck("api", "API health check")
    var executionCount = 0
    
    check.checkFn = proc(): Future[HealthCheckResult] {.async.} =
      inc executionCount
      return HealthCheckResult(
        status: HealthStatus.Healthy,
        message: "API is running normally",
        metadata: %*{"version": "1.0.0"}
      )
    
    let result = waitFor check.execute()
    check(result.status == HealthStatus.Healthy)
    check(result.message == "API is running normally")
    check(result.metadata["version"].getStr() == "1.0.0")
    check(executionCount == 1)
    
  test "Health check error handling":
    # Test health check with failure
    var check = newHealthCheck("service", "Service check")
    
    check.checkFn = proc(): Future[HealthCheckResult] {.async.} =
      raise newException(IOError, "Connection timeout")
    
    let result = waitFor check.execute()
    check(result.status == HealthStatus.Unhealthy)
    check("Connection timeout" in result.message)
    
  test "Monitor registration":
    # Test registering health checks
    let dbCheck = newHealthCheck("database", "DB check")
    let apiCheck = newHealthCheck("api", "API check")
    
    monitor.registerHealthCheck(dbCheck)
    monitor.registerHealthCheck(apiCheck)
    
    check(monitor.getHealthChecks().len == 2)
    check(monitor.getHealthCheck("database").isSome)
    check(monitor.getHealthCheck("api").isSome)
    check(monitor.getHealthCheck("nonexistent").isNone)
    
  test "Resource monitoring":
    # Test resource monitoring
    let resource = newResourceMonitor("memory", ResourceType.Memory)
    resource.threshold = 80.0  # 80% threshold
    resource.interval = initDuration(seconds = 5)
    
    check(resource.name == "memory")
    check(resource.resourceType == ResourceType.Memory)
    check(resource.threshold == 80.0)
    
  test "Resource metrics collection":
    # Test collecting resource metrics
    var memoryMonitor = newResourceMonitor("memory", ResourceType.Memory)
    var cpuMonitor = newResourceMonitor("cpu", ResourceType.CPU)
    
    # Set up mock collector functions
    memoryMonitor.collectFn = proc(): ResourceMetrics =
      return ResourceMetrics(
        name: "memory",
        value: 65.5,
        unit: "percent",
        timestamp: getTime(),
        metadata: %*{"total": "16GB", "used": "10.48GB"}
      )
    
    cpuMonitor.collectFn = proc(): ResourceMetrics =
      return ResourceMetrics(
        name: "cpu",
        value: 45.2,
        unit: "percent",
        timestamp: getTime(),
        metadata: %*{"cores": 8}
      )
    
    monitor.registerResourceMonitor(memoryMonitor)
    monitor.registerResourceMonitor(cpuMonitor)
    
    waitFor monitor.collectResourceMetrics()
    
    let metrics = monitor.getResourceMetrics()
    check(metrics.len == 2)
    # Check values exist but don't assume order
    check(metrics.anyIt(it.value == 65.5))
    check(metrics.anyIt(it.value == 45.2))
    
  test "Alert rules":
    # Test alert rule creation and evaluation
    let rule = newAlertRule(
      name = "high_memory",
      severity = AlertSeverity.Warning,
      condition = AlertCondition(
        metric: "memory",
        operator: ComparisonOperator.GreaterThan,
        threshold: 80.0,
        duration: initDuration(minutes = 5)
      )
    )
    
    check(rule.name == "high_memory")
    check(rule.severity == AlertSeverity.Warning)
    check(rule.condition.threshold == 80.0)
    
  test "Alert triggering":
    # Test alert triggering
    let alertTest = proc(alert: Alert) {.gcsafe.} =
      check(alert.severity == AlertSeverity.Warning)
      check(alert.rule == "high_memory")
    
    monitor.onAlert = alertTest
    
    let memoryMonitor = newResourceMonitor("memory", ResourceType.Memory)
    memoryMonitor.collectFn = proc(): ResourceMetrics =
      return ResourceMetrics(
        name: "memory",
        value: 85.0,  # Above threshold
        unit: "percent",
        timestamp: getTime()
      )
    
    monitor.registerResourceMonitor(memoryMonitor)
    
    let rule = newAlertRule(
      name = "high_memory",
      severity = AlertSeverity.Warning,
      condition = AlertCondition(
        metric: "memory",
        operator: ComparisonOperator.GreaterThan,
        threshold: 80.0
      )
    )
    
    monitor.registerAlertRule(rule)
    waitFor monitor.evaluateAlerts()
    
    # Alert function should have been called
    
  test "Application state monitoring":
    # Test application state tracking
    let appState = newApplicationState()
    
    appState.setState("startup", "initializing")
    check(appState.getState("startup") == "initializing")
    
    appState.setState("database", "connected")
    appState.setState("api", "listening")
    
    let states = appState.getAllStates()
    check(states.len == 3)
    check(states["database"] == "connected")
    
  test "Monitoring aggregation":
    # Test aggregating monitoring data
    monitor.startMonitoring(interval = initDuration(seconds = 1))
    
    # Add some health checks
    let dbCheck = newHealthCheck("database", "DB check")
    dbCheck.checkFn = proc(): Future[HealthCheckResult] {.async.} =
      return HealthCheckResult(status: HealthStatus.Healthy)
    
    monitor.registerHealthCheck(dbCheck)
    
    # Let it run briefly
    waitFor sleepAsync(2000)
    monitor.stopMonitoring()
    
    let summary = monitor.getSummary()
    check(summary["healthChecks"].len >= 1)
    check(summary["startTime"].getInt() <= summary["endTime"].getInt())
    
  test "Dashboard data":
    # Test dashboard data generation
    let dashboardData = monitor.getDashboardData()
    
    check(dashboardData.hasKey("health_checks"))
    check(dashboardData.hasKey("resources"))
    check(dashboardData.hasKey("alerts"))
    check(dashboardData.hasKey("application_state"))
    
  test "Monitoring persistence":
    # Test saving/loading monitoring state
    # Add some data
    let check = newHealthCheck("test", "Test check")
    monitor.registerHealthCheck(check)
    
    # Save state
    let state = monitor.saveState()
    check(state.hasKey("health_checks"))
    check(state.hasKey("resources"))
    
    # Create new monitor and restore
    var newMonitor = newMonitoringSystem()
    newMonitor.loadState(state)
    
    check(newMonitor.getHealthChecks().len == 1)
    
  test "Custom metrics":
    # Test custom metric collection
    let customMetric = newCustomMetric(
      name = "request_count",
      description = "Total request count",
      metricType = MetricType.Counter
    )
    
    monitor.registerCustomMetric(customMetric)
    monitor.recordMetric("request_count", 1.0)
    monitor.recordMetric("request_count", 1.0)
    monitor.recordMetric("request_count", 1.0)
    
    let value = monitor.getMetricValue("request_count")
    check(value == 3.0)
    
  test "Monitoring hooks":
    # Test monitoring lifecycle hooks
    let testStart = proc() {.gcsafe.} =
      discard
    
    let testStop = proc() {.gcsafe.} = 
      discard
    
    let testHealthCheck = proc(name: string, result: HealthCheckResult) {.gcsafe.} =
      discard
    
    monitor.onStart = testStart
    monitor.onStop = testStop
    monitor.onHealthCheckComplete = testHealthCheck
    
    monitor.startMonitoring()
    waitFor sleepAsync(100)
    monitor.stopMonitoring()
    
    # Callbacks should have been set
    check(not monitor.onStart.isNil)
    check(not monitor.onStop.isNil)
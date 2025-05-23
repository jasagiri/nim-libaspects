# Monitoring Module

The monitoring module provides comprehensive monitoring capabilities including health checks, resource monitoring, alerts, and application state tracking.

## Features

- **Health Checks**: Define and execute health checks for various system components
- **Resource Monitoring**: Monitor CPU, memory, disk, and custom resources
- **Alert Rules**: Define alert rules with thresholds and conditions
- **Application State**: Track and monitor application state changes
- **Dashboard Data**: Generate dashboard-ready monitoring data
- **Custom Metrics**: Define and track custom metrics
- **Lifecycle Hooks**: Hook into monitoring lifecycle events

## Basic Usage

```nim
import nim_libaspects/monitoring

# Create monitoring system
let monitor = newMonitoringSystem()

# Define a health check
let dbCheck = newHealthCheck("database", "Check database connectivity")
dbCheck.checkFn = proc(): Future[HealthCheckResult] {.async.} =
  # Perform health check
  if databaseIsConnected():
    return HealthCheckResult(
      status: HealthStatus.Healthy,
      message: "Database is connected",
      metadata: %*{"version": getDatabaseVersion()}
    )
  else:
    return HealthCheckResult(
      status: HealthStatus.Unhealthy,
      message: "Database connection failed"
    )

monitor.registerHealthCheck(dbCheck)

# Define resource monitoring
let memoryMonitor = newResourceMonitor("memory", ResourceType.Memory)
memoryMonitor.collectFn = proc(): ResourceMetrics =
  return ResourceMetrics(
    name: "memory",
    value: getMemoryUsagePercent(),
    unit: "percent",
    timestamp: getTime(),
    metadata: %*{"total": getTotalMemory()}
  )

monitor.registerResourceMonitor(memoryMonitor)

# Define alert rules
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

# Set up alert handler
monitor.onAlert = proc(alert: Alert) {.gcsafe.} =
  echo "Alert triggered: ", alert.message
  # Send notification, log, etc.

# Start monitoring
monitor.startMonitoring(interval = initDuration(seconds = 30))

# ... application runs ...

# Stop monitoring
monitor.stopMonitoring()
```

## Health Checks

Health checks verify the status of system components:

```nim
let apiCheck = newHealthCheck("api", "API health check")
apiCheck.timeout = initDuration(seconds = 10)

apiCheck.checkFn = proc(): Future[HealthCheckResult] {.async.} =
  let response = await checkApiEndpoint()
  if response.status == 200:
    return HealthCheckResult(
      status: HealthStatus.Healthy,
      message: "API is responsive",
      metadata: %*{"response_time": response.time}
    )
  else:
    return HealthCheckResult(
      status: HealthStatus.Unhealthy,
      message: &"API returned status {response.status}"
    )

# Execute health check manually
let result = await apiCheck.execute()
echo "Health check result: ", result.status
```

## Resource Monitoring

Monitor system resources:

```nim
let cpuMonitor = newResourceMonitor("cpu", ResourceType.CPU)
cpuMonitor.interval = initDuration(seconds = 5)

cpuMonitor.collectFn = proc(): ResourceMetrics =
  return ResourceMetrics(
    name: "cpu",
    value: getCpuUsagePercent(),
    unit: "percent",
    timestamp: getTime(),
    metadata: %*{
      "cores": getCpuCoreCount(),
      "model": getCpuModel()
    }
  )

# Custom resource type
let queueMonitor = newResourceMonitor("job_queue", ResourceType.Custom)
queueMonitor.collectFn = proc(): ResourceMetrics =
  return ResourceMetrics(
    name: "job_queue",
    value: float(getQueueSize()),
    unit: "items",
    timestamp: getTime()
  )
```

## Alert System

Define and manage alerts:

```nim
# Complex alert condition
let diskSpaceRule = newAlertRule(
  name = "low_disk_space",
  severity = AlertSeverity.Critical,
  condition = AlertCondition(
    metric: "disk",
    operator: ComparisonOperator.LessThan,
    threshold: 10.0,  # Less than 10% free
    duration: initDuration(minutes = 5)  # Sustained for 5 minutes
  )
)

# Alert with custom evaluation
let customRule = newAlertRule(
  name = "queue_backlog",
  severity = AlertSeverity.Warning,
  condition = AlertCondition(
    metric: "job_queue",
    operator: ComparisonOperator.GreaterThan,
    threshold: 1000.0
  )
)

monitor.registerAlertRule(diskSpaceRule)
monitor.registerAlertRule(customRule)

# Handle alerts
monitor.onAlert = proc(alert: Alert) {.gcsafe.} =
  case alert.severity
  of AlertSeverity.Critical:
    sendPagerDutyAlert(alert)
  of AlertSeverity.Warning:
    sendSlackNotification(alert)
  of AlertSeverity.Info:
    logAlert(alert)
```

## Application State

Track application state:

```nim
let appState = monitor.appState

# Set state
appState.setState("initialization", "starting")
appState.setState("database", "connecting")
appState.setState("api", "loading")

# Update state
appState.setState("database", "connected")
appState.setState("api", "ready")
appState.setState("initialization", "complete")

# Get state
let dbState = appState.getState("database")
let allStates = appState.getAllStates()

# State in monitoring summary
let summary = monitor.getSummary()
echo summary["appState"]
```

## Dashboard Integration

Generate dashboard-ready data:

```nim
# Get dashboard data
let dashboardData = monitor.getDashboardData()

# dashboardData contains:
# - health_checks: Current status of all health checks
# - resources: Latest resource metrics
# - alerts: Recent alerts
# - application_state: Current application state
# - timestamp: Data generation timestamp

# Use for API endpoint
proc getDashboard(): JsonNode =
  return monitor.getDashboardData()

# Use for periodic reporting
proc generateReport() =
  let data = monitor.getDashboardData()
  let report = createHtmlReport(data)
  saveReport(report)
```

## Custom Metrics

Define and track custom metrics:

```nim
# Counter metric
let requestCounter = newCustomMetric(
  name = "http_requests",
  description = "Total HTTP requests",
  metricType = MetricType.Counter
)

monitor.registerCustomMetric(requestCounter)

# Increment counter
monitor.recordMetric("http_requests", 1.0)

# Gauge metric
let activeConnections = newCustomMetric(
  name = "active_connections",
  description = "Current active connections",
  metricType = MetricType.Gauge
)

monitor.registerCustomMetric(activeConnections)

# Set gauge value
monitor.recordMetric("active_connections", getCurrentConnections())

# Histogram metric
let responseTime = newCustomMetric(
  name = "response_time",
  description = "Response time distribution",
  metricType = MetricType.Histogram
)

monitor.registerCustomMetric(responseTime)

# Record histogram value
monitor.recordMetric("response_time", measuredTime)

# Get metric value
let totalRequests = monitor.getMetricValue("http_requests")
```

## Lifecycle Hooks

Hook into monitoring events:

```nim
# Monitor start/stop
monitor.onStart = proc() {.gcsafe.} =
  echo "Monitoring started"
  initializeMetricsBackend()

monitor.onStop = proc() {.gcsafe.} =
  echo "Monitoring stopped"
  flushMetrics()
  closeConnections()

# Health check completion
monitor.onHealthCheckComplete = proc(name: string, result: HealthCheckResult) {.gcsafe.} =
  echo &"Health check {name} completed: {result.status}"
  if result.status == HealthStatus.Unhealthy:
    handleUnhealthyService(name)

# Start monitoring with hooks
monitor.startMonitoring()
```

## Persistence

Save and restore monitoring state:

```nim
# Save current state
let state = monitor.saveState()
writeFile("monitoring_state.json", $state)

# Restore state in new instance
let restoredState = parseFile("monitoring_state.json")
let newMonitor = newMonitoringSystem()
newMonitor.loadState(restoredState)

# State includes:
# - Health check definitions and status
# - Resource monitor configurations
# - Alert history
# - Application state
```

## Best Practices

1. **Health Check Design**
   - Keep health checks focused and fast
   - Set appropriate timeouts
   - Include relevant metadata
   - Use different severity levels

2. **Resource Monitoring**
   - Monitor at appropriate intervals
   - Keep metrics lightweight
   - Use proper units
   - Include contextual metadata

3. **Alert Configuration**
   - Set meaningful thresholds
   - Use duration for noisy metrics
   - Implement proper severity levels
   - Avoid alert fatigue

4. **Performance**
   - Use async operations for checks
   - Cache expensive operations
   - Batch metric collection
   - Clean up old data

5. **Integration**
   - Export metrics to monitoring systems
   - Send alerts to notification channels
   - Provide REST endpoints for dashboards
   - Log important state changes

Example integration:

```nim
import nim_libaspects/monitoring
import nim_libaspects/notifications

# Create integrated monitoring
let monitor = newMonitoringSystem()
let notifier = newNotificationSystem()

# Connect alerts to notifications
monitor.onAlert = proc(alert: Alert) {.gcsafe.} =
  let notification = newNotification(
    title = &"Alert: {alert.rule}",
    message = alert.message,
    severity = case alert.severity
      of AlertSeverity.Critical: NotificationSeverity.nsCritical
      of AlertSeverity.Warning: NotificationSeverity.nsHigh
      of AlertSeverity.Info: NotificationSeverity.nsMedium,
    metadata = alert.metadata
  )
  
  waitFor notifier.send(notification)

# Set up channels
notifier.registerChannel(createSlackChannel(webhookUrl))
notifier.registerChannel(createEmailChannel(smtpConfig))

# Monitor with notifications
monitor.startMonitoring()
```
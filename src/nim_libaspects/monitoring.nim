## Monitoring module provides comprehensive monitoring capabilities including
## health checks, resource monitoring, alerts, and application state tracking.

import std/[
  asyncdispatch,
  times,
  json,
  tables,
  strutils,
  options,
  sequtils,
  os,
  asyncfutures
]

# Convert DateTime to Time
proc now(): Time = getTime()

# Helper to generate unique IDs
var oidCounter {.threadvar.}: int
proc genOid(): string =
  inc oidCounter
  result = $oidCounter & "_" & $now().toUnix


type
  HealthStatus* = enum
    Unknown = "unknown"
    Healthy = "healthy"
    Unhealthy = "unhealthy"
    Degraded = "degraded"
  
  HealthCheckResult* = object
    status*: HealthStatus
    message*: string
    metadata*: JsonNode
    timestamp*: Time
    duration*: Duration
  
  HealthCheck* = ref object
    name*: string
    description*: string
    status*: HealthStatus
    lastResult*: Option[HealthCheckResult]
    checkFn*: proc(): Future[HealthCheckResult] {.gcsafe.}
    timeout*: Duration
  
  ResourceType* = enum
    Memory = "memory"
    CPU = "cpu"
    Disk = "disk"
    Network = "network"
    Custom = "custom"
  
  ResourceMetrics* = object
    name*: string
    value*: float
    unit*: string
    timestamp*: Time
    metadata*: JsonNode
  
  ResourceMonitor* = ref object
    name*: string
    resourceType*: ResourceType
    threshold*: float
    interval*: Duration
    collectFn*: proc(): ResourceMetrics {.gcsafe.}
    lastMetrics*: Option[ResourceMetrics]
  
  AlertSeverity* = enum
    Info = "info"
    Warning = "warning"
    Critical = "critical"
  
  ComparisonOperator* = enum
    GreaterThan = ">"
    LessThan = "<"
    Equal = "=="
    NotEqual = "!="
    GreaterOrEqual = ">="
    LessOrEqual = "<="
  
  AlertCondition* = object
    metric*: string
    operator*: ComparisonOperator
    threshold*: float
    duration*: Duration
  
  AlertRule* = ref object
    name*: string
    description*: string
    severity*: AlertSeverity
    condition*: AlertCondition
    enabled*: bool
    lastTriggered*: Option[Time]
  
  Alert* = object
    id*: string
    rule*: string
    severity*: AlertSeverity
    message*: string
    timestamp*: Time
    metadata*: JsonNode
  
  ApplicationState* = ref object
    states*: Table[string, string]
    lastUpdated*: Table[string, Time]
  
  MetricType* = enum
    Counter = "counter"
    Gauge = "gauge"
    Histogram = "histogram"
  
  CustomMetric* = ref object
    name*: string
    description*: string
    metricType*: MetricType
    value*: float
    values*: seq[float]  # For histogram
  
  MonitoringSystem* = ref object
    healthChecks*: Table[string, HealthCheck]
    resourceMonitors*: Table[string, ResourceMonitor]
    alertRules*: Table[string, AlertRule]
    alerts*: seq[Alert]
    appState*: ApplicationState
    customMetrics*: Table[string, CustomMetric]
    running*: bool
    monitoringTask*: Future[void]
    # Callbacks
    onAlert*: proc(alert: Alert) {.gcsafe.}
    onStart*: proc() {.gcsafe.}
    onStop*: proc() {.gcsafe.}
    onHealthCheckComplete*: proc(name: string, result: HealthCheckResult) {.gcsafe.}
    # Configuration
    interval*: Duration
    startTime*: Time
    endTime*: Time

# Create new monitoring system
proc newMonitoringSystem*(): MonitoringSystem =
  result = MonitoringSystem(
    healthChecks: initTable[string, HealthCheck](),
    resourceMonitors: initTable[string, ResourceMonitor](),
    alertRules: initTable[string, AlertRule](),
    alerts: @[],
    appState: ApplicationState(
      states: initTable[string, string](),
      lastUpdated: initTable[string, Time]()
    ),
    customMetrics: initTable[string, CustomMetric](),
    running: false,
    interval: initDuration(seconds = 30),
    startTime: now()
  )

# Create new health check
proc newHealthCheck*(name, description: string): HealthCheck =
  result = HealthCheck(
    name: name,
    description: description,
    status: HealthStatus.Unknown,
    timeout: initDuration(seconds = 30)
  )

# Execute health check
proc execute*(check: HealthCheck): Future[HealthCheckResult] {.async.} =
  let startTime = now()
  
  try:
    if check.checkFn.isNil:
      return HealthCheckResult(
        status: HealthStatus.Unknown,
        message: "No check function defined",
        metadata: newJNull(),
        timestamp: now(),
        duration: initDuration(milliseconds = (now().toUnix - startTime.toUnix) * 1000)
      )
    
    # Execute with timeout
    let future = check.checkFn()
    if await future.withTimeout(check.timeout.inMilliseconds):
      result = await future
      result.timestamp = now()
      result.duration = initDuration(milliseconds = (now().toUnix - startTime.toUnix) * 1000)
      check.status = result.status
      check.lastResult = some(result)
    else:
      result = HealthCheckResult(
        status: HealthStatus.Unhealthy,
        message: "Health check timed out",
        metadata: newJNull(),
        timestamp: now(),
        duration: initDuration(milliseconds = (now().toUnix - startTime.toUnix) * 1000)
      )
      check.status = result.status
      check.lastResult = some(result)
  except Exception as e:
    result = HealthCheckResult(
      status: HealthStatus.Unhealthy,
      message: "Health check failed: " & e.msg,
      metadata: newJNull(),
      timestamp: now(),
      duration: now() - startTime
    )
    check.status = result.status
    check.lastResult = some(result)

# Register health check
proc registerHealthCheck*(system: MonitoringSystem, check: HealthCheck) =
  system.healthChecks[check.name] = check

# Get all health checks
proc getHealthChecks*(system: MonitoringSystem): seq[HealthCheck] =
  result = toSeq(system.healthChecks.values)

# Get specific health check
proc getHealthCheck*(system: MonitoringSystem, name: string): Option[HealthCheck] =
  if name in system.healthChecks:
    result = some(system.healthChecks[name])
  else:
    result = none(HealthCheck)

# Create new resource monitor
proc newResourceMonitor*(name: string, resourceType: ResourceType): ResourceMonitor =
  result = ResourceMonitor(
    name: name,
    resourceType: resourceType,
    threshold: 0.0,
    interval: initDuration(seconds = 10)
  )

# Register resource monitor
proc registerResourceMonitor*(system: MonitoringSystem, monitor: ResourceMonitor) =
  system.resourceMonitors[monitor.name] = monitor

# Collect resource metrics
proc collectResourceMetrics*(system: MonitoringSystem): Future[void] {.async.} =
  for monitor in system.resourceMonitors.values:
    if not monitor.collectFn.isNil:
      let metrics = monitor.collectFn()
      monitor.lastMetrics = some(metrics)

# Get resource metrics
proc getResourceMetrics*(system: MonitoringSystem): seq[ResourceMetrics] =
  result = @[]
  for monitor in system.resourceMonitors.values:
    if monitor.lastMetrics.isSome:
      result.add(monitor.lastMetrics.get)

# Create new alert rule
proc newAlertRule*(name: string, severity: AlertSeverity, 
                   condition: AlertCondition): AlertRule =
  result = AlertRule(
    name: name,
    severity: severity,
    condition: condition,
    enabled: true
  )

# Register alert rule
proc registerAlertRule*(system: MonitoringSystem, rule: AlertRule) =
  system.alertRules[rule.name] = rule

# Evaluate alerts
proc evaluateAlerts*(system: MonitoringSystem): Future[void] {.async.} =
  for rule in system.alertRules.values:
    if not rule.enabled:
      continue
    
    # Find the metric
    var metricValue: float = 0.0
    var found = false
    
    # Check resource monitors
    for monitor in system.resourceMonitors.values:
      if monitor.name == rule.condition.metric and monitor.lastMetrics.isSome:
        metricValue = monitor.lastMetrics.get().value
        found = true
        break
    
    # Check custom metrics
    if not found and rule.condition.metric in system.customMetrics:
      metricValue = system.customMetrics[rule.condition.metric].value
      found = true
    
    if not found:
      continue
    
    # Evaluate condition
    var triggered = false
    case rule.condition.operator
    of GreaterThan:
      triggered = metricValue > rule.condition.threshold
    of LessThan:
      triggered = metricValue < rule.condition.threshold
    of Equal:
      triggered = metricValue == rule.condition.threshold
    of NotEqual:
      triggered = metricValue != rule.condition.threshold
    of GreaterOrEqual:
      triggered = metricValue >= rule.condition.threshold
    of LessOrEqual:
      triggered = metricValue <= rule.condition.threshold
    
    if triggered:
      let alert = Alert(
        id: $genOid(),
        rule: rule.name,
        severity: rule.severity,
        message: "Alert: " & rule.name & " - " & rule.condition.metric & " " & $rule.condition.operator & " " & $rule.condition.threshold,
        timestamp: now(),
        metadata: %*{
          "metric": rule.condition.metric,
          "value": metricValue,
          "threshold": rule.condition.threshold
        }
      )
      system.alerts.add(alert)
      rule.lastTriggered = some(now())
      
      if not system.onAlert.isNil:
        system.onAlert(alert)

# Create new application state
proc newApplicationState*(): ApplicationState =
  result = ApplicationState(
    states: initTable[string, string](),
    lastUpdated: initTable[string, Time]()
  )

# Set application state
proc setState*(state: ApplicationState, key, value: string) =
  state.states[key] = value
  state.lastUpdated[key] = now()

# Get application state
proc getState*(state: ApplicationState, key: string): string =
  result = state.states.getOrDefault(key, "")

# Get all states
proc getAllStates*(state: ApplicationState): Table[string, string] =
  result = state.states

# Forward declaration
proc monitoringLoop(system: MonitoringSystem): Future[void] {.async.}

# Start monitoring
proc startMonitoring*(system: MonitoringSystem, interval: Duration = initDuration(seconds = 30)) =
  system.interval = interval
  system.running = true
  system.startTime = now()
  
  if not system.onStart.isNil:
    system.onStart()
  
  system.monitoringTask = monitoringLoop(system)

# Monitoring loop
proc monitoringLoop(system: MonitoringSystem): Future[void] {.async.} =
  while system.running:
    # Run health checks
    for check in system.healthChecks.values:
      let result = await check.execute()
      if not system.onHealthCheckComplete.isNil:
        system.onHealthCheckComplete(check.name, result)
    
    # Collect resource metrics
    await system.collectResourceMetrics()
    
    # Evaluate alerts
    await system.evaluateAlerts()
    
    # Wait for next iteration
    await sleepAsync(system.interval.inMilliseconds.int)

# Stop monitoring
proc stopMonitoring*(system: MonitoringSystem) =
  system.running = false
  system.endTime = now()
  
  # In Nim, we can't cancel futures directly. Instead we use the running flag.
  
  if not system.onStop.isNil:
    system.onStop()

# Get monitoring summary
proc getSummary*(system: MonitoringSystem): JsonNode =
  result = %*{
    "startTime": system.startTime.toUnix,
    "endTime": system.endTime.toUnix,
    "running": system.running,
    "healthChecks": newJArray(),
    "resources": newJArray(),
    "alerts": newJArray(),
    "appState": %system.appState.states
  }
  
  # Add health checks
  for check in system.healthChecks.values:
    result["healthChecks"].add(%*{
      "name": check.name,
      "status": $check.status,
      "lastResult": if check.lastResult.isSome: 
        %*{
          "status": $check.lastResult.get().status,
          "message": check.lastResult.get().message,
          "timestamp": check.lastResult.get().timestamp.toUnix
        } else: newJNull()
    })
  
  # Add resources
  for monitor in system.resourceMonitors.values:
    if monitor.lastMetrics.isSome:
      let metrics = monitor.lastMetrics.get()
      result["resources"].add(%*{
        "name": monitor.name,
        "type": $monitor.resourceType,
        "value": metrics.value,
        "unit": metrics.unit,
        "threshold": monitor.threshold,
        "timestamp": metrics.timestamp.toUnix
      })
  
  # Add recent alerts
  for alert in system.alerts[max(0, system.alerts.len - 10)..^1]:
    result["alerts"].add(%*{
      "id": alert.id,
      "rule": alert.rule,
      "severity": $alert.severity,
      "message": alert.message,
      "timestamp": alert.timestamp.toUnix
    })

# Get dashboard data
proc getDashboardData*(system: MonitoringSystem): JsonNode =
  result = %*{
    "health_checks": %*{},
    "resources": %*{},
    "alerts": newJArray(),
    "application_state": %system.appState.states,
    "timestamp": now().toUnix
  }
  
  # Health checks
  for check in system.healthChecks.values:
    result["health_checks"][check.name] = %*{
      "status": $check.status,
      "description": check.description
    }
  
  # Resources
  for monitor in system.resourceMonitors.values:
    if monitor.lastMetrics.isSome:
      let metrics = monitor.lastMetrics.get()
      result["resources"][monitor.name] = %*{
        "type": $monitor.resourceType,
        "value": metrics.value,
        "unit": metrics.unit,
        "threshold": monitor.threshold
      }
  
  # Recent alerts
  for alert in system.alerts[max(0, system.alerts.len - 5)..^1]:
    result["alerts"].add(%*{
      "rule": alert.rule,
      "severity": $alert.severity,
      "timestamp": alert.timestamp.toUnix
    })

# Save monitoring state
proc saveState*(system: MonitoringSystem): JsonNode =
  result = %*{
    "health_checks": %*{},
    "resources": %*{},
    "alerts": newJArray(),
    "app_state": %system.appState.states
  }
  
  # Save health checks
  for name, check in system.healthChecks:
    result["health_checks"][name] = %*{
      "description": check.description,
      "status": $check.status
    }
  
  # Save resource monitors
  for name, monitor in system.resourceMonitors:
    result["resources"][name] = %*{
      "type": $monitor.resourceType,
      "threshold": monitor.threshold,
      "interval": monitor.interval.inSeconds
    }
  
  # Save alerts
  for alert in system.alerts:
    result["alerts"].add(%*{
      "id": alert.id,
      "rule": alert.rule,
      "severity": $alert.severity,
      "message": alert.message,
      "timestamp": alert.timestamp.toUnix
    })

# Load monitoring state
proc loadState*(system: MonitoringSystem, state: JsonNode) =
  # Load health checks
  if state.hasKey("health_checks"):
    for name, data in state["health_checks"]:
      let check = newHealthCheck(name, data["description"].getStr())
      check.status = parseEnum[HealthStatus](data["status"].getStr())
      system.registerHealthCheck(check)
  
  # Load app state
  if state.hasKey("app_state"):
    for key, value in state["app_state"]:
      system.appState.setState(key, value.getStr())

# Create custom metric
proc newCustomMetric*(name, description: string, metricType: MetricType): CustomMetric =
  result = CustomMetric(
    name: name,
    description: description,
    metricType: metricType,
    value: 0.0,
    values: @[]
  )

# Register custom metric
proc registerCustomMetric*(system: MonitoringSystem, metric: CustomMetric) =
  system.customMetrics[metric.name] = metric

# Record metric value
proc recordMetric*(system: MonitoringSystem, name: string, value: float) =
  if name in system.customMetrics:
    let metric = system.customMetrics[name]
    case metric.metricType
    of Counter:
      metric.value += value
    of Gauge:
      metric.value = value
    of Histogram:
      metric.values.add(value)

# Get metric value
proc getMetricValue*(system: MonitoringSystem, name: string): float =
  if name in system.customMetrics:
    result = system.customMetrics[name].value
  else:
    result = 0.0
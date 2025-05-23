## nim_libaspects/logging_metrics.nim
## ロギングとメトリクスの統合モジュール

import std/[tables, json, strformat, options, strutils, re, times]
import ./logging
import ./metrics

type
  MetricsExtractor* = object
    pattern*: string
    counters*: seq[string]
    histograms*: seq[string]
    gauges*: seq[string]
    summaries*: seq[string]
  
  MetricsConfig* = object
    extractors*: seq[MetricsExtractor]
    defaultLabels*: Table[string, string]
    enableAutoMetrics*: bool
    logLevelMetrics*: bool
    performanceMetrics*: bool
    errorMetrics*: bool
  
  LoggingMetricsHandler* = ref object of LogHandler
    registry*: MetricsRegistry
    config*: MetricsConfig
    extractors: Table[string, MetricsExtractor]
  
  MetricsLogger* = ref object
    logger*: Logger
    registry*: MetricsRegistry
    config*: MetricsConfig
    metricsHandler: LoggingMetricsHandler
  
  Timer* = object
    start: Time

# Default metrics configuration
proc defaultMetricsConfig*(): MetricsConfig =
  result = MetricsConfig(
    extractors: @[],
    defaultLabels: initTable[string, string](),
    enableAutoMetrics: true,
    logLevelMetrics: true,
    performanceMetrics: true,
    errorMetrics: true
  )

# Create a new metrics handler
proc newLoggingMetricsHandler*(registry: MetricsRegistry, config = defaultMetricsConfig()): LoggingMetricsHandler =
  result = LoggingMetricsHandler(
    registry: registry,
    config: config,
    extractors: initTable[string, MetricsExtractor]()
  )
  
  # Build pattern lookup table
  for extractor in config.extractors:
    result.extractors[extractor.pattern] = extractor

# Normalize metric names
proc normalizeMetricName(name: string): string =
  result = name.toLowerAscii()
  result = result.replace(" ", "_")
  result = result.replace("-", "_")
  result = result.replace(".", "_")

# Forward declarations
proc extractMetricsFromFields(registry: MetricsRegistry, fields: JsonNode, 
                              extractor: MetricsExtractor, defaultLabels: Table[string, string])
proc autoExtractMetrics(registry: MetricsRegistry, record: LogRecord)

# Process log record and extract metrics
method handle*(self: LoggingMetricsHandler, record: LogRecord) =
  # Count logs by level if enabled
  if self.config.logLevelMetrics:
    let counter = self.registry.counter("logs_total", @["level", "module"])
    var labels = @[$record.level, record.module] 
    counter.inc(labels)
  
  # Track errors
  if self.config.errorMetrics and record.level >= lvlError:
    let errorCounter = self.registry.counter("errors_total", @["module", "error_type"])
    var labels = @[record.module]
    if record.fields.hasKey("error"):
      labels.add(record.fields["error"].getStr())
    else:
      labels.add("unknown")
    errorCounter.inc(labels)
  
  # Extract custom metrics based on patterns
  for pattern, extractor in self.extractors:
    if record.message.match(re(pattern)):
      extractMetricsFromFields(self.registry, record.fields, extractor, self.config.defaultLabels)
  
  # Auto-extract common metrics
  if self.config.enableAutoMetrics:
    autoExtractMetrics(self.registry, record)

# Extract metrics based on field names
proc extractMetricsFromFields(registry: MetricsRegistry, fields: JsonNode, 
                              extractor: MetricsExtractor, defaultLabels: Table[string, string]) =
  if fields.kind != JObject:
    return
  
  var labelNames: seq[string] = @[]
  var labelValues: seq[string] = @[]
  
  # Extract label values first
  for key, value in fields:
    if key.endsWith("_label") or key in ["method", "status", "service", "operation", "endpoint"]:
      labelNames.add(key)
      labelValues.add(value.getStr())
  
  # Extract counter metrics
  for counterName in extractor.counters:
    if fields.hasKey(counterName):
      let counter = registry.counter(normalizeMetricName(counterName), labelNames)
      counter.inc(labelValues)
  
  # Extract histogram metrics
  for histName in extractor.histograms:
    if fields.hasKey(histName):
      let value = fields[histName]
      if value.kind in {JInt, JFloat}:
        let histogram = registry.histogram(
          normalizeMetricName(histName),
          labelNames,
          @[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
        )
        histogram.observe(value.getFloat(), labelValues)
  
  # Extract gauge metrics
  for gaugeName in extractor.gauges:
    if fields.hasKey(gaugeName):
      let value = fields[gaugeName]
      if value.kind in {JInt, JFloat}:
        let gauge = registry.gauge(normalizeMetricName(gaugeName), labelNames)
        gauge.set(value.getFloat(), labelValues)

# Auto-extract common metrics
proc autoExtractMetrics(registry: MetricsRegistry, record: LogRecord) =
  if record.fields.kind != JObject:
    return
  
  var labelNames: seq[string] = @[]
  var labelValues: seq[string] = @[]
  
  # Extract common fields as labels
  for key, value in record.fields:
    case key
    of "method", "status", "service", "endpoint", "operation":
      labelNames.add(key)
      labelValues.add(value.getStr())
  
  # Look for common metric patterns
  for key, value in record.fields:
    case key
    of "duration", "duration_ms", "response_time", "response_time_ms", "latency_ms":
      if value.kind in {JInt, JFloat}:
        let histName = if key.endsWith("_ms"): key else: key & "_ms"
        let histogram = registry.histogram(
          normalizeMetricName("request_" & histName),
          labelNames,
          @[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
        )
        histogram.observe(value.getFloat(), labelValues)
    
    of "error_count", "retry_count", "attempt_count":
      if value.kind == JInt:
        let counter = registry.counter(
          normalizeMetricName(key),
          labelNames
        )
        counter.inc(labelValues)
    
    of "memory_mb", "cpu_percent", "disk_usage", "queue_size":
      if value.kind in {JInt, JFloat}:
        let gauge = registry.gauge(
          normalizeMetricName(key),
          labelNames
        )
        gauge.set(value.getFloat(), labelValues)

# Create a timer for measuring durations
proc startTimer*(): Timer =
  Timer(start: getTime())

# Extend Logger with metrics support
proc attachMetrics*(logger: var Logger, registry: MetricsRegistry, config = defaultMetricsConfig()) =
  let handler = newLoggingMetricsHandler(registry, config)
  logger.handlers.add(handler)

# Create a new logger with metrics integration
proc newMetricsLogger*(name: string, registry: MetricsRegistry, config = defaultMetricsConfig()): MetricsLogger =
  result = MetricsLogger(
    logger: newLogger(name),
    registry: registry,
    config: config
  )
  
  result.metricsHandler = newLoggingMetricsHandler(registry, config)
  result.logger.handlers.add(result.metricsHandler)

# Add middleware support for metrics
proc addMiddleware*(logger: Logger, middleware: proc(record: LogRecord): LogRecord) =
  # This would need to be implemented in the base logging module
  discard

# Helper for creating structured logs with fields
proc withFields*(logger: Logger, fields: JsonNode): Logger =
  # This would need to be implemented in the base logging module
  result = logger

proc elapsed*(timer: Timer): Duration =
  getTime() - timer.start

# Get a summary of all metrics
proc getSummary*(registry: MetricsRegistry): JsonNode =
  result = newJObject()
  
  let allMetrics = registry.getAllMetrics()
  
  let countersSummary = newJObject()
  let histogramsSummary = newJObject()
  let gaugesSummary = newJObject()
  
  for name, metric in allMetrics:
    case metric.kind
    of mtCounter:
      countersSummary[name] = %* {
        "type": "counter"
      }
    of mtHistogram:
      histogramsSummary[name] = %* {
        "type": "histogram"
      }
    of mtGauge:
      gaugesSummary[name] = %* {
        "type": "gauge"
      }
    else:
      discard
  
  result["counters"] = countersSummary
  result["histograms"] = histogramsSummary
  result["gauges"] = gaugesSummary

# Integration with distributed tracing
proc extractTraceInfo*(fields: JsonNode): tuple[traceId, spanId: string] =
  result.traceId = ""
  result.spanId = ""
  
  if fields.kind == JObject:
    if fields.hasKey("trace_id"):
      result.traceId = fields["trace_id"].getStr()
    if fields.hasKey("span_id"):
      result.spanId = fields["span_id"].getStr()

# Enhanced logging methods with metrics
proc logWithMetrics*(logger: MetricsLogger, level: LogLevel, message: string, fields: JsonNode) =
  # Create log record
  let record = LogRecord(
    level: level,
    message: message,
    timestamp: now(),
    module: logger.logger.module,
    fields: fields
  )
  
  # Extract trace info if available
  let (traceId, spanId) = extractTraceInfo(fields)
  if traceId != "":
    var labelNames = @["service", "operation"]
    var labelValues: seq[string] = @[]
    
    if fields.hasKey("service"):
      labelValues.add(fields["service"].getStr())
    else:
      labelValues.add("unknown")
      
    if fields.hasKey("operation"):
      labelValues.add(fields["operation"].getStr())
    else:
      labelValues.add("unknown")
    
    let traceCounter = logger.registry.counter("traces_total", labelNames)
    traceCounter.inc(labelValues)
  
  # Log with all handlers
  for handler in logger.logger.handlers:
    handler.handle(record)

# Convenience methods
proc debug*(logger: MetricsLogger, message: string, fields = newJObject()) =
  logger.logWithMetrics(lvlDebug, message, fields)

proc info*(logger: MetricsLogger, message: string, fields = newJObject()) =
  logger.logWithMetrics(lvlInfo, message, fields)

proc warn*(logger: MetricsLogger, message: string, fields = newJObject()) =
  logger.logWithMetrics(lvlWarn, message, fields)

proc error*(logger: MetricsLogger, message: string, fields = newJObject()) =
  logger.logWithMetrics(lvlError, message, fields)

proc fatal*(logger: MetricsLogger, message: string, fields = newJObject()) =
  logger.logWithMetrics(lvlFatal, message, fields)
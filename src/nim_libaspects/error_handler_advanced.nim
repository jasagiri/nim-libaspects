## Advanced error handling module
## Provides error aggregation, classification, prioritization, and recovery strategies

import std/[
  tables,
  sequtils,
  json,
  strformat,
  times,
  algorithm,
  os,
  locks,
  math,
  strutils
]
import ./errors

type
  # Error aggregation
  ErrorGroup* = object
    message*: string
    count*: int
    firstOccurrence*: Time
    lastOccurrence*: Time
    severities*: CountTable[ErrorSeverity]
  
  ErrorSummary* = object
    totalErrors*: int
    uniqueErrors*: int
    bySeverity*: CountTable[ErrorSeverity]
    byCategory*: CountTable[string]
    timeRange*: tuple[start: Time, finish: Time]
  
  ErrorAggregator* = ref object
    errors*: seq[ref AppError]
    groups*: Table[string, ErrorGroup]
    lock: Lock
  
  # Error classification
  ClassificationRule* = proc(err: ref AppError): bool {.gcsafe.}
  
  ErrorClassifier* = ref object
    rules*: Table[string, ClassificationRule]
    defaultCategory*: string
  
  # Error prioritization
  PriorityRule* = proc(err: ref AppError): int {.gcsafe.}
  
  ErrorPrioritizer* = ref object
    baseRule*: PriorityRule
    boosts*: Table[string, int]  # tag -> priority boost
  
  # Recovery strategies
  RecoveryResult* = object
    isRecovered*: bool
    value*: string
    attempts*: int
    error*: ref AppError
    circuitOpen*: bool
  
  RecoveryStrategy* = ref object of RootObj
    name*: string
  
  RetryStrategy* = ref object of RecoveryStrategy
    maxAttempts*: int
    backoffMs*: int
    backoffMultiplier*: float
  
  FallbackStrategy* = ref object of RecoveryStrategy
    fallbackValue*: string
  
  CircuitBreakerStrategy* = ref object of RecoveryStrategy
    failureThreshold*: int
    resetTimeoutMs*: int
    failureCount*: int
    lastFailureTime*: Time
    isOpen*: bool
  
  RecoveryManager* = ref object
    strategies*: Table[string, RecoveryStrategy]
  
  # Error enrichment
  ContextProvider* = proc(): JsonNode {.gcsafe.}
  
  ErrorEnricher* = ref object
    providers*: Table[string, ContextProvider]
  
  EnrichedError* = ref object
    baseError*: ref AppError
    enrichedContext*: JsonNode
  
  # Error reporting
  ReportFormatter* = proc(errors: seq[ref AppError]): string {.gcsafe.}
  ReportDestination* = proc(report: string) {.gcsafe.}
  
  ErrorReporter* = ref object
    formats*: Table[string, ReportFormatter]
    destinations*: Table[string, tuple[format: string, handler: ReportDestination]]
  
  # Error stream processing
  ErrorFilter* = proc(err: ref AppError): bool {.gcsafe.}
  ErrorTransformer* = proc(err: ref AppError): ref AppError {.gcsafe.}
  ErrorHandler* = proc(err: ref AppError) {.gcsafe.}
  
  ErrorStreamProcessor* = ref object
    filters*: seq[ErrorFilter]
    transformers*: seq[ErrorTransformer]
    handlers*: seq[ErrorHandler]

# Error aggregation implementation
proc newErrorAggregator*(): ErrorAggregator =
  result = ErrorAggregator(
    errors: @[],
    groups: initTable[string, ErrorGroup]()
  )
  initLock(result.lock)

proc addError*(aggregator: ErrorAggregator, err: ref AppError) =
  withLock(aggregator.lock):
    aggregator.errors.add(err)
    
    let key = err.msg
    if key notin aggregator.groups:
      aggregator.groups[key] = ErrorGroup(
        message: err.msg,
        count: 0,
        firstOccurrence: now().toTime,
        lastOccurrence: now().toTime,
        severities: initCountTable[ErrorSeverity]()
      )
    
    var group = aggregator.groups[key]
    inc group.count
    group.lastOccurrence = now().toTime
    group.severities.inc(err.severity)
    aggregator.groups[key] = group

proc getSummary*(aggregator: ErrorAggregator): ErrorSummary =
  withLock(aggregator.lock):
    result.totalErrors = aggregator.errors.len
    result.uniqueErrors = aggregator.groups.len
    result.bySeverity = initCountTable[ErrorSeverity]()
    result.byCategory = initCountTable[string]()
    
    if aggregator.errors.len > 0:
      result.timeRange.start = now().toTime
      result.timeRange.finish = now().toTime
    
    for err in aggregator.errors:
      result.bySeverity.inc(err.severity)
      # Category would come from error context or code
      result.byCategory.inc($err.context.code)

proc getErrorGroups*(aggregator: ErrorAggregator): Table[string, ErrorGroup] =
  withLock(aggregator.lock):
    result = aggregator.groups

# Error classification implementation
proc newErrorClassifier*(defaultCategory = "unknown"): ErrorClassifier =
  ErrorClassifier(
    rules: initTable[string, ClassificationRule](),
    defaultCategory: defaultCategory
  )

proc addRule*(classifier: ErrorClassifier, category: string, rule: ClassificationRule) =
  classifier.rules[category] = rule

proc classify*(classifier: ErrorClassifier, err: ref AppError): string =
  for category, rule in classifier.rules:
    if rule(err):
      return category
  return classifier.defaultCategory

# Error prioritization implementation
proc newErrorPrioritizer*(): ErrorPrioritizer =
  ErrorPrioritizer(
    baseRule: nil,
    boosts: initTable[string, int]()
  )

proc addPriorityRule*(prioritizer: ErrorPrioritizer, rule: PriorityRule) =
  prioritizer.baseRule = rule

proc addPriorityBoost*(prioritizer: ErrorPrioritizer, tag: string, boost: int) =
  prioritizer.boosts[tag] = boost

proc getPriority*(prioritizer: ErrorPrioritizer, err: ref AppError): int =
  if prioritizer.baseRule != nil:
    result = prioritizer.baseRule(err)
  
  # Tags could be derived from error code or context
  let tag = $err.context.code
  if tag in prioritizer.boosts:
    result += prioritizer.boosts[tag]

proc sortByPriority*(prioritizer: ErrorPrioritizer, errors: seq[ref AppError]): seq[ref AppError] =
  result = errors
  result.sort(proc(a, b: ref AppError): int =
    prioritizer.getPriority(b) - prioritizer.getPriority(a)
  )

# Recovery strategies implementation
proc newRetryStrategy*(maxAttempts: int, backoffMs: int, backoffMultiplier = 2.0): RetryStrategy =
  RetryStrategy(
    name: "retry",
    maxAttempts: maxAttempts,
    backoffMs: backoffMs,
    backoffMultiplier: backoffMultiplier
  )

proc newFallbackStrategy*(fallbackValue: string): FallbackStrategy =
  FallbackStrategy(
    name: "fallback",
    fallbackValue: fallbackValue
  )

proc newCircuitBreakerStrategy*(failureThreshold: int, resetTimeoutMs: int): CircuitBreakerStrategy =
  CircuitBreakerStrategy(
    name: "circuit_breaker",
    failureThreshold: failureThreshold,
    resetTimeoutMs: resetTimeoutMs,
    failureCount: 0,
    isOpen: false
  )

proc newRecoveryManager*(): RecoveryManager =
  RecoveryManager(
    strategies: initTable[string, RecoveryStrategy]()
  )

proc registerStrategy*(manager: RecoveryManager, name: string, strategy: RecoveryStrategy) =
  manager.strategies[name] = strategy

template execute*(manager: RecoveryManager, strategyName: string, body: untyped): RecoveryResult =
  var result = RecoveryResult(isRecovered: false, value: "", attempts: 0)
  
  if strategyName in manager.strategies:
    let strategy = manager.strategies[strategyName]
    
    case strategy.name
    of "retry":
      let retryStrategy = cast[RetryStrategy](strategy)
      var backoff = retryStrategy.backoffMs
      
      for attempt in 1..retryStrategy.maxAttempts:
        result.attempts = attempt
        try:
          result.value = body
          result.isRecovered = true
          break
        except Exception as e:
          result.error = newAppError(ecInternalError, e.msg, severity = sevError)
          if attempt < retryStrategy.maxAttempts:
            sleep(backoff)
            backoff = int(backoff.float * retryStrategy.backoffMultiplier)
    
    of "fallback":
      let fallbackStrategy = cast[FallbackStrategy](strategy)
      try:
        result.value = body
        result.isRecovered = true
      except Exception as e:
        result.error = newAppError(ecInternalError, e.msg, severity = sevWarning)
        result.value = fallbackStrategy.fallbackValue
        result.isRecovered = true
    
    of "circuit_breaker":
      let cbStrategy = cast[CircuitBreakerStrategy](strategy)
      let now = getTime()
      
      # Check if circuit should be reset
      if cbStrategy.isOpen and (now - cbStrategy.lastFailureTime).inMilliseconds > cbStrategy.resetTimeoutMs:
        cbStrategy.isOpen = false
        cbStrategy.failureCount = 0
      
      result.circuitOpen = cbStrategy.isOpen
      
      if not cbStrategy.isOpen:
        try:
          result.value = body
          result.isRecovered = true
          cbStrategy.failureCount = 0
        except Exception as e:
          result.error = newAppError(ecInternalError, e.msg, severity = sevError)
          inc cbStrategy.failureCount
          cbStrategy.lastFailureTime = now
          
          if cbStrategy.failureCount >= cbStrategy.failureThreshold:
            cbStrategy.isOpen = true
  
  result

# Error enrichment implementation
proc newErrorEnricher*(): ErrorEnricher =
  ErrorEnricher(
    providers: initTable[string, ContextProvider]()
  )

proc addContextProvider*(enricher: ErrorEnricher, name: string, provider: ContextProvider) =
  enricher.providers[name] = provider

proc enrich*(enricher: ErrorEnricher, err: ref AppError): ref AppError =
  result = err
  result.enrichedContext = newJObject()
  
  for name, provider in enricher.providers:
    try:
      result.enrichedContext[name] = provider()
    except:
      result.enrichedContext[name] = %*{"error": "Failed to get context"}

# Error reporting implementation
proc newErrorReporter*(): ErrorReporter =
  ErrorReporter(
    formats: initTable[string, ReportFormatter](),
    destinations: initTable[string, tuple[format: string, handler: ReportDestination]]()
  )

proc addFormat*(reporter: ErrorReporter, name: string, formatter: ReportFormatter) =
  reporter.formats[name] = formatter

proc addDestination*(reporter: ErrorReporter, name: string, format: string, handler: ReportDestination) =
  reporter.destinations[name] = (format: format, handler: handler)

proc report*(reporter: ErrorReporter, errors: seq[ref AppError]) =
  for name, dest in reporter.destinations:
    if dest.format in reporter.formats:
      let formatter = reporter.formats[dest.format]
      let report = formatter(errors)
      dest.handler(report)

# Error stream processing implementation
proc newErrorStreamProcessor*(): ErrorStreamProcessor =
  ErrorStreamProcessor(
    filters: @[],
    transformers: @[],
    handlers: @[]
  )

proc addFilter*(processor: ErrorStreamProcessor, filter: ErrorFilter) =
  processor.filters.add(filter)

proc addTransformer*(processor: ErrorStreamProcessor, transformer: ErrorTransformer) =
  processor.transformers.add(transformer)

proc addHandler*(processor: ErrorStreamProcessor, handler: ErrorHandler) =
  processor.handlers.add(handler)

proc process*(processor: ErrorStreamProcessor, err: ref AppError) =
  # Apply filters
  for filter in processor.filters:
    if not filter(err):
      return
  
  # Apply transformers
  var processedErr = err
  for transformer in processor.transformers:
    processedErr = transformer(processedErr)
  
  # Apply handlers
  for handler in processor.handlers:
    handler(processedErr)

# Convenience functions
proc createDetailedErrorReport*(errors: seq[ref AppError]): string =
  result = "Detailed Error Report\n"
  result &= "===================\n\n"
  
  # Group by severity
  var bySeverity = initTable[ErrorSeverity, seq[ref AppError]]()
  for err in errors:
    if err.severity notin bySeverity:
      bySeverity[err.severity] = @[]
    bySeverity[err.severity].add(err)
  
  # Report by severity
  for severity in [sevCritical, sevError, sevWarning, sevInfo, sevDebug]:
    if severity in bySeverity:
      result &= &"\n{severity} Errors ({bySeverity[severity].len}):\n"
      result &= repeat("-", 40) & "\n"
      
      for err in bySeverity[severity]:
        result &= &"Time: {now()}\n"
        result &= &"Message: {err.msg}\n"
        result &= &"Code: {err.context.code}\n"
        if err.context.source != "":
          result &= &"Source: {err.context.source}\n"
        if err.context.stackTrace.len > 0:
          result &= "Stack Trace:\n" & err.context.stackTrace.join("\n") & "\n"
        result &= "\n"

proc createJsonErrorReport*(errors: seq[ref AppError]): JsonNode =
  result = %*{
    "report": {
      "timestamp": $getTime(),
      "totalErrors": errors.len,
      "errors": newJArray()
    }
  }
  
  for err in errors:
    let errorJson = %*{
      "timestamp": $now(),
      "severity": $err.severity,
      "message": err.msg,
      "code": $err.context.code,
      "source": err.context.source,
      "stackTrace": err.context.stackTrace
    }
    
    # Add enriched context if available
    if err.enrichedContext != nil:
      errorJson["enrichedContext"] = err.enrichedContext
    result["report"]["errors"].add(errorJson)

# Global error handler with recovery
var globalErrorHandler* = newRecoveryManager()

# Initialize default strategies
globalErrorHandler.registerStrategy("default_retry", newRetryStrategy(3, 100))
globalErrorHandler.registerStrategy("default_fallback", newFallbackStrategy(""))
globalErrorHandler.registerStrategy("default_circuit", newCircuitBreakerStrategy(5, 60000))

template withErrorRecovery*(strategy: string, body: untyped): untyped =
  globalErrorHandler.execute(strategy, body)
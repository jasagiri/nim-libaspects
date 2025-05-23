## Test suite for advanced error handling features
import unittest
import times
import sequtils
import tables
import json
import os
import strutils
import strformat
import nim_libaspects/error_handler_advanced
import nim_libaspects/errors

suite "Advanced Error Handler Tests":
  test "Error aggregation":
    let aggregator = newErrorAggregator()
    
    # Add multiple errors
    aggregator.addError(newAppError(ecConnectionFailed, "Connection failed", severity = sevError))
    aggregator.addError(newAppError(ecTimeout, "Timeout", severity = sevWarning))
    aggregator.addError(newAppError(ecInvalidInput, "Invalid input", severity = sevInfo))
    aggregator.addError(newAppError(ecConnectionFailed, "Connection failed", severity = sevError))  # Duplicate
    
    # Check aggregation
    let summary = aggregator.getSummary()
    check(summary.totalErrors == 4)
    check(summary.uniqueErrors == 3)
    check(summary.bySeverity[sevError] == 2)
    check(summary.bySeverity[sevWarning] == 1)
    check(summary.bySeverity[sevInfo] == 1)
    
    # Check error grouping
    let groups = aggregator.getErrorGroups()
    check("Connection failed" in groups)
    check(groups["Connection failed"].count == 2)
  
  test "Error classification":
    let classifier = newErrorClassifier()
    
    # Register classification rules
    classifier.addRule("network", proc(err: ref AppError): bool =
      err.msg.contains("connection") or err.msg.contains("timeout")
    )
    
    classifier.addRule("validation", proc(err: ref AppError): bool =
      err.msg.toLowerAscii.contains("invalid") or err.msg.toLowerAscii.contains("required")
    )
    
    # Classify errors
    let networkError = newAppError(ecConnectionFailed, "Connection timeout", severity = sevError)
    let validationError = newAppError(ecInvalidInput, "Invalid email format", severity = sevWarning)
    let unknownError = newAppError(ecInternalError, "Unknown failure", severity = sevError)
    
    check(classifier.classify(networkError) == "network")
    check(classifier.classify(validationError) == "validation")
    check(classifier.classify(unknownError) == "unknown")
  
  test "Error prioritization":
    let prioritizer = newErrorPrioritizer()
    
    # Configure priority rules
    prioritizer.addPriorityRule(proc(err: ref AppError): int =
      case err.severity
      of sevCritical: 100
      of sevError: 75
      of sevWarning: 50
      of sevInfo: 25
      of sevDebug: 10
    )
    
    prioritizer.addPriorityBoost($ecPermissionDenied, 50)
    prioritizer.addPriorityBoost($ecResourceExhausted, 40)
    
    # Create errors with tags
    var err1 = newAppError(ecPermissionDenied, "Security breach", severity = sevError)
    # err1.tags = @["security"]  # AppError doesn't have tags field
    
    var err2 = newAppError(ecResourceExhausted, "Data corruption", severity = sevError)
    # err2.tags = @["data_loss"]  # AppError doesn't have tags field
    
    var err3 = newAppError(ecInternalError, "UI glitch", severity = sevInfo)
    
    # Check priorities (75 for High priority + boost from error code)
    check(prioritizer.getPriority(err1) == 125)  # 75 + 50
    check(prioritizer.getPriority(err2) == 115)  # 75 + 40
    check(prioritizer.getPriority(err3) == 25)   # 25 + 0 (no boost)
    
    # Sort by priority
    let errors = @[err3, err1, err2]
    let sorted = prioritizer.sortByPriority(errors)
    check(sorted[0] == err1)
    check(sorted[1] == err2)
    check(sorted[2] == err3)
  
  test "Recovery strategies":
    let recoveryManager = newRecoveryManager()
    
    # Register recovery strategies
    recoveryManager.registerStrategy("retry", newRetryStrategy(
      maxAttempts = 3,
      backoffMs = 100,
      backoffMultiplier = 2.0
    ))
    
    recoveryManager.registerStrategy("fallback", newFallbackStrategy(
      fallbackValue = "default"
    ))
    
    recoveryManager.registerStrategy("circuit_breaker", newCircuitBreakerStrategy(
      failureThreshold = 3,
      resetTimeoutMs = 5000
    ))
    
    # Test retry strategy
    var retryCount = 0
    let retryResult = recoveryManager.execute("retry"):
      inc retryCount
      if retryCount < 3:
        raise newException(IOError, "Connection failed")
      "success"
    
    check(retryResult.isRecovered)
    check(retryResult.value == "success")
    check(retryResult.attempts == 3)
    
    # Test fallback strategy
    let fallbackResult = recoveryManager.execute("fallback"):
      raise newException(ValueError, "Invalid input")
      ""  # Never reached, but needed for type inference
    
    check(fallbackResult.isRecovered)
    check(fallbackResult.value == "default")
    
    # Test circuit breaker
    var cbCount = 0
    for i in 1..5:
      let result = recoveryManager.execute("circuit_breaker"):
        inc cbCount
        if cbCount <= 3:
          raise newException(IOError, "Service unavailable")
        "success"
      
      if i <= 3:
        check(not result.isRecovered)
      else:
        check(result.circuitOpen)  # Circuit should be open
  
  test "Error context enrichment":
    let enricher = newErrorEnricher()
    
    # Add context providers
    enricher.addContextProvider("system", proc(): JsonNode =
      %*{
        "os": hostOS,
        "cpu": hostCPU,
        "timestamp": $getTime()
      }
    )
    
    enricher.addContextProvider("user", proc(): JsonNode =
      %*{
        "userId": "12345",
        "sessionId": "abc-def-ghi"
      }
    )
    
    # Enrich error
    var err = newAppError(ecInternalError, "Operation failed", severity = sevCritical)
    let enriched = enricher.enrich(err)
    
    check(enriched.enrichedContext.hasKey("system"))
    check(enriched.enrichedContext.hasKey("user"))
    check(enriched.enrichedContext["system"].hasKey("os"))
    check(enriched.enrichedContext["user"]["userId"].getStr() == "12345")
  
  test "Error reporting":
    let reporter = newErrorReporter()
    
    # Configure report formats
    reporter.addFormat("summary", proc(errors: seq[ref AppError]): string =
      &"Total errors: {errors.len}"
    )
    
    reporter.addFormat("detailed", proc(errors: seq[ref AppError]): string =
      var result = "Error Report:\n"
      for err in errors:
        result &= &"- [{err.severity}] {err.msg}\n"
      result
    )
    
    # Add destinations (simplified for gc safety)
    var outputReceived = false
    
    reporter.addDestination("console_summary", "summary", 
      proc(report: string) {.gcsafe.} = 
        outputReceived = true
        echo "Summary: ", report)
    
    reporter.addDestination("file_detailed", "detailed",
      proc(report: string) {.gcsafe.} = 
        outputReceived = true
        echo "Detailed: ", report)
    
    # Report errors
    let errors = @[
      newAppError(ecInternalError, "Error 1", severity = sevError),
      newAppError(ecInternalError, "Error 2", severity = sevWarning)
    ]
    
    reporter.report(errors)
    
    # Just check that output was produced
    check(outputReceived)
  
  test "Error stream processing":
    let processor = newErrorStreamProcessor()
    
    # Add filters
    processor.addFilter(proc(err: ref AppError): bool =
      err.severity >= sevWarning
    )
    
    # Add transformers
    processor.addTransformer(proc(err: ref AppError): ref AppError =
      result = err
      result.msg = "[PROCESSED] " & err.msg
    )
    
    # Add handlers
    var handledCount = 0
    processor.addHandler(proc(err: ref AppError) {.gcsafe.} =
      inc handledCount
    )
    
    # Process errors
    processor.process(newAppError(ecInternalError, "Low priority", severity = sevInfo))
    processor.process(newAppError(ecInternalError, "High priority", severity = sevError))
    processor.process(newAppError(ecInternalError, "Medium priority", severity = sevWarning))
    
    check(handledCount == 2)  # Low priority filtered out
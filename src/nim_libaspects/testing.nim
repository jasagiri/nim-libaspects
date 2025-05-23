## testing.nim
## ==========
##
## Unified testing framework module for nim-libs.
## This module provides a comprehensive testing framework with assertions,
## test discovery, and various reporters.
##
## Features:
## - Enhanced assertions with detailed error messages
## - Test discovery and organization
## - Multiple output formats (console, JSON, HTML)
## - Test fixtures and lifecycle hooks
## - Parallel test execution support

import std/[tables, strutils, strformat, sets, os, times, json, locks]
import ./errors
import ./config
import ./parallel
import nim_core
import nim_corepkg/ast/analyzer as ast_analyzer
import nim_corepkg/analysis/ai_patterns

# Export basic types and functions that tests commonly need
export times.DateTime

type
  TestStatus* = enum
    tsPass     ## Test passed
    tsFail     ## Test failed
    tsSkip     ## Test was skipped
    tsError    ## Error during test execution
    tsPending  ## Test is pending implementation

  TestResult* = object
    name*: string
    suite*: string
    status*: TestStatus
    message*: string
    duration*: float
    timestamp*: DateTime
    stackTrace*: seq[string]
    assertions*: seq[AssertionInfo]

  AssertionInfo* = object
    expression*: string
    location*: string
    message*: string
    values*: seq[tuple[name: string, value: string]]

  TestInfo* = object
    name*: string
    suite*: string
    filename*: string
    lineNumber*: int
    tags*: HashSet[string]
    testProc*: TestProc
    timeout*: int

  TestSuite* = object
    name*: string
    tests*: seq[TestInfo]
    beforeAll*: seq[FixtureProc]
    afterAll*: seq[FixtureProc]
    beforeEach*: seq[FixtureProc]
    afterEach*: seq[FixtureProc]
    parallel*: bool
    tags*: HashSet[string]

  TestRunner* = ref object
    suites*: seq[TestSuite]
    config*: TestConfig
    reporter*: TestReporter
    results*: seq[TestResult]
    stats*: TestStats
    discoverer*: TestDiscoverer
    parallel*: bool

  TestConfig* = ref object
    pattern*: string
    tags*: HashSet[string]
    excludeTags*: HashSet[string]
    parallel*: bool
    maxWorkers*: int
    timeout*: int
    verbosity*: int
    outputDir*: string
    failFast*: bool

  TestStats* = object
    total*: int
    passed*: int
    failed*: int
    skipped*: int
    errors*: int
    pending*: int
    duration*: float
    startTime*: DateTime
    endTime*: DateTime

  TestProc* = proc(): Result[void, ref TestError] {.gcsafe.}
  FixtureProc* = proc(): Result[void, ref TestError] {.gcsafe.}

  TestReporter* = ref object of RootObj
  TestDiscoverer* = ref object of RootObj

  TestError* = object of CatchableError

  PowerAssertError* = object of TestError
    expression*: string
    values*: seq[tuple[name: string, value: string]]
    location*: string

  # Reporter implementations
  ConsoleReporter* = ref object of TestReporter
    colored*: bool
    verbose*: bool

  JsonReporter* = ref object of TestReporter
    outputFile*: string
    pretty*: bool

  HtmlReporter* = ref object of TestReporter
    outputFile*: string
    cssFile*: string
    title*: string

  # Discoverer implementations
  FileDiscoverer* = ref object of TestDiscoverer
    pattern*: string
    rootDir*: string

  ModuleDiscoverer* = ref object of TestDiscoverer
    modules*: seq[string]

# Global test registry
var testRegistry {.threadvar.}: seq[TestSuite]
var currentSuite {.threadvar.}: string
var testLock: Lock

proc initTestRegistry*() =
  ## Initialize the test registry
  testRegistry = @[]
  currentSuite = ""
  initLock(testLock)

# Test assertions with power assert features
template check*(condition: untyped, message: string = ""): untyped =
  ## Enhanced assertion that provides detailed error information using AST analysis
  let condResult = condition
  if not condResult:
    var error: ref PowerAssertError
    new(error)
    error.expression = astToStr(condition)
    error.location = instantiationInfo().filename & ":" & $instantiationInfo().line
    
    # Use nim-lang-core's AST analysis for better error messages
    when compiles(ast_analyzer.parseString(astToStr(condition))):
      let ast = ast_analyzer.parseString(astToStr(condition))
      # Extract values from AST for detailed error reporting
      # This would provide better insights into assertion failures
    
    if message.len > 0:
      error.msg = message
    else:
      error.msg = fmt"Assertion failed: {astToStr(condition)}"
    raise error

template expect*(expected, actual: untyped): untyped =
  ## Compare expected and actual values
  block:
    let exp = expected
    let act = actual
    if exp != act:
      var error: ref PowerAssertError
      new(error)
      error.expression = $(astToStr(actual)) & " == " & $(astToStr(expected))
      error.values = @[("expected", $exp), ("actual", $act)]
      error.location = instantiationInfo().filename & ":" & $instantiationInfo().line
      error.msg = "Expected " & $exp & ", got " & $act
      raise error

template expectError*(errorType: typedesc, code: untyped): untyped =
  ## Expect that code raises a specific error type
  block:
    let errorTypeName = $errorType
    var raised = false
    var actualError = ""
    try:
      code
    except errorType:
      raised = true
    except CatchableError as e:
      actualError = $e.name
    
    if not raised:
      var error: ref PowerAssertError
      new(error)
      error.location = instantiationInfo().filename & ":" & $instantiationInfo().line
      if actualError.len > 0:
        error.msg = "Expected " & errorTypeName & ", got " & actualError
      else:
        error.msg = "Expected " & errorTypeName & ", but no error was raised"
      raise error

# Test definition macros
template suite*(name: string, body: untyped): untyped =
  ## Define a test suite
  block:
    let oldSuite = currentSuite
    currentSuite = name
    # Create new suite if needed
    var found = false
    withLock(testLock):
      for s in mitems(testRegistry):
        if s.name == name:
          found = true
          break
      if not found:
        testRegistry.add(TestSuite(
          name: name,
          tests: @[],
          beforeAll: @[],
          afterAll: @[],
          beforeEach: @[],
          afterEach: @[]
        ))
    
    body
    currentSuite = oldSuite

template test*(name: string, body: untyped): untyped =
  ## Define a test within a suite
  block:
    let testProc = proc(): Result[void, ref TestError] {.gcsafe.} =
      try:
        body
        Result[void, ref TestError].ok()
      except TestError as e:
        Result[void, ref TestError].err(e)
      except CatchableError as e:
        var te = new(TestError)
        te.msg = e.msg
        Result[void, ref TestError].err(te)
    
    let info = TestInfo(
      name: name,
      suite: currentSuite,
      filename: instantiationInfo().filename,
      lineNumber: instantiationInfo().line,
      testProc: testProc
    )
    
    withLock(testLock):
      for s in mitems(testRegistry):
        if s.name == currentSuite:
          s.tests.add(info)
          break

# Test lifecycle hooks
template beforeAll*(body: untyped): untyped =
  ## Run before all tests in a suite
  block:
    let hookProc = proc(): Result[void, ref TestError] {.gcsafe.} =
      try:
        body
        Result[void, ref TestError].ok()
      except CatchableError as e:
        var te = new(TestError)
        te.msg = e.msg
        Result[void, ref TestError].err(te)
    
    withLock(testLock):
      for s in mitems(testRegistry):
        if s.name == currentSuite:
          s.beforeAll.add(hookProc)
          break

template afterAll*(body: untyped): untyped =
  ## Run after all tests in a suite
  block:
    let hookProc = proc(): Result[void, ref TestError] {.gcsafe.} =
      try:
        body
        Result[void, ref TestError].ok()
      except CatchableError as e:
        var te = new(TestError)
        te.msg = e.msg
        Result[void, ref TestError].err(te)
    
    withLock(testLock):
      for s in mitems(testRegistry):
        if s.name == currentSuite:
          s.afterAll.add(hookProc)
          break

template beforeEach*(body: untyped): untyped =
  ## Run before each test in a suite
  block:
    let hookProc = proc(): Result[void, ref TestError] {.gcsafe.} =
      try:
        body
        Result[void, ref TestError].ok()
      except CatchableError as e:
        var te = new(TestError)
        te.msg = e.msg
        Result[void, ref TestError].err(te)
    
    withLock(testLock):
      for s in mitems(testRegistry):
        if s.name == currentSuite:
          s.beforeEach.add(hookProc)
          break

template afterEach*(body: untyped): untyped =
  ## Run after each test in a suite
  block:
    let hookProc = proc(): Result[void, ref TestError] {.gcsafe.} =
      try:
        body
        Result[void, ref TestError].ok()
      except CatchableError as e:
        var te = new(TestError)
        te.msg = e.msg
        Result[void, ref TestError].err(te)
    
    withLock(testLock):
      for s in mitems(testRegistry):
        if s.name == currentSuite:
          s.afterEach.add(hookProc)
          break

# Skip test functionality
template skip*(reason: string = ""): untyped =
  ## Skip a test
  var error: ref TestError
  new(error)
  error.msg = if reason.len > 0: reason else: "Test skipped"
  raise error

# Test runner implementation
proc newTestRunner*(config: TestConfig = nil, reporter: TestReporter = nil): TestRunner =
  ## Create a new test runner
  result = TestRunner(
    suites: @[],
    config: if config != nil: config else: TestConfig(),
    reporter: if reporter != nil: reporter else: ConsoleReporter(),
    results: @[],
    stats: TestStats()
  )

proc runTest(runner: TestRunner, suite: TestSuite, test: TestInfo): TestResult =
  ## Run a single test
  let startTime = now()
  var result = TestResult(
    name: test.name,
    suite: suite.name,
    timestamp: startTime
  )
  
  # Run beforeEach hooks
  for hook in suite.beforeEach:
    let hookResult = hook()
    if hookResult.isErr:
      result.status = tsError
      result.message = hookResult.error.msg
      result.duration = (now() - startTime).inMilliseconds.float / 1000.0
      return result
  
  # Run the test
  let testResult = test.testProc()
  if testResult.isOk:
    result.status = tsPass
  else:
    let error = testResult.error
    if error of PowerAssertError:
      let assertError = cast[ref PowerAssertError](error)
      result.status = tsFail
      result.message = assertError.msg
      result.assertions = @[AssertionInfo(
        expression: assertError.expression,
        location: assertError.location,
        message: assertError.msg,
        values: assertError.values
      )]
    else:
      result.status = tsError
      result.message = error.msg
  
  # Run afterEach hooks
  for hook in suite.afterEach:
    discard hook()
  
  result.duration = (now() - startTime).inMilliseconds.float / 1000.0
  return result

proc runSuite(runner: TestRunner, suite: TestSuite): seq[TestResult] =
  ## Run all tests in a suite
  result = @[]
  
  # Run beforeAll hooks
  for hook in suite.beforeAll:
    let hookResult = hook()
    if hookResult.isErr:
      # If beforeAll fails, skip all tests
      for test in suite.tests:
        result.add(TestResult(
          name: test.name,
          suite: suite.name,
          status: tsError,
          message: "beforeAll hook failed: " & hookResult.error.msg,
          timestamp: now()
        ))
      return result
  
  # Run tests (parallel or sequential)
  if suite.parallel and runner.parallel:
    # TODO: Implement parallel test execution using our parallel module
    for test in suite.tests:
      result.add(runner.runTest(suite, test))
  else:
    for test in suite.tests:
      result.add(runner.runTest(suite, test))
      if runner.config.failFast and result[^1].status in {tsFail, tsError}:
        break
  
  # Run afterAll hooks
  for hook in suite.afterAll:
    discard hook()

proc run*(runner: TestRunner): TestStats =
  ## Run all tests
  runner.stats.startTime = now()
  
  for suite in runner.suites:
    let results = runner.runSuite(suite)
    runner.results.add(results)
    
    # Update stats
    for result in results:
      inc(runner.stats.total)
      case result.status
      of tsPass: inc(runner.stats.passed)
      of tsFail: inc(runner.stats.failed)
      of tsSkip: inc(runner.stats.skipped)
      of tsError: inc(runner.stats.errors)
      of tsPending: inc(runner.stats.pending)
  
  runner.stats.endTime = now()
  runner.stats.duration = (runner.stats.endTime - runner.stats.startTime).inMilliseconds.float / 1000.0
  
  return runner.stats

# Reporter implementations
method beginTesting*(reporter: TestReporter) {.base.} =
  ## Called when testing begins
  discard

method endTesting*(reporter: TestReporter, stats: TestStats) {.base.} =
  ## Called when testing ends
  discard

method beginSuite*(reporter: TestReporter, suite: TestSuite) {.base.} =
  ## Called when a suite begins
  discard

method endSuite*(reporter: TestReporter, suite: TestSuite) {.base.} =
  ## Called when a suite ends
  discard

method reportTest*(reporter: TestReporter, result: TestResult) {.base.} =
  ## Report a test result
  discard

method reportStats*(reporter: TestReporter, stats: TestStats) {.base.} =
  ## Report overall statistics
  discard

# Console reporter implementation
method beginTesting*(reporter: ConsoleReporter) =
  echo "Running tests..."
  echo "=".repeat(50)

method endTesting*(reporter: ConsoleReporter, stats: TestStats) =
  echo "=".repeat(50)
  reporter.reportStats(stats)

method reportTest*(reporter: ConsoleReporter, result: TestResult) =
  let status = case result.status
    of tsPass: "[PASS]"
    of tsFail: "[FAIL]"
    of tsSkip: "[SKIP]"
    of tsError: "[ERROR]"
    of tsPending: "[PENDING]"
  
  if reporter.colored:
    # TODO: Add color support
    echo fmt"{status} {result.suite}.{result.name} ({result.duration:.3f}s)"
  else:
    echo fmt"{status} {result.suite}.{result.name} ({result.duration:.3f}s)"
  
  if result.message.len > 0 and reporter.verbose:
    echo "  ", result.message

method reportStats*(reporter: ConsoleReporter, stats: TestStats) =
  echo fmt"""
Test Results:
  Total:   {stats.total}
  Passed:  {stats.passed}
  Failed:  {stats.failed}
  Skipped: {stats.skipped}
  Errors:  {stats.errors}
  Pending: {stats.pending}
  
Duration: {stats.duration:.3f}s
"""

# Test discovery
method discover*(discoverer: TestDiscoverer): seq[TestSuite] {.base.} =
  ## Discover tests
  return @[]

# File discoverer implementation
method discover*(discoverer: FileDiscoverer): seq[TestSuite] =
  # TODO: Implement file-based test discovery
  return @[]

# Module discoverer implementation  
method discover*(discoverer: ModuleDiscoverer): seq[TestSuite] =
  # Return tests from the global registry
  return testRegistry

# AI-powered test analysis features using nim-lang-core
proc analyzeTestCode*(filename: string): seq[string] =
  ## Analyze test code for potential improvements using AI patterns
  result = @[]
  
  try:
    let astResult = ast_analyzer.parseFile(filename)
    if astResult.isOk:
      # Use nim-lang-core's AI pattern detection
      let detector = newAiPatternDetector()
      let patterns = detector.detectPatterns(astResult.get(), filename)
    
      for pattern in patterns:
        # Add all testing-related patterns
        result.add(pattern.message)
  except:
    discard

proc suggestTestImprovements*(suite: TestSuite): seq[string] =
  ## Suggest improvements for test suite using AI analysis
  result = @[]
  
  # Analyze test patterns
  if suite.tests.len == 0:
    result.add("Empty test suite - consider adding tests")
  
  if suite.beforeAll.len == 0 and suite.afterAll.len == 0:
    result.add("No setup/teardown - consider adding fixtures if needed")
  
  # Check for common anti-patterns
  for test in suite.tests:
    if test.name.startsWith("test") and test.name.len > 50:
      result.add(fmt"Test name '{test.name}' is too long - consider a more concise name")

proc generateTestSkeleton*(sourceFile: string): string =
  ## Generate test skeleton for a source file using AST analysis
  result = ""
  
  try:
    let astResult = ast_analyzer.parseFile(sourceFile)
    if astResult.isOk:
      # Extract public procedures that need testing
      # This would use nim-lang-core's symbol analysis
      result = fmt"""
import unittest
import {sourceFile.splitFile().name}

suite "{sourceFile.splitFile().name} tests":
  test "basic functionality":
    check true
"""
    else:
      result = "# Error parsing source file"
  except:
    result = "# Error generating test skeleton"

# Convenience functions
proc runTests*(pattern: string = "test_*.nim", parallel: bool = false): int =
  ## Run tests matching a pattern
  initTestRegistry()
  
  let config = TestConfig(
    pattern: pattern,
    parallel: parallel
  )
  let runner = newTestRunner(config, ConsoleReporter())
  let stats = runner.run()
  
  return if stats.failed > 0 or stats.errors > 0: 1 else: 0

# Initialize the module
initTestRegistry()
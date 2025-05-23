## test_testing_simple.nim
## ======================
##
## Simple tests for the testing module

import ../src/nim_libaspects/testing
import std/[strformat, tables, sets, strutils, times]

# Test basic types
block testStatusEnum:
  doAssert $tsPass == "tsPass"
  doAssert $tsFail == "tsFail"
  doAssert $tsSkip == "tsSkip"
  doAssert $tsError == "tsError"
  doAssert $tsPending == "tsPending"
  echo "✓ TestStatus enum test passed"

# Test TestResult creation
block testResultCreation:
  let result = TestResult(
    name: "test_example",
    suite: "ExampleSuite",
    status: tsPass,
    message: "",
    duration: 0.123,
    timestamp: now()
  )
  doAssert result.name == "test_example"
  doAssert result.suite == "ExampleSuite"
  doAssert result.status == tsPass
  doAssert result.duration == 0.123
  echo "✓ TestResult creation test passed"

# Test TestConfig
block testConfigCreation:
  var tags = initHashSet[string]()
  tags.incl("integration")
  var excludeTags = initHashSet[string]()
  excludeTags.incl("slow")
  
  let config = TestConfig(
    pattern: "test_*.nim",
    tags: tags,
    excludeTags: excludeTags,
    parallel: true,
    maxWorkers: 4,
    timeout: 30000,
    verbosity: 2,
    outputDir: "./test-results",
    failFast: true
  )
  doAssert config.pattern == "test_*.nim"
  doAssert "integration" in config.tags
  doAssert "slow" in config.excludeTags
  doAssert config.parallel
  doAssert config.maxWorkers == 4
  echo "✓ TestConfig creation test passed"

# Test PowerAssertError
block testPowerAssertError:
  let error = PowerAssertError(
    expression: "x == y",
    values: @[("x", "10"), ("y", "20")],
    location: "file.nim:42",
    msg: "Values don't match"
  )
  doAssert error.expression == "x == y"
  doAssert error.values.len == 2
  doAssert error.values[0] == ("x", "10")
  doAssert error.values[1] == ("y", "20")
  doAssert error.location == "file.nim:42"
  doAssert error.msg == "Values don't match"
  echo "✓ PowerAssertError test passed"

# Test reporters
block testReporters:
  let consoleReporter = ConsoleReporter(
    colored: true,
    verbose: true
  )
  doAssert consoleReporter.colored
  doAssert consoleReporter.verbose
  
  let jsonReporter = JsonReporter(
    outputFile: "results.json",
    pretty: true
  )
  doAssert jsonReporter.outputFile == "results.json"
  doAssert jsonReporter.pretty
  
  let htmlReporter = HtmlReporter(
    outputFile: "results.html",
    cssFile: "style.css",
    title: "Test Results"
  )
  doAssert htmlReporter.outputFile == "results.html"
  doAssert htmlReporter.cssFile == "style.css"
  doAssert htmlReporter.title == "Test Results"
  echo "✓ Reporters test passed"

# Test discoverers
block testDiscoverers:
  let fileDiscoverer = FileDiscoverer(
    pattern: "test_*.nim",
    rootDir: "./tests"
  )
  doAssert fileDiscoverer.pattern == "test_*.nim"
  doAssert fileDiscoverer.rootDir == "./tests"
  
  let moduleDiscoverer = ModuleDiscoverer(
    modules: @["test_module1", "test_module2"]
  )
  doAssert moduleDiscoverer.modules.len == 2
  doAssert moduleDiscoverer.modules[0] == "test_module1"
  echo "✓ Discoverers test passed"

# Test runner creation
block testRunner:
  let config = TestConfig()
  let reporter = ConsoleReporter()
  let runner = newTestRunner(config, reporter)
  doAssert runner.config == config
  doAssert runner.reporter == reporter
  doAssert runner.results.len == 0
  doAssert runner.suites.len == 0
  echo "✓ TestRunner creation test passed"

# Test assertions
block testAssertions:
  # Test check assertion
  var raised = false
  try:
    check(false, "Should fail")
  except PowerAssertError as e:
    raised = true
    doAssert e.msg == "Should fail"
  doAssert raised, "check should have raised PowerAssertError"
  
  # Test expect assertion
  raised = false
  try:
    expect(42, 43)
  except PowerAssertError as e:
    raised = true
    doAssert e.msg == "Expected 42, got 43"
    doAssert e.values.len == 2
  doAssert raised, "expect should have raised PowerAssertError"
  
  # Test expectError assertion
  raised = false
  try:
    expectError(ValueError):
      discard  # No error raised
  except PowerAssertError as e:
    raised = true
    doAssert "Expected ValueError, but no error was raised" in e.msg
  doAssert raised, "expectError should have raised PowerAssertError"
  
  echo "✓ Assertions test passed"

echo "\nAll tests passed successfully!"
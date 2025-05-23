## test_testing_unit.nim
## ====================
##
## Unit tests for the testing module

import unittest
import ../src/nim_libaspects/testing as nimtest
import std/[strformat, tables, sets, strutils]

# Use standard unittest for testing our testing module
suite "Testing module types":
  test "TestResult creation":
    let result = nimtest.TestResult(
      name: "test_example",
      suite: "ExampleSuite",
      status: nimtest.tsPass,
      message: "",
      duration: 0.123,
      timestamp: now()
    )
    check result.name == "test_example"
    check result.suite == "ExampleSuite"
    check result.status == nimtest.tsPass
    check result.duration == 0.123

  test "TestStatus enum":
    check $nimtest.tsPass == "tsPass"
    check $nimtest.tsFail == "tsFail"
    check $nimtest.tsSkip == "tsSkip"
    check $nimtest.tsError == "tsError"
    check $nimtest.tsPending == "tsPending"

  test "TestInfo creation":
    var tags = initHashSet[string]()
    tags.incl("fast")
    tags.incl("unit")
    
    let info = nimtest.TestInfo(
      name: "test_something",
      suite: "MySuite",
      filename: "test_file.nim",
      lineNumber: 42,
      tags: tags,
      timeout: 5000
    )
    check info.name == "test_something"
    check info.suite == "MySuite"
    check info.filename == "test_file.nim"
    check info.lineNumber == 42
    check "fast" in info.tags
    check "unit" in info.tags
    check info.timeout == 5000

  test "TestSuite structure":
    var tags = initHashSet[string]()
    tags.incl("unit")
    let suite = nimtest.TestSuite(
      name: "TestSuite",
      tests: @[],
      beforeAll: @[],
      afterAll: @[],
      beforeEach: @[],
      afterEach: @[],
      parallel: false,
      tags: tags
    )
    check suite.name == "TestSuite"
    check suite.tests.len == 0
    check not suite.parallel
    check "unit" in suite.tags

  test "TestConfig creation":
    var tags = initHashSet[string]()
    tags.incl("integration")
    var excludeTags = initHashSet[string]()
    excludeTags.incl("slow")
    
    let config = nimtest.TestConfig(
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
    check config.pattern == "test_*.nim"
    check "integration" in config.tags
    check "slow" in config.excludeTags
    check config.parallel
    check config.maxWorkers == 4

suite "Testing module assertions":
  test "PowerAssertError creation":
    let error = nimtest.PowerAssertError(
      expression: "x == y",
      values: @[("x", "10"), ("y", "20")],
      location: "file.nim:42",
      msg: "Values don't match"
    )
    check error.expression == "x == y"
    check error.values.len == 2
    check error.values[0] == ("x", "10")
    check error.values[1] == ("y", "20")
    check error.location == "file.nim:42"
    check error.msg == "Values don't match"

  test "AssertionInfo structure":
    let info = nimtest.AssertionInfo(
      expression: "a > b",
      location: "test.nim:100",
      message: "Comparison failed",
      values: @[("a", "5"), ("b", "10")]
    )
    check info.expression == "a > b"
    check info.location == "test.nim:100"
    check info.message == "Comparison failed"
    check info.values.len == 2

suite "Testing module reporters":
  test "ConsoleReporter creation":
    let reporter = nimtest.ConsoleReporter(
      colored: true,
      verbose: true
    )
    check reporter.colored
    check reporter.verbose

  test "JsonReporter creation":
    let reporter = nimtest.JsonReporter(
      outputFile: "results.json",
      pretty: true
    )
    check reporter.outputFile == "results.json"
    check reporter.pretty

  test "HtmlReporter creation":
    let reporter = nimtest.HtmlReporter(
      outputFile: "results.html",
      cssFile: "style.css",
      title: "Test Results"
    )
    check reporter.outputFile == "results.html"
    check reporter.cssFile == "style.css"
    check reporter.title == "Test Results"

suite "Testing module discoverers":
  test "FileDiscoverer creation":
    let discoverer = nimtest.FileDiscoverer(
      pattern: "test_*.nim",
      rootDir: "./tests"
    )
    check discoverer.pattern == "test_*.nim"
    check discoverer.rootDir == "./tests"

  test "ModuleDiscoverer creation":
    let discoverer = nimtest.ModuleDiscoverer(
      modules: @["test_module1", "test_module2"]
    )
    check discoverer.modules.len == 2
    check discoverer.modules[0] == "test_module1"
    check discoverer.modules[1] == "test_module2"

suite "Testing module runner":
  test "TestRunner creation":
    let config = nimtest.TestConfig()
    let reporter = nimtest.ConsoleReporter()
    let runner = nimtest.newTestRunner(config, reporter)
    check runner.config == config
    check runner.reporter == reporter
    check runner.results.len == 0
    check runner.suites.len == 0

  test "TestStats initialization":
    var stats = nimtest.TestStats(
      total: 10,
      passed: 6,
      failed: 2,
      skipped: 1,
      errors: 1,
      pending: 0
    )
    check stats.total == 10
    check stats.passed == 6
    check stats.failed == 2
    check stats.skipped == 1
    check stats.errors == 1
    check stats.pending == 0
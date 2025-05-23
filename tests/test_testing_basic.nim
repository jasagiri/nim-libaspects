## test_testing_basic.nim
## =====================
##
## Basic tests for the testing module

import ../src/nim_libaspects/testing as nim_test
import std/[strformat, tables, sets, strutils]

# Use our testing framework for its own tests!
nim_test.suite "Testing Module":
  nim_test.test "Basic check assertion":
    var raised = false
    try:
      nim_test.check(true, "Should pass")
    except PowerAssertError:
      raised = true
    assert(not raised)
    
    raised = false
    try:
      nim_test.check(false, "Should fail")
    except PowerAssertError as e:
      raised = true
      assert(e.msg == "Should fail")
    assert(raised)

  nim_test.test "Expect assertion":
    var raised = false
    try:
      nim_test.expect(42, 42)
    except PowerAssertError:
      raised = true
    assert(not raised)
    
    raised = false
    try:
      nim_test.expect(42, 43)
    except PowerAssertError as e:
      raised = true
      assert(e.msg == "Expected 42, got 43")
      assert(e.values.len == 2)
      assert(e.values[0] == ("expected", "42"))
      assert(e.values[1] == ("actual", "43"))
    assert(raised)

  nim_test.test "ExpectError assertion":
    var raised = false
    try:
      nim_test.expectError(ValueError):
        raise newException(ValueError, "Test error")
    except PowerAssertError:
      raised = true
    assert(not raised)
    
    raised = false
    try:
      nim_test.expectError(ValueError):
        # No error raised
        discard
    except PowerAssertError as e:
      raised = true
      assert("Expected ValueError" in e.msg)
    assert(raised)
    
    raised = false
    try:
      nim_test.expectError(ValueError):
        raise newException(IOError, "Wrong error")
    except PowerAssertError as e:
      raised = true
      assert("Expected ValueError, got IOError" in e.msg)
    assert(raised)

  nim_test.test "Test status enum":
    assert($nim_test.tsPass == "tsPass")
    assert($nim_test.tsFail == "tsFail")
    assert($nim_test.tsSkip == "tsSkip")
    assert($nim_test.tsError == "tsError")
    assert($nim_test.tsPending == "tsPending")

  nim_test.test "TestResult creation":
    let result = nim_test.TestResult(
      name: "test_example",
      suite: "ExampleSuite",
      status: nim_test.tsPass,
      message: "",
      duration: 0.123,
      timestamp: now()
    )
    assert(result.name == "test_example")
    assert(result.suite == "ExampleSuite")
    assert(result.status == nim_test.tsPass)
    assert(result.duration == 0.123)

when isMainModule:
  # Run our tests using our own runner
  let config = nim_test.TestConfig(
    pattern: "test_*.nim",
    parallel: false
  )
  let runner = nim_test.newTestRunner(config, nim_test.ConsoleReporter(colored: false, verbose: true))
  let discoverer = nim_test.ModuleDiscoverer()
  runner.suites = discoverer.discover()
  let stats = runner.run()
  
  echo fmt"\nTest Summary: {stats.passed}/{stats.total} passed"
  if stats.failed > 0:
    echo fmt"Failed: {stats.failed}"
  if stats.errors > 0:
    echo fmt"Errors: {stats.errors}"
  
  quit(if stats.failed > 0 or stats.errors > 0: 1 else: 0)
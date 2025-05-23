## test_testing_integration.nim
## ==========================
##
## Integration tests for the testing module showing actual usage

import ../src/nim_libaspects/testing
import std/[strformat, os, json]

# Example of using the testing module
suite "Math Operations":
  var setupValue: int
  
  beforeAll:
    # This runs once before all tests in the suite
    echo "Setting up Math Operations suite"
    setupValue = 42
  
  afterAll:
    # This runs once after all tests in the suite
    echo "Tearing down Math Operations suite"
  
  beforeEach:
    # This runs before each test
    echo "Before each test"
  
  afterEach:
    # This runs after each test
    echo "After each test"
  
  test "Addition":
    check(1 + 1 == 2)
    check(setupValue == 42)
    expect(4, 2 + 2)
  
  test "Subtraction":
    check(5 - 3 == 2)
    expect(0, 10 - 10)
  
  test "Multiplication":
    check(3 * 4 == 12)
    expect(21, 7 * 3)
  
  test "Division":
    check(10 div 2 == 5)
    expectError(DivByZeroDefect):
      discard 5 div 0
  
  test "Skipped test":
    skip("Not implemented yet")
    check(false)  # This should not be executed

suite "String Operations":
  test "Concatenation":
    let result = "Hello" & " " & "World"
    expect("Hello World", result)
  
  test "Length":
    check("test".len == 4)
    expect(0, "".len)
  
  test "Contains":
    check("Hello World".contains("World"))
    check(not "Hello World".contains("Goodbye"))

# Example of parallel test suite
suite "Parallel Tests":
  # Mark this suite for parallel execution
  # Note: In real implementation, this would be set via suite options
  
  test "Parallel Test 1":
    os.sleep(100)  # Simulate some work
    check(true)
  
  test "Parallel Test 2":
    os.sleep(100)  # Simulate some work
    check(true)
  
  test "Parallel Test 3":
    os.sleep(100)  # Simulate some work
    check(true)

# Example of a failing test suite to demonstrate error reporting
suite "Failing Tests":
  test "Assertion failure":
    expect(10, 5 + 6)  # This will fail
  
  test "Check failure":
    check(false, "This should fail")
  
  test "Error in test":
    raise newException(ValueError, "Simulated error")
  
  test "Wrong exception type":
    expectError(IOError):
      raise newException(ValueError, "Wrong type")

# Example custom reporter
type
  CustomReporter = ref object of TestReporter
    results: seq[TestResult]

method reportTest*(reporter: CustomReporter, result: TestResult) =
  reporter.results.add(result)

method endTesting*(reporter: CustomReporter, stats: TestStats) =
  echo "\nCustom Report Summary:"
  echo fmt"Total tests: {stats.total}"
  echo fmt"Success rate: {float(stats.passed) / float(stats.total) * 100:.1f}%"
  
  if stats.failed > 0:
    echo "\nFailed tests:"
    for result in reporter.results:
      if result.status == tsFail:
        echo fmt"  - {result.suite}.{result.name}: {result.message}"

# Main test runner
when isMainModule:
  # Initialize the testing system
  initTestRegistry()
  
  # Create configurations for different scenarios
  let basicConfig = TestConfig(
    pattern: "test_*.nim",
    parallel: false,
    verbosity: 1,
    failFast: false
  )
  
  let parallelConfig = TestConfig(
    pattern: "test_*.nim",
    parallel: true,
    maxWorkers: 4,
    verbosity: 2
  )
  
  # Create different reporters
  let consoleReporter = ConsoleReporter(colored: true, verbose: true)
  let jsonReporter = JsonReporter(outputFile: "test-results.json", pretty: true)
  let customReporter = CustomReporter(results: @[])
  
  # Example 1: Run with console reporter
  echo "=== Running with Console Reporter ==="
  var runner = newTestRunner(basicConfig, consoleReporter)
  let discoverer = ModuleDiscoverer()
  runner.suites = discoverer.discover()
  let stats1 = runner.run()
  
  # Example 2: Run with custom reporter
  echo "\n=== Running with Custom Reporter ==="
  runner = newTestRunner(basicConfig, customReporter)
  runner.suites = discoverer.discover()
  let stats2 = runner.run()
  
  # Example 3: Save results as JSON
  echo "\n=== Saving JSON Results ==="
  let jsonData = %*{
    "stats": {
      "total": stats1.total,
      "passed": stats1.passed,
      "failed": stats1.failed,
      "skipped": stats1.skipped,
      "errors": stats1.errors,
      "duration": stats1.duration
    },
    "results": runner.results.mapIt(%*{
      "name": it.name,
      "suite": it.suite,
      "status": $it.status,
      "message": it.message,
      "duration": it.duration
    })
  }
  
  writeFile("test-results.json", jsonData.pretty())
  echo "Results saved to test-results.json"
  
  # Exit with appropriate code
  quit(if stats1.failed > 0 or stats1.errors > 0: 1 else: 0)
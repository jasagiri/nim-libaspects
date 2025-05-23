# Testing Module

The testing module provides a comprehensive test framework with assertions, runners, and various reporters. When integrated with nim-lang-core, it offers AI-powered test analysis and generation capabilities.

## Features

- Enhanced assertions with detailed error messages
- Test organization with suites and fixtures
- Multiple output formats (console, JSON, HTML)
- Test lifecycle hooks (beforeAll, afterAll, beforeEach, afterEach)
- Parallel test execution support
- **AI-powered test analysis** (with nim-lang-core)
- **Automatic test skeleton generation** (with nim-lang-core)

## Basic Usage

```nim
import nim_libaspects/testing

suite "Math Operations":
  var counter: int
  
  beforeAll:
    counter = 0
    echo "Setting up suite"
  
  beforeEach:
    inc(counter)
  
  test "Addition":
    check(1 + 1 == 2)
    expect(4, 2 + 2)
  
  test "Division by zero":
    expectError(DivByZeroDefect):
      discard 1 div 0
```

## Enhanced Features with nim-lang-core

### Test Code Analysis

Analyze existing test files for potential improvements:

```nim
let suggestions = analyzeTestCode("tests/my_test.nim")
for suggestion in suggestions:
  echo "Improvement: ", suggestion
```

Common suggestions include:
- Missing test coverage for public procedures
- Test naming conventions
- Duplicate test logic
- Missing assertions

### Test Generation

Generate test skeletons from source files:

```nim
let skeleton = generateTestSkeleton("src/mymodule.nim")
writeFile("tests/test_mymodule.nim", skeleton)
```

The generated skeleton includes:
- Import statements
- Test suite structure
- Test cases for each public procedure
- Basic assertions to get started

### Test Suite Analysis

Get AI-powered suggestions for test suite improvements:

```nim
let suite = TestSuite(name: "MyTests", tests: @[...])
let improvements = suggestTestImprovements(suite)

for improvement in improvements:
  echo improvement
```

Suggestions include:
- Missing setup/teardown fixtures
- Test organization improvements
- Performance optimizations for test execution

## Reporters

### Console Reporter

```nim
let reporter = ConsoleReporter(
  colored: true,
  verbose: true
)
```

### JSON Reporter

```nim
let reporter = JsonReporter(
  outputFile: "test-results.json",
  pretty: true
)
```

### HTML Reporter

```nim
let reporter = HtmlReporter(
  outputFile: "test-report.html",
  includeSource: true
)
```

## Test Configuration

```nim
let config = TestConfig(
  pattern: "test_*.nim",
  tags: toHashSet(["unit", "fast"]),
  parallel: true,
  maxWorkers: 4,
  timeout: 5000,
  failFast: false
)

let runner = newTestRunner(config, reporter)
let stats = runner.run()
```

## Power Assertions

The testing module provides enhanced assertions that show detailed information on failure:

```nim
test "Complex assertion":
  let x = 10
  let y = 20
  let z = 30
  
  check(x + y == z)
  # On failure, shows:
  # Assertion failed: x + y == z
  # Values: x=10, y=20, x+y=30, z=30
```

## Best Practices

1. **Use descriptive test names**: Test names should clearly describe what is being tested
2. **One assertion per test**: Keep tests focused on a single behavior
3. **Use fixtures appropriately**: Setup and teardown should handle shared state
4. **Tag tests**: Use tags to organize and filter tests
5. **Leverage AI analysis**: Regularly analyze test code for improvements

## API Reference

See the main README for complete API documentation.
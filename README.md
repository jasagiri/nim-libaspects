# nim-libaspects

Shared library modules for Nim development tools. This package provides common functionality extracted from various Nim tooling projects to promote code reuse and maintainability.

## Features

### Logging Module (`nim_libaspects/logging`)
- Structured logging with multiple log levels (Debug, Info, Warn, Error, Fatal)
- Multiple handler support (Console, File)
- Flexible formatters (Text, JSON)
- Field-based logging for structured data
- Level-based filtering
- Module-level convenience functions

### Errors Module (`nim_libaspects/errors`)
- Enhanced Result[T,E] type with functional operations
- Comprehensive error type hierarchy
- Error context with stack trace support
- Result type utilities (map, flatMap, recover, combine)
- Validation utilities
- Stack trace capture (debug mode)

### Config Module (`nim_libaspects/config`)
- Configuration management from multiple sources
- Support for JSON and TOML files
- Environment variable loading with prefix support
- Command line argument parsing
- Cascading configuration (defaults < files < env < CLI)
- Type-safe value access with automatic conversions
- Nested configuration sections

### Transport Module (`nim_libaspects/transport`)
- Unified transport layer for protocol communication (LSP, DAP, etc.)
- Standard I/O transport for stdio-based communication
- Socket transport for TCP client connections
- Server transport for accepting TCP connections
- Header-based message framing with Content-Length support
- Async/await based API for all operations
- Integration with logging module for debugging
- Stream utilities for testing and file operations

### Parallel Module (`nim_libaspects/parallel`)
- Parallel task execution with dependency management
- Priority-based task scheduling
- Task categories for different workload types (CPU, I/O, Network, Memory)
- Automatic dependency resolution
- Task cancellation and error handling
- Built-in retry support with configurable delays
- Statistics collection for performance monitoring
- Thread pool management with worker limits
- Support for complex dependency graphs
- Result type integration for safe error handling

### Process Module (`nim_libaspects/process`)
- Cross-platform process spawning and management
- Synchronous and asynchronous process execution  
- Process builder pattern for fluent API
- Timeout support for long-running processes
- Environment variable management
- Working directory control
- Shell command execution with proper escaping
- Process manager for tracking multiple processes
- Platform-specific utilities (find executable, shell detection)
- Signal handling on Unix platforms
- Comprehensive error handling with Result types

### Testing Module (`nim_libaspects/testing`)
- Comprehensive test framework with assertions and runners
- Enhanced assertions with detailed error messages
- Test organization with suites and fixtures
- Multiple reporters (Console, JSON, HTML)
- Test lifecycle hooks (beforeAll, afterAll, beforeEach, afterEach)
- Test discovery from files and modules
- Parallel test execution support
- Test filtering by tags and patterns
- Integration with existing unittest framework
- Result statistics and reporting

### Metrics Module (`nim_libaspects/metrics`)
- Performance metrics collection framework
- Counters, gauges, and histograms
- Thread-safe operations
- Aggregation and reporting
- Customizable metric naming
- JSON export capability

### Reporting Module (`nim_libaspects/reporting`)
- Report generation framework
- Multiple output formats (Markdown, HTML, JSON)
- Template-based report generation
- Progress reporting during long operations
- Report sections with metadata
- Aggregation of multiple reports

### Events Module (`nim_libaspects/events`)
- Event-driven architecture with EventBus
- Publish/subscribe pattern with pattern matching
- Event filtering and routing
- Priority-based event handling
- Middleware support for event processing
- Asynchronous event handling
- Event persistence and replay
- Event aggregation for batch processing
- Namespace support for event isolation

### Monitoring Module (`nim_libaspects/monitoring`)
- Comprehensive monitoring system
- Health check endpoints with async execution
- Application state monitoring and tracking
- Resource monitoring (CPU, memory, disk, custom)
- Alert functionality with rule-based conditions
- Dashboard integration with real-time data
- Custom metrics support (counters, gauges, histograms)
- Lifecycle hooks and event notifications
- State persistence and restoration

### Logging-Metrics Module (`nim_libaspects/logging_metrics`)
- Seamless integration between logging and metrics
- Automatic metrics extraction from log events
- Performance tracking (duration, response times)
- Error rate monitoring and tracking
- Custom metrics extractors with pattern matching
- Module-specific metrics collection
- Export formats support (JSON, Prometheus, Graphite)

### Notifications Module (`nim_libaspects/notifications`)
- Multi-channel notification framework
- Channel abstraction for various providers
- Email, Slack, Discord, and Webhook channels
- Template-based message generation
- Rule-based routing to channels
- Retry mechanism with exponential backoff
- Rate limiting per channel
- Notification aggregation
- Asynchronous sending

## Installation

```bash
nimble install nim_libaspects
```

### nim-lang-core Integration (Optional)

For enhanced AI-powered features, nim-libaspects can integrate with [nim-lang-core](https://github.com/jasagiri/nim-lang-core):

1. Clone nim-lang-core adjacent to nim-libaspects:
```bash
git clone https://github.com/jasagiri/nim-lang-core ../nim-lang-core
```

2. The integration is automatically enabled via `nim.cfg` which adds nim-lang-core to the search path.

This integration provides:
- 🤖 AI-powered code analysis and pattern detection
- 📊 Enhanced performance profiling with optimization suggestions
- 🔍 Intelligent configuration validation
- 🚀 Optimized AST caching

#### Quick Start with nim-lang-core

```nim
import nim_libaspects/[testing, config, profiler, cache]

# AI-powered test analysis
let suggestions = analyzeTestCode("test.nim")

# Config validation
let config = newConfig()
let improvements = config.suggestConfigImprovements()

# Performance analysis
let profiler = newProfiler()
let hotspots = profiler.analyzePerformanceHotspots("code.nim")

# Enhanced caching
let cache = newNimCoreCache[string, string](1000)
```

See the [integration guide](docs/nim_core_integration.md) for detailed examples.

## Usage

### Logging Example

```nim
import nim_libaspects/logging

# Create a logger
let logger = newLogger("MyApp")
logger.addHandler(newConsoleHandler())
logger.setLevel(lvlInfo)

# Log messages
logger.info("Application started")
logger.error("Something went wrong", %*{"error_code": 500})

# Module-level functions
info("Quick info message")
```

### Errors Example

```nim
import nim_libaspects/errors

# Use Result type
proc divide(a, b: int): Result[float, string] =
  if b == 0:
    Result[float, string].err("Division by zero")
  else:
    Result[float, string].ok(a.float / b.float)

# Use functional operations
let result = divide(10, 2)
  .mapResult(proc(x: float): string = $x)
  .recoverResult("Error")

# Error context
let error = newValidationError("Invalid email", "email")
```

### Config Example

```nim
import nim_libaspects/config

# Create config with environment variable prefix
let config = newConfig(envPrefix = "MYAPP_")

# Load from different sources (cascading priority)
config.setDefault("port", 8080)
discard config.loadJson("config.json")
discard config.loadEnv()
discard config.loadCommandLine()

# Access values with type conversions
let port = config.getInt("port")
let host = config.getString("host", "localhost")
let debug = config.getBool("debug", false)

# Nested configuration
let serverConfig = config.getSection("server")
if serverConfig.isOk:
  let timeout = serverConfig.get().getInt("timeout", 30)
```

### Transport Example

```nim
import nim_libaspects/transport
import asyncdispatch

# Stdio transport for LSP/DAP protocols
let stdioTransport = newStdioTransport()
waitFor stdioTransport.start()

# Send a message
let message = %*{"jsonrpc": "2.0", "method": "initialize", "id": 1}
waitFor stdioTransport.sendMessage(message)

# Receive a message
let response = waitFor stdioTransport.receiveMessage()

# Socket transport for network communication
let socketTransport = newSocketTransport("localhost", 9999)
waitFor socketTransport.start()

# Server transport for accepting connections
let serverTransport = newServerTransport("0.0.0.0", 8080)
waitFor serverTransport.start()  # Waits for client to connect
```

### Parallel Example

```nim
import nim_libaspects/parallel

# Create executor with custom configuration
let config = ExecutorConfig(
  workerCount: 4,
  enableDependencies: true,
  enablePriorities: true
)
let executor = newParallelExecutor(config)

# Define tasks
proc downloadData(): Result[string, ref AppError] {.thread.} =
  # Simulated download task
  Result[string, ref AppError].ok("data downloaded")

proc processData(): Result[string, ref AppError] {.thread.} =
  # Simulated processing task
  Result[string, ref AppError].ok("data processed")

# Create task specifications
let downloadSpec = newTaskSpec(
  id = "download",
  priority = tpHigh,
  category = tcNetwork
)

let processSpec = newTaskSpec(
  id = "process",
  priority = tpNormal,
  category = tcCPU,
  dependencies = @["download"]  # Depends on download finishing
)

# Add tasks to executor
discard executor.addTask(downloadSpec, downloadData)
discard executor.addTask(processSpec, processData)

# Run until completion
let stats = executor.runUntilComplete()
echo "Tasks completed: ", stats.tasksCompleted
echo "Tasks failed: ", stats.tasksFailed

# Simple parallel execution
let tasks = @[
  ("task1", proc(): Result[string, ref AppError] {.thread.} = 
    Result[string, ref AppError].ok("Task 1 done")),
  ("task2", proc(): Result[string, ref AppError] {.thread.} = 
    Result[string, ref AppError].ok("Task 2 done"))
]

let results = runParallel(tasks)
for result in results:
  echo result.taskId, ": ", result.status
```

### Process Example

```nim
import nim_libaspects/process

# Simple command execution
let result = exec("echo", @["Hello from process"])
if result.isOk:
  echo result.get().output

# Process builder pattern
var builder = newProcessBuilder("git")
discard builder.args("status", "--short")
  .workingDir("/path/to/repo")
  .captureOutput(true)
  .timeout(5000)

let gitResult = builder.run()
if gitResult.isOk:
  echo "Git status: ", gitResult.get().output

# Shell command execution
let shellResult = execShell("ls -la | grep nim")
if shellResult.isOk:
  echo shellResult.get().output

# Process manager for multiple processes
let manager = newProcessManager()

# Start a long-running process
let options = ProcessOptions(
  command: "python",
  args: @["-m", "http.server", "8080"],
  captureOutput: false
)

let processId = manager.start(options)
if processId.isOk:
  echo "Started server with ID: ", processId.get()
  
  # Check if running
  if manager.running(processId.get()):
    echo "Server is running"
  
  # Terminate when done
  discard manager.terminate(processId.get())

# Platform utilities
let python = which("python3")
if python.isSome:
  echo "Python found at: ", python.get()

# Signal handling (Unix only)
when not defined(windows):
  if process.running():
    sendSignal(process, SIGTERM)
```

### Testing Example

```nim
import nim_libaspects/testing

# Define test suites
suite "Math Operations":
  var counter: int
  
  beforeAll:
    counter = 0
    echo "Setting up suite"
  
  afterAll:
    echo "Tearing down suite"
  
  beforeEach:
    inc(counter)
  
  test "Addition":
    check(1 + 1 == 2)
    expect(4, 2 + 2)
  
  test "Division by zero":
    expectError(DivByZeroDefect):
      discard 1 div 0
  
  test "Skipped test":
    skip("Not implemented yet")

# Run with different reporters
let config = TestConfig(
  pattern: "test_*.nim",
  parallel: true,
  failFast: false
)

let consoleReporter = ConsoleReporter(colored: true, verbose: true)
let jsonReporter = JsonReporter(outputFile: "results.json", pretty: true)

let runner = newTestRunner(config, consoleReporter)
let stats = runner.run()

# Exit with appropriate code
quit(if stats.failed > 0: 1 else: 0)
```

### Events Example

```nim
import nim_libaspects/events
import std/json

# Create an event bus
let bus = newEventBus()

# Subscribe to events with pattern matching
discard bus.subscribe("user.*", proc(e: Event) =
  echo "User event: ", e.eventType
  echo "Data: ", e.data
)

# Priority handler
discard bus.subscribePriority("critical.*", 100, proc(e: Event) =
  echo "Critical event (high priority): ", e.eventType
)

# Event filtering
let filter = EventFilter(
  eventType: "order.*",
  predicate: proc(e: Event): bool =
    e.data.hasKey("amount") and e.data["amount"].num > 100
)

discard bus.subscribeWithFilter(filter, proc(e: Event) =
  echo "Large order: ", e.data["amount"]
)

# Middleware
bus.addMiddleware(proc(e: Event, next: proc()) =
  echo "Processing: ", e.eventType
  next()
  echo "Processed: ", e.eventType
)

# Error handling
bus.onError(proc(e: Event, error: ref Exception) =
  echo "Error handling event: ", error.msg
)

# Publish events
bus.publish(newEvent("user.created", %*{"id": 1, "name": "Alice"}))
bus.publish(newEvent("order.created", %*{"id": 100, "amount": 150.0}))
bus.publish(newEvent("critical.alert", %*{"message": "System overload"}))

# Event store for persistence
let store = newEventStore()
store.connect(bus)

# All events are now automatically stored
bus.publish(newEvent("test.event"))

# Replay events
store.replay("user.*")  # Replay only user events

# Event aggregation
let aggregator = newEventAggregator(bus, maxBatchSize = 10, maxWaitTime = 1000)
aggregator.onBatch("metrics.*", proc(events: seq[Event]) =
  echo "Processing batch of ", events.len, " metrics"
)
```

### Enhanced Features with nim-lang-core

When nim-lang-core is available, additional AI-powered features are enabled:

#### Enhanced Testing
```nim
import nim_libaspects/testing

# Analyze test code for improvements
let suggestions = analyzeTestCode("tests/my_test.nim")
for suggestion in suggestions:
  echo "Improvement: ", suggestion

# Generate test skeleton from source
let skeleton = generateTestSkeleton("src/mymodule.nim")
echo skeleton  # Outputs a complete test template
```

#### Intelligent Configuration
```nim
import nim_libaspects/config

let config = newConfig()

# Get AI-powered suggestions
let improvements = config.suggestConfigImprovements()
# Suggests missing common configs like database, log_level, etc.

# Analyze config files for issues
let issues = analyzeConfigFile("config.json")
# Detects anti-patterns like hardcoded passwords

# Generate config schema
let schema = config.generateConfigSchema()
# Auto-generates a schema from current configuration
```

#### Performance Profiling
```nim
import nim_libaspects/profiler

let profiler = newProfiler()

# Analyze code for performance hotspots
let hotspots = profiler.analyzePerformanceHotspots("src/mymodule.nim")
for issue in hotspots:
  echo "Performance issue: ", issue

# Get optimization suggestions
let report = profiler.generateOptimizationReport()
echo report  # Detailed optimization recommendations
```

#### Enhanced Caching
```nim
import nim_libaspects/cache

# Create cache with nim-lang-core AST optimization
let cache = newNimCoreCache[string, string](maxEntries = 1000)
# Uses nim-lang-core's optimized AST cache backend

# Analyze cache usage patterns
let analysis = cache.analyzeCache()
for insight in analysis:
  echo "Cache insight: ", insight
```

## API Documentation

### Logging Module

#### Types
- `LogLevel`: Enum of log levels (Debug, Info, Warn, Error, Fatal)
- `Logger`: Main logging interface
- `LogHandler`: Abstract base for log handlers
- `LogFormatter`: Abstract base for formatters

#### Functions
- `newLogger(name: string)`: Create a new logger
- `newConsoleHandler()`: Create console output handler
- `newFileHandler(filename: string)`: Create file output handler
- `newTextFormatter(format: string)`: Create text formatter
- `newJsonFormatter(pretty: bool)`: Create JSON formatter

### Errors Module

#### Types
- `ErrorCode`: Enum of error codes
- `ErrorContext`: Error context with metadata
- `AppError`: Base application error type
- Specific error types: ValidationError, NotFoundError, etc.

#### Functions
- `capture[T](body: proc(): T)`: Convert exceptions to Result
- `mapResult[T,E,U]`: Transform success value
- `flatMapResult[T,E,U]`: Chain Result operations
- `recoverResult[T,E]`: Provide fallback value
- `combineResults[T,E]`: Combine multiple Results
- `validate[T]`: Validate values with multiple validators

### Config Module

#### Types
- `ConfigValue`: Unified configuration value type
- `ConfigValueKind`: Enum of value types (Null, Bool, Int, Float, String, Array, Object)
- `Config`: Main configuration manager
- `ConfigSource`: Enum of configuration sources (Default, File, Env, CommandLine)

#### Functions
- `newConfig(envPrefix, cmdLinePrefix)`: Create new config manager
- `loadJson(filename)`: Load JSON configuration file
- `loadToml(filename)`: Load TOML configuration file
- `loadEnv()`: Load environment variables
- `loadCommandLine(args)`: Load command line arguments
- `setDefault[T](key, value)`: Set default values
- `getString(key, default)`: Get string value with conversion
- `getInt(key, default)`: Get integer value with conversion
- `getBool(key, default)`: Get boolean value
- `getFloat(key, default)`: Get float value with conversion
- `getSection(section)`: Get nested configuration
- `loadCascade(files, loadEnv, loadCmdLine)`: Load from multiple sources
- `validateConfig(schemaFile)`: Validate config against schema (nim-lang-core)
- `analyzeConfigFile(filename)`: Analyze config file for issues (nim-lang-core)
- `suggestConfigImprovements()`: Get AI-powered suggestions (nim-lang-core)
- `generateConfigSchema()`: Auto-generate schema from config (nim-lang-core)

### Transport Module

#### Types
- `Transport`: Base transport type
- `StdioTransport`: Standard I/O transport
- `SocketTransport`: TCP client transport
- `ServerTransport`: TCP server transport
- `TransportKind`: Enum of transport types (tkStdio, tkSocket, tkServer)
- `ConnectionState`: Connection states (Disconnected, Connecting, Connected, Disconnecting)
- `MessageHeader`: Header information for messages

#### Functions
- `newStdioTransport(logger)`: Create stdio transport
- `newSocketTransport(host, port, logger)`: Create socket transport
- `newServerTransport(host, port, logger)`: Create server transport
- `createTransport(kind, host, port, logger)`: Factory for creating transports
- `start()`: Start/connect the transport
- `stop()`: Stop/disconnect the transport
- `sendMessage(message)`: Send a JSON message
- `receiveMessage()`: Receive a JSON message
- `isConnected()`: Check connection status
- `parseHeader(line)`: Parse a header line
- `parseHeaders(block)`: Parse multiple headers
- `createHeader(length, type)`: Create message headers

### Parallel Module

#### Types
- `TaskId`: Unique task identifier
- `TaskPriority`: Task priority levels (tpLow, tpNormal, tpHigh, tpCritical)
- `TaskStatus`: Task states (tsPending, tsRunning, tsCompleted, tsFailed, tsCancelled, tsSkipped)
- `TaskCategory`: Task categories (tcGeneral, tcCPU, tcIO, tcNetwork, tcMemory)
- `TaskSpec`: Task specification with configuration
- `TaskInfo`: Runtime task information  
- `TaskResult`: Task execution result
- `TaskProc`: Thread-safe task procedure type
- `ExecutorConfig`: Executor configuration
- `ExecutorStats`: Execution statistics
- `ParallelExecutor`: Main task executor

#### Functions
- `newTaskId(id)`: Create a task identifier
- `newTaskSpec(id, name, priority, category, ...)`: Create task specification
- `defaultExecutorConfig()`: Get default executor configuration
- `newParallelExecutor(config)`: Create new executor
- `addTask(executor, spec, taskProc)`: Add task to executor
- `cancelTask(executor, taskId)`: Cancel a task
- `start(executor)`: Start the executor
- `stop(executor)`: Stop the executor
- `schedule(executor)`: Run one scheduling iteration
- `runUntilComplete(executor)`: Run until all tasks complete
- `getTaskStatus(executor, taskId)`: Get task status
- `getTaskResult(executor, taskId)`: Get task result
- `getStats(executor)`: Get execution statistics
- `runParallel(tasks, config)`: Convenience function for simple parallel execution

### Process Module

#### Types
- `ProcessError`: Error type for process operations
- `ProcessStatus`: Process states (psRunning, psCompleted, psFailed, psTerminated, psTimeout)
- `ProcessResult`: Result of process execution
- `ProcessOptions`: Options for process execution
- `ProcessHandle`: Handle to a running process
- `ProcessManager`: Manager for multiple processes
- `ProcessBuilder`: Fluent API for building processes

#### Functions
- `newProcessError(msg)`: Create process error
- `getShell()`: Get system shell
- `escapeShellArg(s)`: Escape shell argument
- `escapeShellCommand(cmd, args)`: Create escaped shell command
- `findExecutable(name)`: Find executable in PATH
- `createProcess(options)`: Create a new process
- `runProcess(options)`: Run process synchronously
- `runProcessAsync(options)`: Run process asynchronously
- `newProcessBuilder(command)`: Create process builder
- `newProcessManager(logger)`: Create process manager
- `exec(command, args)`: Execute command and return result
- `execShell(command)`: Execute shell command
- `which(command)`: Find command in PATH
- `monitorProcess(handle, callback)`: Monitor process status
- `sendSignal(process, signal)`: Send signal to process (Unix only)

### Testing Module

#### Types
- `TestStatus`: Test result status (tsPass, tsFail, tsSkip, tsError, tsPending)
- `TestResult`: Individual test result with metadata
- `AssertionInfo`: Detailed assertion information
- `TestInfo`: Test metadata and configuration
- `TestSuite`: Collection of tests with fixtures
- `TestRunner`: Main test execution engine
- `TestConfig`: Runner configuration options
- `TestStats`: Overall test statistics
- `TestReporter`: Base reporter interface
- `ConsoleReporter`: Console output reporter
- `JsonReporter`: JSON format reporter
- `HtmlReporter`: HTML format reporter
- `TestDiscoverer`: Test discovery interface
- `FileDiscoverer`: File-based test discovery
- `ModuleDiscoverer`: Module-based test discovery

#### Functions
- `check(condition, message)`: Assert a condition with optional message
- `expect(expected, actual)`: Compare expected and actual values
- `expectError(errorType, code)`: Expect code to raise specific error
- `skip(reason)`: Skip test with optional reason
- `suite(name, body)`: Define a test suite
- `test(name, body)`: Define a test
- `beforeAll(body)`: Run before all tests in suite
- `afterAll(body)`: Run after all tests in suite
- `beforeEach(body)`: Run before each test
- `afterEach(body)`: Run after each test
- `newTestRunner(config, reporter)`: Create test runner
- `run(runner)`: Run all tests
- `runTests(pattern, parallel)`: Convenience function to run tests
- `analyzeTestCode(filename)`: Analyze test code for improvements (nim-lang-core)
- `suggestTestImprovements(suite)`: Get AI suggestions for test suite (nim-lang-core)
- `generateTestSkeleton(sourceFile)`: Generate test skeleton from source (nim-lang-core)

### Events Module

#### Types
- `Event`: Core event object with id, type, data, timestamp, and metadata
- `EventBus`: Main event dispatcher with publish/subscribe
- `EventFilter`: Filter configuration with pattern and predicate
- `EventHandler`: Event handler function type
- `EventMiddleware`: Middleware function type
- `EventSubscription`: Subscription information
- `EventStore`: Event persistence and replay
- `EventAggregator`: Batch event processing
- `AsyncEventBus`: Asynchronous event handling

#### Functions
- `newEvent(eventType, data?)`: Create new event
- `newEventBus(namespace?)`: Create event bus
- `publish(bus, event)`: Publish event to bus
- `subscribe(bus, pattern, handler)`: Subscribe to events
- `subscribePriority(bus, pattern, priority, handler)`: Priority subscription
- `subscribeWithFilter(bus, filter, handler)`: Filtered subscription
- `unsubscribe(bus, id)`: Remove subscription
- `addMiddleware(bus, middleware)`: Add middleware
- `onError(bus, handler)`: Set error handler
- `namespace(bus, name)`: Create namespaced bus
- `newEventStore(maxEvents?)`: Create event store
- `connect(store, bus)`: Connect store to bus
- `getEvents(store, pattern?)`: Retrieve stored events
- `replay(store, pattern?)`: Replay stored events
- `newEventAggregator(bus, maxSize, maxTime)`: Create aggregator
- `onBatch(aggregator, pattern, handler)`: Set batch handler

### Profiler Module

#### Types
- `ProfileEntry`: Single profile measurement
- `ProfileStats`: Aggregated statistics for an operation
- `ProfileReport`: Complete profiling report
- `ProfilerConfig`: Profiler configuration
- `Profiler`: Main profiler object

#### Functions
- `newProfiler(config?)`: Create new profiler
- `span(profiler, name)`: Create profiling span
- `profile(name, body)`: Profile a code block
- `generateReport()`: Generate profiling report
- `exportJson()`: Export profile data as JSON
- `exportHtml()`: Export profile as HTML report
- `analyzePerformanceHotspots(sourceFile)`: Find performance issues (nim-lang-core)
- `suggestOptimizations(report)`: Get optimization suggestions (nim-lang-core)
- `analyzeCallGraph(sourceFiles)`: Analyze call relationships (nim-lang-core)
- `generateOptimizationReport()`: Generate comprehensive report (nim-lang-core)

### Cache Module

#### Types
- `Cache[K,V]`: Generic cache interface
- `LoadingCache[K,V]`: Cache with automatic loading
- `AsyncCache[K,V]`: Asynchronous cache operations
- `MultiLevelCache[K,V]`: Multi-level cache hierarchy
- `GroupCache[K,V]`: Cache with group invalidation
- `MemoryAwareCache[K,V]`: Memory-limited cache
- `NimCoreCache[K,V]`: Enhanced cache with nim-lang-core

#### Functions
- `newCache[K,V](maxSize, ttl, policy)`: Create cache
- `put(key, value, ttl?)`: Store value
- `get(key)`: Retrieve value
- `invalidate(key)`: Remove single entry
- `invalidateAll()`: Clear cache
- `getStats()`: Get cache statistics
- `newNimCoreCache[K,V](maxEntries)`: Create enhanced cache (nim-lang-core)
- `putAstNode(key, ast)`: Store AST node (nim-lang-core)
- `getAstNode(key)`: Retrieve AST node (nim-lang-core)
- `analyzeCache()`: Analyze usage patterns (nim-lang-core)

## Testing

Run all tests:
```bash
nim c -r tests/test_all
```

Run specific module tests:
```bash
nim c -r tests/test_logging
nim c -r tests/test_errors
nim c -r tests/test_config
nim c -r tests/test_transport
nim c -r tests/test_parallel
nim c -r tests/test_process
nim c -r tests/test_testing
nim c -r tests/test_metrics
nim c -r tests/test_reporting
nim c -r tests/test_events
```

## Documentation

### Module Documentation
- [Testing Module](docs/testing.md) - Test framework with AI-powered analysis
- [Configuration Module](docs/config.md) - Config management with validation
- [Profiler Module](docs/profiler.md) - Performance profiling and optimization
- [Cache Module](docs/cache.md) - Caching with nim-lang-core integration
- [Events Module](docs/events.md) - Event-driven architecture
- [Monitoring Module](docs/monitoring.md) - System monitoring
- [Metrics Module](docs/metrics.md) - Performance metrics
- [Notifications Module](docs/notifications.md) - Multi-channel notifications
- [Reporting Module](docs/reporting.md) - Report generation
- [Logging-Metrics Module](docs/logging_metrics.md) - Integrated logging and metrics

### Integration Guides
- [nim-lang-core Integration](docs/nim_core_integration.md) - Complete guide for AI-powered features

### Examples
- [Basic Examples](examples/) - Simple usage examples
- [Integration Example](examples/nim_core_integration_simple.nim) - nim-lang-core features demo

## License

MIT License

## Contributing

Contributions are welcome! Please submit pull requests with tests for any new functionality.
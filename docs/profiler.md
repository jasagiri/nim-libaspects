# Profiler Module

The profiler module provides comprehensive performance profiling capabilities with CPU time tracking, memory profiling, and performance analysis. When integrated with nim-lang-core, it offers AI-powered optimization suggestions.

## Features

- CPU time tracking with nanosecond precision
- Memory usage profiling
- Hierarchical profiling with call trees
- Multiple output formats (JSON, HTML)
- Thread-safe profiling
- **AI-powered performance analysis** (with nim-lang-core)
- **Automatic optimization suggestions** (with nim-lang-core)
- **Call graph analysis** (with nim-lang-core)

## Basic Usage

```nim
import nim_libaspects/profiler

# Using the global profiler
profile "expensive_operation":
  # Your code here
  for i in 0..1000:
    discard

# Using a custom profiler
let profiler = newProfiler()

let span = profiler.span("database_query")
# Perform database query
span.finish()

# Generate report
let report = profiler.generateReport()
echo report.exportJson()
```

## Profiling Operations

### Manual Spans

```nim
let profiler = newProfiler()

# Start a span
let span = profiler.span("operation_name")

# Do work...

# Finish the span
span.finish()
```

### Template-based Profiling

```nim
# Profile a code block
profile "data_processing":
  let data = loadData()
  let processed = processData(data)
  saveData(processed)
```

### Nested Profiling

```nim
profile "main_operation":
  profile "sub_operation_1":
    doWork1()
  
  profile "sub_operation_2":
    doWork2()
```

## Memory Profiling

The profiler tracks memory usage for each operation:

```nim
let config = ProfilerConfig(
  enabled: true,
  captureMemory: true,
  captureStack: false
)

let profiler = newProfiler(config)

profile "memory_intensive":
  var data = newSeq[int](1_000_000)
  # Memory delta is tracked
```

## Enhanced Features with nim-lang-core

### Performance Hotspot Analysis

Analyze source code to identify performance issues:

```nim
let hotspots = profiler.analyzePerformanceHotspots("src/mymodule.nim")
for issue in hotspots:
  echo "Performance issue: ", issue
```

Common issues detected:
- Nested loops with high complexity
- Inefficient string concatenation
- Unnecessary allocations
- Missing optimization opportunities

### Optimization Suggestions

Get AI-powered optimization suggestions based on profiling data:

```nim
let report = profiler.generateReport()
let suggestions = suggestOptimizations(report)

for suggestion in suggestions:
  echo suggestion
```

Suggestions include:
- High-variance operations that need optimization
- Memory-intensive operations for pooling
- Frequently called slow functions
- Cache opportunities

### Optimization Report

Generate a comprehensive optimization report:

```nim
let report = profiler.generateOptimizationReport()
writeFile("optimization-report.md", report)
```

The report includes:
- Summary statistics
- Top 10 slowest operations
- Memory usage analysis
- AI-powered optimization suggestions
- Actionable recommendations

### Call Graph Analysis

Analyze call relationships in your code:

```nim
let callGraph = profiler.analyzeCallGraph(@["src/module1.nim", "src/module2.nim"])
# Note: Full implementation requires nim-lang-core symbol index
```

## Report Generation

### JSON Export

```nim
let report = profiler.generateReport()
let json = report.exportJson()
writeFile("profile.json", json)
```

### HTML Export

```nim
let html = report.exportHtml()
writeFile("profile.html", html)
```

### Console Output

```nim
echo profiler.generateReport()
# Outputs formatted statistics
```

## Profile Statistics

The profiler provides detailed statistics:

```nim
type ProfileStats = object
  operation: string
  count: int
  totalTime: float64    # milliseconds
  minTime: float64
  maxTime: float64
  avgTime: float64
  p50Time: float64      # median
  p95Time: float64
  p99Time: float64
  memoryDelta: int64    # bytes
```

## Configuration

```nim
let config = ProfilerConfig(
  enabled: true,
  autoFlush: true,
  flushInterval: initDuration(minutes = 5),
  maxEntries: 10000,
  captureMemory: true,
  captureStack: false
)

let profiler = newProfiler(config)
```

## Best Practices

1. **Profile in production mode**: Debug mode adds overhead
2. **Use meaningful operation names**: Makes reports easier to understand
3. **Profile at appropriate granularity**: Not too fine, not too coarse
4. **Regular profiling**: Make it part of CI/CD pipeline
5. **Act on suggestions**: Use AI suggestions to guide optimization
6. **Memory profiling**: Enable when investigating memory issues

## Performance Tips

Based on common patterns detected by the AI analysis:

1. **Avoid string concatenation in loops**: Use `seq[string]` and `join`
2. **Cache expensive computations**: Especially in hot paths
3. **Use appropriate data structures**: Tables for lookups, sequences for iteration
4. **Minimize allocations**: Reuse buffers where possible
5. **Profile before optimizing**: Measure, don't guess

## API Reference

See the main README for complete API documentation.
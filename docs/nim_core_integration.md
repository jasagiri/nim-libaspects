# nim-lang-core Integration Guide

This guide explains how to integrate and use nim-lang-core features in nim-libaspects.

## Overview

nim-libaspects can optionally integrate with [nim-lang-core](https://github.com/jasagiri/nim-lang-core) to provide AI-powered code analysis, performance optimization suggestions, and enhanced caching capabilities.

## Setup

### 1. Install nim-lang-core

Clone nim-lang-core adjacent to your nim-libaspects installation:

```bash
# Assuming nim-libaspects is in current directory
git clone https://github.com/jasagiri/nim-lang-core ../nim-lang-core
```

### 2. Verify Integration

The integration is automatically enabled through `nim.cfg`. You can verify it's working:

```nim
import nim_libaspects/cache

# This should compile without errors
let cache = newNimCoreCache[string, string](100)
echo "nim-lang-core integration is working!"
```

## Enhanced Modules

Four modules in nim-libaspects are enhanced with nim-lang-core capabilities:

### 1. Testing Module

Enhanced with AI-powered test analysis and generation:

```nim
import nim_libaspects/testing

# Analyze test code
let testFile = "tests/test_example.nim"
let suggestions = analyzeTestCode(testFile)
for s in suggestions:
  echo "Suggestion: ", s

# Generate test skeleton
let sourceFile = "src/mymodule.nim"
let skeleton = generateTestSkeleton(sourceFile)
writeFile("tests/test_mymodule.nim", skeleton)

# Analyze test suite
let improvements = suggestTestImprovements(suite)
```

### 2. Config Module

Enhanced with configuration validation and analysis:

```nim
import nim_libaspects/config

let config = newConfig("APP_")

# Validate against schema
let validation = config.validateConfig("schema.nim")
if validation.isErr:
  for error in validation.error:
    echo "Validation error: ", error

# Analyze config file
let issues = analyzeConfigFile("config.json")
for issue in issues:
  echo "Issue: ", issue

# Get AI suggestions
let suggestions = config.suggestConfigImprovements()
for s in suggestions:
  echo "Config suggestion: ", s

# Generate schema
let schema = config.generateConfigSchema()
```

### 3. Profiler Module

Enhanced with performance analysis:

```nim
import nim_libaspects/profiler

let profiler = newProfiler()

# Analyze source for hotspots
let hotspots = profiler.analyzePerformanceHotspots("src/slow.nim")
for h in hotspots:
  echo "Hotspot: ", h

# Get optimization suggestions
profile "operation":
  # Your code
  discard

let report = profiler.generateReport()
let suggestions = suggestOptimizations(report)

# Generate comprehensive report
let optimizationReport = profiler.generateOptimizationReport()
echo optimizationReport
```

### 4. Cache Module

Enhanced with nim-lang-core's AST cache:

```nim
import nim_libaspects/cache

# Create enhanced cache
let cache = newNimCoreCache[string, string](maxEntries = 1000)

# Analyze cache usage
let regularCache = newCache[string, string](100)
regularCache.put("key", "value")

let analysis = regularCache.analyzeCache()
for insight in analysis:
  echo "Cache insight: ", insight
```

## AI Pattern Detection

nim-lang-core provides pattern detection across several categories:

- `pcNaming`: Naming convention issues
- `pcStyle`: Code style issues
- `pcLogicIssue`: Logical problems
- `pcDocumentation`: Missing or poor documentation
- `pcSecurity`: Security vulnerabilities
- `pcPerformance`: Performance bottlenecks
- `pcAPIUsage`: API misuse

## Complete Example

Here's a complete example showing all integrations:

```nim
import nim_libaspects/[testing, config, profiler, cache]
import std/[os, strutils]

# 1. Enhanced Testing
echo "=== Testing Analysis ==="
if fileExists("tests/test_main.nim"):
  let testSuggestions = analyzeTestCode("tests/test_main.nim")
  echo "Found ", testSuggestions.len, " test improvements"

# 2. Configuration Management
echo "\n=== Configuration ==="
let config = newConfig("MYAPP_")
config.setDefault("port", 8080)
config.setDefault("workers", 4)

let configSuggestions = config.suggestConfigImprovements()
for s in configSuggestions:
  echo "Config: ", s

# 3. Performance Profiling
echo "\n=== Performance Analysis ==="
let profiler = newProfiler()

profile "data_processing":
  # Simulate work
  for i in 0..1000:
    discard

let report = profiler.generateOptimizationReport()
echo report.split('\n')[0..5].join("\n")

# 4. Enhanced Caching
echo "\n=== Cache Analysis ==="
let cache = newCache[string, string](100)
for i in 0..50:
  cache.put($i, "value" & $i)

# Simulate cache usage
for i in 0..100:
  discard cache.get($(i mod 30))

let cacheAnalysis = cache.analyzeCache()
for insight in cacheAnalysis:
  echo "Cache: ", insight
```

## Performance Considerations

The AI-powered features add some overhead:

1. **AST Parsing**: File analysis requires parsing, which takes time
2. **Pattern Detection**: AI analysis has computational cost
3. **Caching**: Use caching to avoid repeated analysis

Best practices:
- Cache analysis results
- Run analysis in CI/CD, not production
- Use conditional compilation for optional features

## Troubleshooting

### Import Errors

If you get import errors, ensure:
1. nim-lang-core is in `../nim-lang-core` relative to nim-libaspects
2. Your `nim.cfg` includes the path
3. nim-lang-core is properly installed

### Compilation Errors

Common issues:
- **Type mismatches**: Ensure you're using the correct types from nim-lang-core
- **Missing procedures**: Some features require specific nim-lang-core versions

### Runtime Errors

- **File not found**: AST analysis requires actual files to exist
- **Invalid patterns**: Ensure pattern strings are valid

## Future Enhancements

Planned integrations:
1. Custom AI pattern rules
2. Real-time code analysis
3. Integration with LSP features
4. Advanced refactoring suggestions

## API Reference

For detailed API documentation, see:
- [Testing Module](testing.md)
- [Config Module](config.md)
- [Profiler Module](profiler.md)
- [Cache Module](cache.md)
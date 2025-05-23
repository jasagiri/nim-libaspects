## Performance profiler module
## Provides CPU time tracking, memory profiling, and performance analysis

import std/[
  times,
  tables,
  sequtils,
  json,
  strformat,
  strutils,
  algorithm,
  locks,
  os
]
import system
import ./errors
import nim_core
import nim_corepkg/ast/analyzer as ast_analyzer
import nim_corepkg/analysis/ai_patterns
import nim_corepkg/analysis/symbol_index

# Helper functions
proc sum[T](s: seq[T]): T =
  result = T(0)
  for x in s:
    result += x

type
  ProfileEntry* = object
    operation*: string
    startTime*: Time
    endTime*: Time
    duration*: Duration
    memoryBefore*: int
    memoryAfter*: int
    threadId*: int
    metadata*: JsonNode
  
  ProfileStats* = object
    operation*: string
    count*: int
    totalTime*: float64  # milliseconds
    minTime*: float64
    maxTime*: float64
    avgTime*: float64
    p50Time*: float64  # median
    p95Time*: float64
    p99Time*: float64
    memoryDelta*: int64  # bytes
  
  MemorySnapshot* = object
    timestamp*: Time
    heapSize*: int
    stackSize*: int
    residentSize*: int
    virtualSize*: int
  
  ProfilerConfig* = object
    enabled*: bool
    autoFlush*: bool
    flushInterval*: Duration
    maxEntries*: int
    captureMemory*: bool
    captureStack*: bool
  
  ProfileReport* = object
    startTime*: Time
    endTime*: Time
    duration*: Duration
    profiles*: Table[string, ProfileStats]
    memorySnapshots*: seq[MemorySnapshot]
    threadStats*: Table[int, int]  # thread ID -> operation count
  
  ProfilerSpan* = ref object
    profiler: Profiler
    operation: string
    startTime: Time
  
  Profiler* = ref object
    entries: seq[ProfileEntry]
    activeOps: Table[string, Time]
    memorySnapshots: Table[string, MemorySnapshot]
    config: ProfilerConfig
    lock: Lock
    startTime: Time

proc getMemoryInfo(): tuple[heap: int, resident: int, virtual: int] =
  ## Get current memory usage
  when defined(linux):
    try:
      let pid = getCurrentProcessId()
      let statusFile = &"/proc/{pid}/status"
      if fileExists(statusFile):
        let status = readFile(statusFile)
        var heap, resident, virtual: int
        for line in status.splitLines():
          let parts = line.split()
          if parts.len >= 2:
            if parts[0] == "VmRSS:":  # Resident set size
              resident = parseInt(parts[1]) * 1024
            elif parts[0] == "VmSize:":  # Virtual memory size
              virtual = parseInt(parts[1]) * 1024
            elif parts[0] == "VmData:":  # Data segment size (heap)
              heap = parseInt(parts[1]) * 1024
        return (heap, resident, virtual)
      else:
        let occupied = getOccupiedMem()
        return (occupied, occupied, occupied)
    except:
      let occupied = getOccupiedMem()
      return (occupied, occupied, occupied)
  else:
    # For non-Linux systems, use GC statistics
    let occupied = getOccupiedMem()
    let free = getFreeMem()
    let total = occupied + free
    return (occupied, occupied, total)

proc newProfiler*(config = ProfilerConfig(
  enabled: true,
  autoFlush: false,
  flushInterval: initDuration(minutes = 5),
  maxEntries: 10000,
  captureMemory: true,
  captureStack: false
)): Profiler =
  result = Profiler(
    entries: @[],
    activeOps: initTable[string, Time](),
    memorySnapshots: initTable[string, MemorySnapshot](),
    config: config,
    startTime: getTime()
  )
  initLock(result.lock)

proc start*(profiler: Profiler, operation: string, metadata: JsonNode = nil) =
  if not profiler.config.enabled:
    return
  
  withLock(profiler.lock):
    let now = getTime()
    profiler.activeOps[operation] = now
    
    if profiler.config.captureMemory:
      let memInfo = getMemoryInfo()
      profiler.entries.add(ProfileEntry(
        operation: operation,
        startTime: now,
        memoryBefore: memInfo.heap,
        threadId: getThreadId(),
        metadata: metadata
      ))

proc stop*(profiler: Profiler, operation: string) =
  if not profiler.config.enabled:
    return
  
  withLock(profiler.lock):
    let now = getTime()
    if operation in profiler.activeOps:
      let startTime = profiler.activeOps[operation]
      profiler.activeOps.del(operation)
      
      var entry = ProfileEntry(
        operation: operation,
        startTime: startTime,
        endTime: now,
        duration: now - startTime,
        threadId: getThreadId()
      )
      
      if profiler.config.captureMemory:
        let memInfo = getMemoryInfo()
        entry.memoryAfter = memInfo.heap
      
      profiler.entries.add(entry)
      
      # Auto-flush if needed
      if profiler.config.autoFlush and profiler.entries.len >= profiler.config.maxEntries:
        profiler.entries = profiler.entries[^(profiler.config.maxEntries div 2)..^1]

proc span*(profiler: Profiler, operation: string): ProfilerSpan =
  profiler.start(operation)
  ProfilerSpan(
    profiler: profiler,
    operation: operation,
    startTime: getTime()
  )

# Manual cleanup for ProfilerSpan
proc finish*(span: ProfilerSpan) =
  if span.profiler != nil:
    span.profiler.stop(span.operation)

proc recordMemory*(profiler: Profiler, label: string) =
  if not profiler.config.enabled or not profiler.config.captureMemory:
    return
  
  withLock(profiler.lock):
    let memInfo = getMemoryInfo()
    profiler.memorySnapshots[label] = MemorySnapshot(
      timestamp: getTime(),
      heapSize: memInfo.heap,
      residentSize: memInfo.resident,
      virtualSize: memInfo.virtual
    )

proc getProfile*(profiler: Profiler, operation: string): ProfileStats =
  withLock(profiler.lock):
    var durations: seq[float64] = @[]
    var memoryDeltas: seq[int64] = @[]
    
    for entry in profiler.entries:
      if entry.operation == operation and entry.endTime != Time():
        durations.add(entry.duration.inMilliseconds.float64)
        if entry.memoryAfter > 0:
          memoryDeltas.add(entry.memoryAfter - entry.memoryBefore)
    
    if durations.len == 0:
      raise newException(KeyError, &"No profile data for operation: {operation}")
    
    durations.sort()
    
    let totalTime = durations.sum()
    let avgTime = totalTime / durations.len.float64
    
    result = ProfileStats(
      operation: operation,
      count: durations.len,
      totalTime: totalTime,
      minTime: durations[0],
      maxTime: durations[^1],
      avgTime: avgTime,
      p50Time: durations[durations.len div 2],
      p95Time: if durations.len > 20: durations[int(durations.len.float * 0.95)] else: durations[^1],
      p99Time: if durations.len > 100: durations[int(durations.len.float * 0.99)] else: durations[^1],
      memoryDelta: if memoryDeltas.len > 0: memoryDeltas.sum() div memoryDeltas.len else: 0
    )

proc getMemorySnapshot*(profiler: Profiler, label: string): MemorySnapshot =
  withLock(profiler.lock):
    if label notin profiler.memorySnapshots:
      raise newException(KeyError, &"No memory snapshot for label: {label}")
    result = profiler.memorySnapshots[label]

proc generateReport*(profiler: Profiler, minDuration: float64 = 0.0): ProfileReport =
  withLock(profiler.lock):
    let now = getTime()
    result = ProfileReport(
      startTime: profiler.startTime,
      endTime: now,
      duration: now - profiler.startTime,
      profiles: initTable[string, ProfileStats](),
      memorySnapshots: toSeq(profiler.memorySnapshots.values),
      threadStats: initTable[int, int]()
    )
    
    # Collect unique operations
    var operations: seq[string] = @[]
    for entry in profiler.entries:
      if entry.operation notin operations:
        operations.add(entry.operation)
    
    # Generate stats for each operation
    for op in operations:
      try:
        let stats = profiler.getProfile(op)
        if stats.avgTime >= minDuration:
          result.profiles[op] = stats
      except KeyError:
        discard
    
    # Thread statistics
    for entry in profiler.entries:
      if entry.threadId in result.threadStats:
        inc result.threadStats[entry.threadId]
      else:
        result.threadStats[entry.threadId] = 1

proc exportJson*(profiler: Profiler): JsonNode =
  let report = profiler.generateReport()
  result = %*{
    "startTime": $report.startTime,
    "endTime": $report.endTime,
    "duration": report.duration.inMilliseconds,
    "profiles": newJObject(),
    "memory": newJArray(),
    "threads": newJObject()
  }
  
  for op, stats in report.profiles:
    result["profiles"][op] = %*{
      "count": stats.count,
      "totalTime": stats.totalTime,
      "minTime": stats.minTime,
      "maxTime": stats.maxTime,
      "avgTime": stats.avgTime,
      "p50": stats.p50Time,
      "p95": stats.p95Time,
      "p99": stats.p99Time,
      "memoryDelta": stats.memoryDelta
    }
  
  for snapshot in report.memorySnapshots:
    result["memory"].add(%*{
      "timestamp": $snapshot.timestamp,
      "heap": snapshot.heapSize,
      "resident": snapshot.residentSize,
      "virtual": snapshot.virtualSize
    })
  
  for threadId, count in report.threadStats:
    result["threads"][$threadId] = %count

proc exportHtml*(profiler: Profiler): string =
  let report = profiler.generateReport()
  result = """
<!DOCTYPE html>
<html>
<head>
  <title>Performance Profile Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    table { border-collapse: collapse; width: 100%; margin: 20px 0; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background-color: #f2f2f2; }
    tr:nth-child(even) { background-color: #f9f9f9; }
    .metric { text-align: right; }
    .summary { background-color: #e7f3ff; padding: 10px; margin: 10px 0; }
  </style>
</head>
<body>
  <h1>Performance Profile Report</h1>
  <div class="summary">
    <p><strong>Start Time:</strong> $1</p>
    <p><strong>End Time:</strong> $2</p>
    <p><strong>Duration:</strong> $3 ms</p>
  </div>
  
  <h2>Operation Profiles</h2>
  <table>
    <tr>
      <th>Operation</th>
      <th class="metric">Count</th>
      <th class="metric">Total (ms)</th>
      <th class="metric">Min (ms)</th>
      <th class="metric">Max (ms)</th>
      <th class="metric">Avg (ms)</th>
      <th class="metric">P50 (ms)</th>
      <th class="metric">P95 (ms)</th>
      <th class="metric">P99 (ms)</th>
      <th class="metric">Memory Δ</th>
    </tr>
""" % [$report.startTime, $report.endTime, $report.duration.inMilliseconds]
  
  for op, stats in report.profiles:
    result.add(&"""
    <tr>
      <td>{op}</td>
      <td class="metric">{stats.count}</td>
      <td class="metric">{stats.totalTime:.2f}</td>
      <td class="metric">{stats.minTime:.2f}</td>
      <td class="metric">{stats.maxTime:.2f}</td>
      <td class="metric">{stats.avgTime:.2f}</td>
      <td class="metric">{stats.p50Time:.2f}</td>
      <td class="metric">{stats.p95Time:.2f}</td>
      <td class="metric">{stats.p99Time:.2f}</td>
      <td class="metric">{stats.memoryDelta}</td>
    </tr>
""")
  
  result.add("""
  </table>
  
  <h2>Thread Statistics</h2>
  <table>
    <tr>
      <th>Thread ID</th>
      <th class="metric">Operation Count</th>
    </tr>
""")
  
  for threadId, count in report.threadStats:
    result.add(&"""
    <tr>
      <td>{threadId}</td>
      <td class="metric">{count}</td>
    </tr>
""")
  
  result.add("""
  </table>
</body>
</html>
""")

proc clear*(profiler: Profiler) =
  withLock(profiler.lock):
    profiler.entries = @[]
    profiler.activeOps.clear()
    profiler.memorySnapshots.clear()
    profiler.startTime = getTime()

# AI-powered performance analysis using nim-lang-core
proc analyzePerformanceHotspots*(profiler: Profiler, sourceFile: string): seq[string] =
  ## Analyze source code to identify performance hotspots
  result = @[]
  
  try:
    let astResult = ast_analyzer.parseFile(sourceFile)
    if astResult.isOk:
      # Use nim-lang-core's AI patterns to detect performance issues
      let detector = newAiPatternDetector()
      let patterns = detector.detectPatterns(astResult.get(), sourceFile)
    
      for pattern in patterns:
        if pattern.category == pcPerformance:
          result.add(pattern.message)
    
    # Cross-reference with profiling data
    let report = profiler.generateReport()
    for op, stats in report.profiles:
      if stats.avgTime > 100.0:  # Slow operations (> 100ms)
        result.add(fmt"Operation '{op}' is slow (avg: {stats.avgTime:.2f}ms)")
  except:
    result.add("Failed to analyze performance hotspots")

proc suggestOptimizations*(report: ProfileReport): seq[string] =
  ## Suggest optimizations based on profiling data
  result = @[]
  
  # Analyze slow operations
  for op, stats in report.profiles:
    if stats.maxTime > stats.avgTime * 10:
      result.add(fmt"'{op}' has high variance - consider caching or optimization")
    
    if stats.memoryDelta > 1_000_000:  # > 1MB memory allocation
      result.add(fmt"'{op}' allocates {stats.memoryDelta} bytes - consider memory pooling")
    
    if stats.count > 1000 and stats.avgTime > 1.0:
      result.add(fmt"'{op}' is called frequently ({stats.count}x) and is slow - high impact optimization target")

proc analyzeCallGraph*(profiler: Profiler, sourceFiles: seq[string]): Table[string, seq[string]] =
  ## Analyze call relationships using AST analysis
  result = initTable[string, seq[string]]()
  
  # This is a simplified implementation
  # Full implementation would use nim-lang-core's symbol index
  for file in sourceFiles:
    try:
      let astResult = ast_analyzer.parseFile(file)
      if astResult.isOk:
        # Placeholder for call graph analysis
        result[file] = @[]
    except:
      discard

proc generateOptimizationReport*(profiler: Profiler): string =
  ## Generate a comprehensive optimization report
  let report = profiler.generateReport()
  let suggestions = suggestOptimizations(report)
  
  result = "# Performance Optimization Report\n\n"
  
  # Summary statistics
  result &= "## Summary\n"
  result &= fmt"Total operations: {report.profiles.len}\n"
  result &= fmt"Total duration: {report.duration.inMilliseconds}ms\n\n"
  
  # Top slowest operations
  result &= "## Slowest Operations\n"
  var sorted = toSeq(report.profiles.pairs)
  sorted.sort do (a, b: (string, ProfileStats)) -> int:
    cmp(b[1].totalTime, a[1].totalTime)
  
  for i, (op, stats) in sorted:
    if i >= 10: break
    result &= fmt"- {op}: {stats.totalTime:.2f}ms total ({stats.count} calls)\n"
  
  result &= "\n## Optimization Suggestions\n"
  for suggestion in suggestions:
    result &= fmt"- {suggestion}\n"

# Convenience functions for module-level profiling
var globalProfiler* = newProfiler()

template profile*(name: string, body: untyped) =
  let span = globalProfiler.span(name)
  try:
    body
  finally:
    span.finish()

proc enableProfiling*(enabled = true) =
  globalProfiler.config.enabled = enabled

proc getGlobalProfiler*(): Profiler =
  globalProfiler
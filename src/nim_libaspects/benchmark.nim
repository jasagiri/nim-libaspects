## Benchmarking framework
## Provides tools for performance benchmarking and comparison

import std/[
  times,
  tables,
  sequtils,
  json,
  strformat,
  algorithm,
  math,
  random,
  os
]
import ./profiler
import ./errors

type
  BenchmarkResult* = object
    name*: string
    iterations*: int
    totalTime*: float64  # milliseconds
    avgTime*: float64
    minTime*: float64
    maxTime*: float64
    stdDev*: float64
    warmupTime*: float64
    samples*: seq[float64]
    memoryStats*: MemoryStats
  
  MemoryStats* = object
    avgMemory*: int64
    peakMemory*: int64
    allocations*: int
  
  BenchmarkSuite* = ref object
    name*: string
    benchmarks*: OrderedTable[string, proc()]
    profiler*: Profiler
    config*: BenchmarkConfig
  
  BenchmarkConfig* = object
    iterations*: int
    warmup*: int
    captureMemory*: bool
    randomize*: bool
    timeout*: Duration
  
  BenchmarkComparison* = object
    results*: Table[string, BenchmarkResult]
    fastest*: string
    slowest*: string
    speedup*: float64
    summary*: string
  
  Statistics* = object
    mean*: float64
    median*: float64
    stdDev*: float64
    min*: float64
    max*: float64
    p95*: float64
    p99*: float64

proc calculateStats*(samples: seq[float64]): Statistics =
  if samples.len == 0:
    return
  
  var sorted = samples
  sorted.sort()
  
  result.min = sorted[0]
  result.max = sorted[^1]
  result.mean = samples.sum() / samples.len.float64
  result.median = sorted[sorted.len div 2]
  
  # Standard deviation
  var variance = 0.0
  for s in samples:
    variance += pow(s - result.mean, 2)
  result.stdDev = sqrt(variance / samples.len.float64)
  
  # Percentiles
  result.p95 = sorted[int(sorted.len.float64 * 0.95)]
  result.p99 = sorted[int(sorted.len.float64 * 0.99)]

proc benchmark*(name: string, iterations = 1000, warmup = 100, body: proc()): BenchmarkResult =
  result.name = name
  result.iterations = iterations
  
  # Warmup runs
  let warmupStart = cpuTime()
  for i in 0..<warmup:
    body()
  result.warmupTime = (cpuTime() - warmupStart) * 1000
  
  # Actual benchmark runs
  result.samples = newSeq[float64](iterations)
  let startTime = cpuTime()
  
  for i in 0..<iterations:
    let iterStart = cpuTime()
    body()
    let iterEnd = cpuTime()
    result.samples[i] = (iterEnd - iterStart) * 1000
  
  result.totalTime = (cpuTime() - startTime) * 1000
  
  # Calculate statistics
  let stats = calculateStats(result.samples)
  result.avgTime = stats.mean
  result.minTime = stats.min
  result.maxTime = stats.max
  result.stdDev = stats.stdDev

proc benchmarkMemory*(name: string, iterations = 100, body: proc()): BenchmarkResult =
  result = benchmark(name, iterations, 0, body)
  
  var memoryDeltas: seq[int64] = @[]
  var peakMemory: int64 = 0
  
  for i in 0..<iterations:
    let memBefore = GC_getStatistics().maxHeapSize
    body()
    let memAfter = GC_getStatistics().maxHeapSize
    let delta = memAfter - memBefore
    memoryDeltas.add(delta)
    peakMemory = max(peakMemory, memAfter)
  
  result.memoryStats.avgMemory = memoryDeltas.sum() div memoryDeltas.len
  result.memoryStats.peakMemory = peakMemory
  result.memoryStats.allocations = iterations

proc newBenchmarkSuite*(name: string, config = BenchmarkConfig(
  iterations: 1000,
  warmup: 100,
  captureMemory: false,
  randomize: false,
  timeout: initDuration(seconds = 30)
)): BenchmarkSuite =
  BenchmarkSuite(
    name: name,
    benchmarks: initOrderedTable[string, proc()](),
    profiler: newProfiler(),
    config: config
  )

proc add*(suite: BenchmarkSuite, name: string, benchmark: proc()) =
  suite.benchmarks[name] = benchmark

proc run*(suite: BenchmarkSuite, iterations = -1): Table[string, BenchmarkResult] =
  result = initTable[string, BenchmarkResult]()
  
  let finalIterations = if iterations > 0: iterations else: suite.config.iterations
  
  var benchmarkOrder = toSeq(suite.benchmarks.keys)
  if suite.config.randomize:
    benchmarkOrder.shuffle()
  
  for name in benchmarkOrder:
    let bench = suite.benchmarks[name]
    if suite.config.captureMemory:
      result[name] = benchmarkMemory(name, finalIterations, bench)
    else:
      result[name] = benchmark(name, finalIterations, suite.config.warmup, bench)

proc compareBenchmarks*(iterations = 1000, body: untyped): BenchmarkComparison =
  var results: Table[string, BenchmarkResult]
  
  template benchmark(benchName: string, benchBody: untyped) =
    results[benchName] = benchmark(benchName, iterations, iterations div 10):
      benchBody
  
  body
  
  # Find fastest and slowest
  var fastest = ""
  var slowest = ""
  var minTime = float64.high
  var maxTime = 0.0
  
  for name, result in results:
    if result.avgTime < minTime:
      minTime = result.avgTime
      fastest = name
    if result.avgTime > maxTime:
      maxTime = result.avgTime
      slowest = name
  
  let speedup = maxTime / minTime
  
  BenchmarkComparison(
    results: results,
    fastest: fastest,
    slowest: slowest,
    speedup: speedup,
    summary: &"{fastest} is {speedup:.2f}x faster than {slowest}"
  )

proc benchmarkWithSetup*(name: string, setup: proc(), teardown: proc(), 
                        iterations = 1000, body: proc()): BenchmarkResult =
  setup()
  defer: teardown()
  benchmark(name, iterations, 0, body)

proc generateReport*(results: Table[string, BenchmarkResult]): string =
  result = "Benchmark Report\n"
  result &= "================\n\n"
  
  for name, res in results:
    result &= &"Benchmark: {name}\n"
    result &= &"  Iterations: {res.iterations}\n"
    result &= &"  Total Time: {res.totalTime:.2f} ms\n"
    result &= &"  Avg Time:   {res.avgTime:.4f} ms\n"
    result &= &"  Min Time:   {res.minTime:.4f} ms\n"
    result &= &"  Max Time:   {res.maxTime:.4f} ms\n"
    result &= &"  Std Dev:    {res.stdDev:.4f} ms\n"
    
    if res.memoryStats.avgMemory > 0:
      result &= &"  Avg Memory: {res.memoryStats.avgMemory} bytes\n"
      result &= &"  Peak Memory: {res.memoryStats.peakMemory} bytes\n"
    
    result &= "\n"

proc generateJsonReport*(results: Table[string, BenchmarkResult]): JsonNode =
  result = %*{
    "suite": "Benchmark Results",
    "timestamp": $getTime(),
    "results": newJObject()
  }
  
  for name, res in results:
    result["results"][name] = %*{
      "iterations": res.iterations,
      "totalTime": res.totalTime,
      "avgTime": res.avgTime,
      "minTime": res.minTime,
      "maxTime": res.maxTime,
      "stdDev": res.stdDev,
      "samples": res.samples,
      "memory": {
        "avg": res.memoryStats.avgMemory,
        "peak": res.memoryStats.peakMemory,
        "allocations": res.memoryStats.allocations
      }
    }

proc generateHtmlReport*(results: Table[string, BenchmarkResult], title = "Benchmark Results"): string =
  result = &"""
<!DOCTYPE html>
<html>
<head>
  <title>{title}</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 20px; }}
    table {{ border-collapse: collapse; width: 100%; margin: 20px 0; }}
    th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
    th {{ background-color: #4CAF50; color: white; }}
    tr:nth-child(even) {{ background-color: #f2f2f2; }}
    .number {{ text-align: right; }}
    .chart {{ width: 100%; height: 300px; margin: 20px 0; }}
  </style>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
  <h1>{title}</h1>
  <table>
    <tr>
      <th>Benchmark</th>
      <th class="number">Iterations</th>
      <th class="number">Avg Time (ms)</th>
      <th class="number">Min Time (ms)</th>
      <th class="number">Max Time (ms)</th>
      <th class="number">Std Dev (ms)</th>
      <th class="number">Memory (bytes)</th>
    </tr>
"""
  
  for name, res in results:
    result &= &"""
    <tr>
      <td>{name}</td>
      <td class="number">{res.iterations}</td>
      <td class="number">{res.avgTime:.4f}</td>
      <td class="number">{res.minTime:.4f}</td>
      <td class="number">{res.maxTime:.4f}</td>
      <td class="number">{res.stdDev:.4f}</td>
      <td class="number">{res.memoryStats.avgMemory}</td>
    </tr>
"""
  
  result &= """
  </table>
  
  <div class="chart">
    <canvas id="performanceChart"></canvas>
  </div>
  
  <script>
    const ctx = document.getElementById('performanceChart').getContext('2d');
    const data = {
      labels: ["""
  
  # Add benchmark names
  var first = true
  for name, _ in results:
    if not first:
      result &= ", "
    result &= &"'{name}'"
    first = false
  
  result &= "],\n      datasets: [{\n        label: 'Average Time (ms)',\n        data: ["
  
  # Add average times
  first = true
  for _, res in results:
    if not first:
      result &= ", "
    result &= &"{res.avgTime:.4f}"
    first = false
  
  result &= """
        ],
        backgroundColor: 'rgba(75, 192, 192, 0.2)',
        borderColor: 'rgba(75, 192, 192, 1)',
        borderWidth: 1
      }]
    };
    
    new Chart(ctx, {
      type: 'bar',
      data: data,
      options: {
        scales: {
          y: {
            beginAtZero: true
          }
        }
      }
    });
  </script>
</body>
</html>
"""

# Convenience functions
var globalBenchmarkSuite* = newBenchmarkSuite("Global")

proc bench*(name: string, body: proc()) =
  globalBenchmarkSuite.add(name, body)

proc runBenchmarks*(iterations = 1000): Table[string, BenchmarkResult] =
  globalBenchmarkSuite.run(iterations)

proc reportBenchmarks*(): string =
  generateReport(runBenchmarks())
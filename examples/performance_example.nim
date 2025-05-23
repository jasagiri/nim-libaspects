## Example demonstrating performance profiling and benchmarking
import nim_libaspects/profiler
import nim_libaspects/benchmark
import os
import strformat
import sequtils

# Example function to profile
proc expensiveComputation(n: int): int =
  profile("expensive_computation"):
    result = 0
    for i in 1..n:
      for j in 1..i:
        result += i * j

# Profile various operations
proc demonstrateProfiler() =
  echo "=== Profiler Demo ==="
  
  # Basic profiling
  globalProfiler.start("simple_operation")
  sleep(10)
  globalProfiler.stop("simple_operation")
  
  # Memory profiling
  globalProfiler.recordMemory("before_allocation")
  var largeData = newSeq[int](1000000)
  globalProfiler.recordMemory("after_allocation")
  
  # Multiple operations
  for i in 1..5:
    profile("iteration_" & $i):
      discard expensiveComputation(100)
  
  # Generate and display report
  let report = globalProfiler.generateReport()
  echo "\nProfile Report:"
  echo "--------------"
  for name, stats in report.profiles:
    echo &"{name}:"
    echo &"  Count: {stats.count}"
    echo &"  Avg Time: {stats.avgTime:.2f} ms"
    echo &"  Total Time: {stats.totalTime:.2f} ms"
  
  # Export to JSON
  let jsonReport = globalProfiler.exportJson()
  writeFile("profile_report.json", pretty(jsonReport))
  echo "\nProfile report saved to profile_report.json"

# Demonstrate benchmarking
proc demonstrateBenchmark() =
  echo "\n=== Benchmark Demo ==="
  
  # Compare sorting algorithms
  let comparison = compareBenchmarks(iterations = 100):
    benchmark("bubble_sort"):
      var data = @[64, 34, 25, 12, 22, 11, 90]
      for i in 0..<data.len:
        for j in 0..<data.len-i-1:
          if data[j] > data[j+1]:
            swap(data[j], data[j+1])
    
    benchmark("selection_sort"):
      var data = @[64, 34, 25, 12, 22, 11, 90]
      for i in 0..<data.len:
        var minIdx = i
        for j in i+1..<data.len:
          if data[j] < data[minIdx]:
            minIdx = j
        swap(data[i], data[minIdx])
  
  echo &"\nComparison Results:"
  echo &"Fastest: {comparison.fastest}"
  echo &"Speedup: {comparison.speedup:.2f}x"
  echo comparison.summary
  
  # Benchmark suite
  var suite = newBenchmarkSuite("String Operations")
  
  suite.add("concatenation") do:
    var s = ""
    for i in 1..100:
      s &= $i
  
  suite.add("join") do:
    let parts = toSeq(1..100).mapIt($it)
    discard parts.join("")
  
  suite.add("format") do:
    var s = ""
    for i in 1..100:
      s = &"{s}{i}"
  
  let results = suite.run(iterations = 100)
  echo "\nBenchmark Suite Results:"
  echo generateReport(results)
  
  # Save HTML report
  let htmlReport = generateHtmlReport(results, "String Operations Benchmark")
  writeFile("benchmark_report.html", htmlReport)
  echo "Benchmark report saved to benchmark_report.html"

when isMainModule:
  demonstrateProfiler()
  demonstrateBenchmark()
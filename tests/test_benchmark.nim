## Test suite for benchmark module
import unittest
import times
import sequtils
import tables
import math
import json
import nim_libaspects/benchmark

suite "Benchmark Tests":
  test "Basic benchmark":
    let result = benchmark("simple_operation", iterations = 100) do:
      var sum = 0
      for i in 1..1000:
        sum += i
    
    check(result.iterations == 100)
    check(result.totalTime > 0)
    check(result.avgTime > 0)
    check(result.minTime > 0)
    check(result.maxTime > 0)
    check(result.stdDev >= 0)
  
  test "Benchmark with warmup":
    let result = benchmark("with_warmup", iterations = 50, warmup = 10) do:
      var product = 1
      for i in 1..100:
        product *= i mod 10 + 1
    
    check(result.iterations == 50)
    check(result.warmupTime > 0)
  
  test "Memory benchmark":
    let result = benchmarkMemory("memory_test", iterations = 10) do:
      var data = newSeq[int](100000)
      for i in 0..<data.len:
        data[i] = i * 2
    
    check(result.iterations == 10)
    check(result.avgMemory >= 0)
    check(result.peakMemory >= result.avgMemory)
  
  test "Benchmark suite":
    var suite = newBenchmarkSuite("Math Operations")
    
    suite.add("addition") do:
      var sum = 0
      for i in 1..1000:
        sum += i
    
    suite.add("multiplication") do:
      var product = 1
      for i in 1..100:
        product *= (i mod 10) + 1
    
    suite.add("division") do:
      var result = 1000000.0
      for i in 1..100:
        result /= (i.float + 1.0)
    
    let results = suite.run(iterations = 100)
    
    check(results.len == 3)
    check(results.hasKey("addition"))
    check(results.hasKey("multiplication"))
    check(results.hasKey("division"))
  
  test "Comparative benchmark":
    proc bubbleSort(data: var seq[int]) =
      for i in 0..<data.len:
        for j in 0..<data.len-i-1:
          if data[j] > data[j+1]:
            swap(data[j], data[j+1])
    
    proc quickSort(data: var seq[int]) =
      if data.len <= 1:
        return
      let pivot = data[data.len div 2]
      var less = newSeq[int]()
      var equal = newSeq[int]()
      var greater = newSeq[int]()
      
      for x in data:
        if x < pivot:
          less.add(x)
        elif x == pivot:
          equal.add(x)
        else:
          greater.add(x)
      
      quickSort(less)
      quickSort(greater)
      data = less & equal & greater
    
    let comparison = compareBenchmarks(iterations = 10):
      benchmark("bubble_sort"):
        var data = toSeq(1..100)
        data.shuffle()
        bubbleSort(data)
      
      benchmark("quick_sort"):
        var data = toSeq(1..100)
        data.shuffle()
        quickSort(data)
    
    check(comparison.results.len == 2)
    check(comparison.fastest == "quick_sort" or comparison.fastest == "bubble_sort")
    check(comparison.speedup > 0)
  
  test "Statistical analysis":
    let samples = @[1.0, 2.0, 3.0, 4.0, 5.0]
    let stats = calculateStats(samples)
    
    check(stats.mean == 3.0)
    check(stats.median == 3.0)
    check(stats.stdDev > 0)
    check(stats.min == 1.0)
    check(stats.max == 5.0)
  
  test "Benchmark report":
    var suite = newBenchmarkSuite("Report Test")
    
    suite.add("test1") do:
      sleep(1)
    
    suite.add("test2") do:
      sleep(2)
    
    let results = suite.run(iterations = 5)
    let report = generateReport(results)
    
    check(report.contains("Report Test"))
    check(report.contains("test1"))
    check(report.contains("test2"))
    
    let jsonReport = generateJsonReport(results)
    check(jsonReport.hasKey("suite"))
    check(jsonReport.hasKey("results"))
  
  test "Benchmark with setup and teardown":
    var setupCalled = false
    var teardownCalled = false
    var data: seq[int]
    
    let result = benchmarkWithSetup("with_setup",
      setup = proc() =
        setupCalled = true
        data = newSeq[int](1000)
      ,
      teardown = proc() =
        teardownCalled = true
        data = @[]
      ,
      iterations = 10
    ) do:
      for i in 0..<data.len:
        data[i] = i * 2
    
    check(setupCalled)
    check(teardownCalled)
    check(result.iterations == 10)
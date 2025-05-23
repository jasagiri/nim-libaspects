## Test suite for profiler module
import unittest
import times
import sequtils
import tables
import json
import os
import nim_libaspects/profiler

suite "Profiler Tests":
  var profiler: Profiler
  
  setup:
    profiler = newProfiler()
  
  test "Basic profiling":
    profiler.start("test_operation")
    sleep(10)  # Simulate some work
    profiler.stop("test_operation")
    
    let profile = profiler.getProfile("test_operation")
    check(profile.count == 1)
    check(profile.totalTime > 0)
    check(profile.minTime > 0)
    check(profile.maxTime > 0)
    check(profile.avgTime > 0)
  
  test "Multiple operations":
    for i in 1..5:
      profiler.start("operation_1")
      sleep(5)
      profiler.stop("operation_1")
      
      profiler.start("operation_2")
      sleep(10)
      profiler.stop("operation_2")
    
    let profile1 = profiler.getProfile("operation_1")
    let profile2 = profiler.getProfile("operation_2")
    
    check(profile1.count == 5)
    check(profile2.count == 5)
    check(profile2.avgTime > profile1.avgTime)
  
  test "Nested operations":
    profiler.start("outer")
    profiler.start("inner")
    sleep(5)
    profiler.stop("inner")
    sleep(5)
    profiler.stop("outer")
    
    let innerProfile = profiler.getProfile("inner")
    let outerProfile = profiler.getProfile("outer")
    
    check(outerProfile.totalTime > innerProfile.totalTime)
  
  test "Auto-stop with scope":
    let span = profiler.span("auto_operation")
    sleep(10)
    # Span automatically stops when it goes out of scope
    
  test "Memory profiling":
    profiler.recordMemory("before_allocation")
    var data = newSeq[int](1000000)
    profiler.recordMemory("after_allocation")
    
    let beforeMem = profiler.getMemorySnapshot("before_allocation")
    let afterMem = profiler.getMemorySnapshot("after_allocation")
    
    check(afterMem.heapSize >= beforeMem.heapSize)
  
  test "Export profiles":
    profiler.start("export_test")
    sleep(5)
    profiler.stop("export_test")
    
    let report = profiler.generateReport()
    check(report.profiles.len > 0)
    check(report.profiles.hasKey("export_test"))
    
    let json = profiler.exportJson()
    check(json.hasKey("profiles"))
    check(json.hasKey("memory"))
  
  test "Threshold-based filtering":
    profiler.start("fast_op")
    sleep(1)
    profiler.stop("fast_op")
    
    profiler.start("slow_op")
    sleep(100)
    profiler.stop("slow_op")
    
    let filteredReport = profiler.generateReport(minDuration = 50)
    check(filteredReport.profiles.hasKey("slow_op"))
    check(not filteredReport.profiles.hasKey("fast_op"))
  
  test "Clear profiles":
    profiler.start("temp_op")
    profiler.stop("temp_op")
    
    check(profiler.getProfile("temp_op").count == 1)
    
    profiler.clear()
    
    expect(KeyError):
      discard profiler.getProfile("temp_op")
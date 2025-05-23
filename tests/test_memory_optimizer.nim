## Test suite for memory optimizer module
import unittest
import sequtils
import tables
import json
import nim_libaspects/memory_optimizer

suite "Memory Optimizer Tests":
  test "Memory pool basic operations":
    var pool = newMemoryPool[int](blockSize = 10)
    
    let obj1 = pool.allocate()
    obj1[] = 42
    check(obj1[] == 42)
    
    let obj2 = pool.allocate()
    obj2[] = 100
    check(obj2[] == 100)
    
    pool.deallocate(obj1)
    
    let obj3 = pool.allocate()  # Should reuse obj1's slot
    obj3[] = 200
    check(obj3[] == 200)
    
    check(pool.getAllocatedCount() == 2)
    check(pool.getTotalBlocks() == 1)
  
  test "Memory pool expansion":
    var pool = newMemoryPool[string](blockSize = 2)
    
    var objects: seq[ptr string] = @[]
    
    # Allocate more than block size
    for i in 0..4:
      let obj = pool.allocate()
      obj[] = "test" & $i
      objects.add(obj)
    
    check(pool.getAllocatedCount() == 5)
    check(pool.getTotalBlocks() == 3)  # Should have expanded
    
    # Verify all objects are intact
    for i, obj in objects:
      check(obj[] == "test" & $i)
  
  test "Object pool with recycling":
    var pool = newObjectPool[seq[int]](
      maxSize = 5,
      factory = proc(): seq[int] = newSeq[int](),
      reset = proc(obj: var seq[int]) = obj.setLen(0)
    )
    
    var objects: seq[seq[int]] = @[]
    
    # Get objects from pool
    for i in 0..2:
      var obj = pool.get()
      obj.add(i)
      objects.add(obj)
    
    check(pool.size() == 0)  # All objects taken
    
    # Return objects to pool
    for obj in objects:
      pool.put(obj)
    
    check(pool.size() == 3)
    
    # Get recycled object
    var recycled = pool.get()
    check(recycled.len == 0)  # Should be reset
  
  test "Memory tracking":
    enableMemoryTracking()
    
    trackAllocation("test_array", 1000)
    trackAllocation("test_table", 500)
    trackAllocation("test_array", 1000)  # Another allocation
    
    let stats = getMemoryStats()
    check(stats["test_array"].count == 2)
    check(stats["test_array"].totalSize == 2000)
    check(stats["test_table"].count == 1)
    check(stats["test_table"].totalSize == 500)
    
    trackDeallocation("test_array", 1000)
    
    let updatedStats = getMemoryStats()
    check(updatedStats["test_array"].currentSize == 1000)
    
    disableMemoryTracking()
  
  test "Memory compactor":
    type TestObject = object
      id: int
      data: string
      next: ref TestObject
    
    var objects: seq[ref TestObject] = @[]
    
    # Create fragmented memory
    for i in 0..9:
      var obj = new TestObject
      obj.id = i
      obj.data = "Object " & $i
      objects.add(obj)
    
    # Remove every other object to create gaps
    for i in countup(1, 9, 2):
      objects[i] = nil
    
    # Compact memory
    let compactor = newMemoryCompactor()
    let report = compactor.compact()
    
    check(report.totalObjects > 0)
    check(report.compactedObjects >= 0)
    
  test "Memory limits":
    setMemoryLimit("test_category", 1024)  # 1KB limit
    
    check(checkMemoryLimit("test_category", 500))
    allocateWithLimit("test_category", 500)
    
    check(checkMemoryLimit("test_category", 600) == false)
    
    expect(MemoryLimitExceeded):
      allocateWithLimit("test_category", 600)
    
    clearMemoryLimits()
  
  test "Weak references":
    var strongRef = new int
    strongRef[] = 42
    
    let weakRef = newWeakRef(strongRef)
    
    check(weakRef.isAlive())
    check(weakRef.get()[] == 42)
    
    strongRef = nil
    GC_fullCollect()
    
    check(not weakRef.isAlive())
    check(weakRef.get() == nil)
  
  test "Memory profiling":
    let snapshot1 = takeMemorySnapshot("before")
    
    var data = newSeq[int](10000)
    for i in 0..<data.len:
      data[i] = i
    
    let snapshot2 = takeMemorySnapshot("after")
    
    let diff = compareSnapshots(snapshot1, snapshot2)
    check(diff.heapGrowth > 0)
    check(diff.allocations.len > 0)
    
    let report = generateMemoryReport()
    check(report.contains("Memory Report"))
    check(report.contains("before"))
    check(report.contains("after"))
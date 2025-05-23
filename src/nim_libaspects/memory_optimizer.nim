## Memory optimization utilities
## Provides memory pooling, tracking, and optimization tools

import std/[
  tables,
  sequtils,
  json,
  strformat,
  times,
  locks,
  hashes,
  sets
]
import ./errors

type
  # Memory pool for fixed-size objects
  MemoryPool*[T] = ref object
    blocks: seq[seq[T]]
    freeList: seq[ptr T]
    blockSize: int
    allocated: int
    lock: Lock
  
  # Object pool for recyclable objects
  ObjectPool*[T] = ref object
    available: seq[T]
    maxSize: int
    factory: proc(): T
    reset: proc(obj: var T)
    lock: Lock
  
  # Memory tracking
  AllocationInfo* = object
    count*: int
    totalSize*: int64
    currentSize*: int64
    peakSize*: int64
    locations*: seq[string]
  
  MemorySnapshot* = object
    timestamp*: Time
    heapSize*: int64
    allocations*: Table[string, AllocationInfo]
    gcStats*: GC_Statistics
  
  MemoryDiff* = object
    heapGrowth*: int64
    allocations*: seq[tuple[name: string, delta: int64]]
    deallocations*: seq[tuple[name: string, delta: int64]]
  
  # Memory compactor
  CompactionReport* = object
    totalObjects*: int
    compactedObjects*: int
    freedBytes*: int64
    duration*: Duration
  
  MemoryCompactor* = ref object
    enabled: bool
    threshold: float  # Fragmentation threshold
  
  # Weak references
  WeakRef*[T] = ref object
    id: int
    registry: ptr Table[int, ref T]
  
  MemoryLimitExceeded* = object of CatchableError

var
  memoryTracking {.global.} = false
  memoryAllocations {.global.}: Table[string, AllocationInfo]
  memoryLock {.global.}: Lock
  memoryLimits {.global.}: Table[string, int64]
  weakRefRegistry {.global.}: Table[int, ref object]
  weakRefCounter {.global.} = 0
  weakRefLock {.global.}: Lock

initLock(memoryLock)
initLock(weakRefLock)

# Memory Pool Implementation
proc newMemoryPool*[T](blockSize = 1024): MemoryPool[T] =
  result = MemoryPool[T](
    blocks: @[],
    freeList: @[],
    blockSize: blockSize,
    allocated: 0
  )
  initLock(result.lock)

proc expandPool[T](pool: MemoryPool[T]) =
  var newBlock = newSeq[T](pool.blockSize)
  pool.blocks.add(newBlock)
  
  # Add all new slots to free list
  for i in 0..<pool.blockSize:
    pool.freeList.add(addr pool.blocks[^1][i])

proc allocate*[T](pool: MemoryPool[T]): ptr T =
  withLock(pool.lock):
    if pool.freeList.len == 0:
      pool.expandPool()
    
    result = pool.freeList.pop()
    inc pool.allocated

proc deallocate*[T](pool: MemoryPool[T], obj: ptr T) =
  withLock(pool.lock):
    pool.freeList.add(obj)
    dec pool.allocated

proc getAllocatedCount*[T](pool: MemoryPool[T]): int =
  withLock(pool.lock):
    pool.allocated

proc getTotalBlocks*[T](pool: MemoryPool[T]): int =
  withLock(pool.lock):
    pool.blocks.len

# Object Pool Implementation
proc newObjectPool*[T](maxSize: int, factory: proc(): T, reset: proc(obj: var T) = nil): ObjectPool[T] =
  result = ObjectPool[T](
    available: @[],
    maxSize: maxSize,
    factory: factory,
    reset: reset
  )
  initLock(result.lock)

proc get*[T](pool: ObjectPool[T]): T =
  withLock(pool.lock):
    if pool.available.len > 0:
      result = pool.available.pop()
    else:
      result = pool.factory()

proc put*[T](pool: ObjectPool[T], obj: T) =
  withLock(pool.lock):
    if pool.available.len < pool.maxSize:
      var objCopy = obj
      if pool.reset != nil:
        pool.reset(objCopy)
      pool.available.add(objCopy)

proc size*[T](pool: ObjectPool[T]): int =
  withLock(pool.lock):
    pool.available.len

# Memory Tracking
proc enableMemoryTracking*() =
  withLock(memoryLock):
    memoryTracking = true
    memoryAllocations.clear()

proc disableMemoryTracking*() =
  withLock(memoryLock):
    memoryTracking = false

proc trackAllocation*(name: string, size: int64, location = "") =
  if not memoryTracking:
    return
  
  withLock(memoryLock):
    if name notin memoryAllocations:
      memoryAllocations[name] = AllocationInfo()
    
    var info = memoryAllocations[name]
    inc info.count
    info.totalSize += size
    info.currentSize += size
    info.peakSize = max(info.peakSize, info.currentSize)
    if location != "":
      info.locations.add(location)
    memoryAllocations[name] = info

proc trackDeallocation*(name: string, size: int64) =
  if not memoryTracking:
    return
  
  withLock(memoryLock):
    if name in memoryAllocations:
      memoryAllocations[name].currentSize -= size

proc getMemoryStats*(): Table[string, AllocationInfo] =
  withLock(memoryLock):
    result = memoryAllocations

# Memory Limits
proc setMemoryLimit*(category: string, limitBytes: int64) =
  withLock(memoryLock):
    memoryLimits[category] = limitBytes

proc checkMemoryLimit*(category: string, requestedSize: int64): bool =
  withLock(memoryLock):
    if category notin memoryLimits:
      return true
    
    let limit = memoryLimits[category]
    let current = if category in memoryAllocations:
      memoryAllocations[category].currentSize
    else:
      0
    
    return current + requestedSize <= limit

proc allocateWithLimit*(category: string, size: int64) =
  if not checkMemoryLimit(category, size):
    raise newException(MemoryLimitExceeded, 
      &"Memory limit exceeded for category '{category}'")
  
  trackAllocation(category, size)

proc clearMemoryLimits*() =
  withLock(memoryLock):
    memoryLimits.clear()

# Weak References
proc newWeakRef*[T](obj: ref T): WeakRef[T] =
  withLock(weakRefLock):
    inc weakRefCounter
    let id = weakRefCounter
    weakRefRegistry[id] = cast[ref object](obj)
    
    result = WeakRef[T](
      id: id,
      registry: addr weakRefRegistry
    )

proc isAlive*[T](weak: WeakRef[T]): bool =
  withLock(weakRefLock):
    weak.id in weakRefRegistry

proc get*[T](weak: WeakRef[T]): ref T =
  withLock(weakRefLock):
    if weak.id in weakRefRegistry:
      result = cast[ref T](weakRefRegistry[weak.id])

# Memory Snapshots
proc takeMemorySnapshot*(label: string): MemorySnapshot =
  let stats = GC_getStatistics()
  result = MemorySnapshot(
    timestamp: getTime(),
    heapSize: stats.maxHeapSize,
    allocations: getMemoryStats(),
    gcStats: stats
  )

proc compareSnapshots*(before, after: MemorySnapshot): MemoryDiff =
  result.heapGrowth = after.heapSize - before.heapSize
  
  # Find new allocations
  for name, info in after.allocations:
    if name notin before.allocations:
      result.allocations.add((name, info.currentSize))
    else:
      let delta = info.currentSize - before.allocations[name].currentSize
      if delta > 0:
        result.allocations.add((name, delta))
      elif delta < 0:
        result.deallocations.add((name, -delta))

# Memory Compactor
proc newMemoryCompactor*(threshold = 0.3): MemoryCompactor =
  MemoryCompactor(
    enabled: true,
    threshold: threshold
  )

proc compact*(compactor: MemoryCompactor): CompactionReport =
  let startTime = getTime()
  let statsBefore = GC_getStatistics()
  
  # Force full garbage collection
  GC_fullCollect()
  
  let statsAfter = GC_getStatistics()
  let endTime = getTime()
  
  result = CompactionReport(
    totalObjects: statsAfter.totalAllocated.int,
    compactedObjects: (statsBefore.totalAllocated - statsAfter.totalAllocated).int,
    freedBytes: statsBefore.maxHeapSize - statsAfter.maxHeapSize,
    duration: endTime - startTime
  )

# Memory Reports
proc generateMemoryReport*(): string =
  result = "Memory Report\n"
  result &= "=============\n\n"
  
  let stats = GC_getStatistics()
  result &= &"Heap Size: {stats.maxHeapSize} bytes\n"
  result &= &"Total Allocated: {stats.totalAllocated}\n"
  result &= &"Total Deallocated: {stats.totalDeallocated}\n\n"
  
  result &= "Allocations by Category:\n"
  for name, info in getMemoryStats():
    result &= &"  {name}:\n"
    result &= &"    Count: {info.count}\n"
    result &= &"    Current: {info.currentSize} bytes\n"
    result &= &"    Peak: {info.peakSize} bytes\n"
    result &= &"    Total: {info.totalSize} bytes\n"

proc generateJsonReport*(): JsonNode =
  let stats = GC_getStatistics()
  result = %*{
    "timestamp": $getTime(),
    "heap": {
      "size": stats.maxHeapSize,
      "allocated": stats.totalAllocated,
      "deallocated": stats.totalDeallocated
    },
    "allocations": newJObject()
  }
  
  for name, info in getMemoryStats():
    result["allocations"][name] = %*{
      "count": info.count,
      "current": info.currentSize,
      "peak": info.peakSize,
      "total": info.totalSize,
      "locations": info.locations
    }

# Auto-cleanup helpers
template withMemoryPool*(T: typedesc, poolVar: untyped, blockSize: int, body: untyped) =
  var poolVar = newMemoryPool[T](blockSize)
  try:
    body
  finally:
    discard

template withObjectPool*(T: typedesc, poolVar: untyped, size: int, 
                        factory: proc(): T, body: untyped) =
  var poolVar = newObjectPool[T](size, factory)
  try:
    body
  finally:
    discard

# Memory optimization recommendations
proc analyzeMemoryUsage*(): seq[string] =
  result = @[]
  
  let stats = GC_getStatistics()
  let heapUsage = stats.maxHeapSize.float / stats.totalAllocated.float
  
  if heapUsage > 0.8:
    result.add("High heap fragmentation detected. Consider compaction.")
  
  for name, info in getMemoryStats():
    if info.peakSize > info.currentSize * 2:
      result.add(&"Category '{name}' shows high peak usage. Consider pooling.")
    
    if info.count > 10000 and info.totalSize / info.count < 100:
      result.add(&"Category '{name}' has many small allocations. Consider batching.")

# Export convenience functions
proc optimizeMemory*() =
  GC_fullCollect()
  let compactor = newMemoryCompactor()
  discard compactor.compact()
import std/[
  unittest,
  times,
  asyncdispatch,
  json,
  tables,
  strutils,
  options,
  sequtils
]
import nim_libaspects/cache

suite "Cache System":
  var cache: Cache[string, string]
  
  setup:
    cache = newCache[string, string]()
    
  test "Basic cache operations":
    # Test put and get
    cache.put("key1", "value1")
    let value = cache.get("key1")
    check(value.isSome)
    check(value.get() == "value1")
    
    # Test missing key
    let missing = cache.get("nonexistent")
    check(missing.isNone)
    
  test "TTL management":
    # Test with TTL
    let ttlCache = newCache[string, string](defaultTTL = initDuration(seconds = 1))
    ttlCache.put("temp", "value", ttl = initDuration(seconds = 1))
    
    # Value should exist immediately
    check(ttlCache.get("temp").isSome)
    
    # Wait for expiration
    waitFor sleepAsync(1100)
    
    # Value should be gone
    check(ttlCache.get("temp").isNone)
    
  test "LRU eviction":
    # Create cache with max size
    let lruCache = newLRUCache[string, string](maxSize = 3)
    
    # Fill cache
    lruCache.put("a", "1")
    lruCache.put("b", "2")
    lruCache.put("c", "3")
    
    # Access 'a' to make it recently used
    discard lruCache.get("a")
    
    # Add new item, should evict 'b' (least recently used)
    lruCache.put("d", "4")
    
    check(lruCache.get("a").isSome)
    check(lruCache.get("b").isNone)  # Evicted
    check(lruCache.get("c").isSome)
    check(lruCache.get("d").isSome)
    
  test "LFU eviction":
    # Create cache with LFU policy
    let lfuCache = newLFUCache[string, int](maxSize = 3)
    
    # Add items with different access frequencies
    lfuCache.put("a", 1)
    lfuCache.put("b", 2)
    lfuCache.put("c", 3)
    
    # Access items different number of times
    discard lfuCache.get("a")  # Accessed twice (put + get)
    discard lfuCache.get("a")  # Accessed three times
    discard lfuCache.get("b")  # Accessed twice
    # c is accessed only once (during put)
    
    # Add new item, should evict 'c' (least frequently used)
    lfuCache.put("d", 4)
    
    check(lfuCache.get("a").isSome)
    check(lfuCache.get("b").isSome)
    check(lfuCache.get("c").isNone)  # Evicted
    check(lfuCache.get("d").isSome)
    
  test "Cache invalidation":
    cache.put("key1", "value1")
    cache.put("key2", "value2")
    cache.put("key3", "value3")
    
    # Invalidate single key
    cache.invalidate("key1")
    check(cache.get("key1").isNone)
    check(cache.get("key2").isSome)
    
    # Invalidate all
    cache.invalidateAll()
    check(cache.get("key2").isNone)
    check(cache.get("key3").isNone)
    
  test "Cache statistics":
    let statCache = newCache[string, string](enableStats = true)
    
    # Generate some activity
    statCache.put("key1", "value1")
    discard statCache.get("key1")  # Hit
    discard statCache.get("key2")  # Miss
    discard statCache.get("key1")  # Hit
    
    let stats = statCache.getStats()
    check(stats.hits == 2)
    check(stats.misses == 1)
    check(stats.puts == 1)
    check(stats.evictions == 0)
    check(stats.hitRate == 2.0 / 3.0)
    
  test "Async cache operations":
    let asyncCache = newAsyncCache[string, string]()
    
    proc testAsync() {.async.} =
      # Async put
      await asyncCache.put("async1", "value1")
      
      # Async get
      let value = await asyncCache.get("async1")
      check(value.isSome)
      check(value.get() == "value1")
      
      # Async compute if absent
      let computed = await asyncCache.computeIfAbsent("async2", 
        proc(): Future[string] {.async.} =
          await sleepAsync(10)
          return "computed"
      )
      check(computed == "computed")
      
      # Should not compute again
      let cached = await asyncCache.get("async2")
      check(cached.get() == "computed")
    
    waitFor testAsync()
    
  test "Cache loader function":
    var loadCount = 0
    let loadingCache = newLoadingCache[string, int](
      loader = proc(key: string): int =
        inc loadCount
        return key.len
    )
    
    # First access loads value
    let val1 = loadingCache.get("hello")
    check(val1.get() == 5)
    check(loadCount == 1)
    
    # Second access uses cache
    let val2 = loadingCache.get("hello")
    check(val2.get() == 5)
    check(loadCount == 1)  # No additional load
    
    # Different key loads again
    let val3 = loadingCache.get("world!")
    check(val3.get() == 6)
    check(loadCount == 2)
    
  test "Typed cache with complex types":
    type
      User = object
        id: int
        name: string
        tags: seq[string]
    
    let userCache = newCache[int, User]()
    
    let user = User(
      id: 1,
      name: "Alice",
      tags: @["admin", "developer"]
    )
    
    userCache.put(1, user)
    let cached = userCache.get(1)
    
    check(cached.isSome)
    check(cached.get().name == "Alice")
    check(cached.get().tags.len == 2)
    
  test "Cache serialization":
    # Test cache persistence
    cache.put("persist1", "value1")
    cache.put("persist2", "value2")
    
    # Save cache state
    let state = cache.save()
    
    # Create new cache and restore
    var newCache = newCache[string, string]()
    newCache.load(state)
    
    let val1 = newCache.get("persist1")
    check(val1.isSome)
    check(val1.get() == "value1")
    
    let val2 = newCache.get("persist2")
    check(val2.isSome)
    check(val2.get() == "value2")
    
  test "Pattern-based invalidation":
    cache.put("user:1", "Alice")
    cache.put("user:2", "Bob")
    cache.put("item:1", "Book")
    cache.put("item:2", "Pen")
    
    # Invalidate by pattern
    cache.invalidatePattern("user:*")
    
    check(cache.get("user:1").isNone)
    check(cache.get("user:2").isNone)
    check(cache.get("item:1").isSome)
    check(cache.get("item:2").isSome)
    
  test "Multi-level cache":
    # Create L1 and L2 caches
    let l1Cache = newCache[string, string](maxSize = 2)
    let l2Cache = newCache[string, string](maxSize = 5)
    
    let multiCache = newMultiLevelCache[string, string](
      levels = @[l1Cache, l2Cache]
    )
    
    # Put goes to all levels
    multiCache.put("key1", "value1")
    
    # Get checks L1 first, then L2
    let value = multiCache.get("key1")
    check(value.isSome)
    
    # Fill L1 to capacity
    multiCache.put("key2", "value2")
    multiCache.put("key3", "value3")  # This evicts key1 from L1
    
    # key1 should still be in L2
    check(l1Cache.get("key1").isNone)
    check(l2Cache.get("key1").isSome)
    
    # Getting key1 promotes it back to L1
    discard multiCache.get("key1")
    check(l1Cache.get("key1").isSome)
    
  test "Cache listeners":
    var events: seq[CacheEvent] = @[]
    let listenCache = newCache[string, string]()
    
    # Use a shared variable for thread safety
    var eventsPtr = addr events
    
    listenCache.onEvent = proc(event: CacheEvent) {.gcsafe.} =
      eventsPtr[].add(event)
    
    listenCache.put("key1", "value1")
    discard listenCache.get("key1")
    listenCache.invalidate("key1")
    
    check(events.len == 3)
    check(events[0].eventType == CacheEventType.Put)
    check(events[1].eventType == CacheEventType.Hit)
    check(events[2].eventType == CacheEventType.Evict)
    
  test "Distributed cache interface":
    # Test distributed cache abstraction
    let distCache = newDistributedCache[string, string](
      namespace = "test",
      nodes = @["localhost:6379"]
    )
    
    # Should support same operations
    waitFor distCache.put("dist1", "value1")
    let value = waitFor distCache.get("dist1")
    check(value.isSome)
    
    # Test distributed invalidation
    waitFor distCache.invalidateAll()
    let after = waitFor distCache.get("dist1")
    check(after.isNone)
    
  test "Cache warmup":
    let warmupCache = newCache[string, string]()
    
    # Define warmup data
    let warmupData = {
      "preload1": "value1",
      "preload2": "value2",
      "preload3": "value3"
    }.toTable
    
    # Warm up cache
    warmupCache.warmup(warmupData)
    
    # All values should be available
    check(warmupCache.get("preload1").get() == "value1")
    check(warmupCache.get("preload2").get() == "value2")
    check(warmupCache.get("preload3").get() == "value3")
    
  test "Cache groups":
    let groupCache = newGroupCache[string, string]()
    
    # Put with groups
    groupCache.put("key1", "value1", groups = @["groupA"])
    groupCache.put("key2", "value2", groups = @["groupA", "groupB"])
    groupCache.put("key3", "value3", groups = @["groupB"])
    
    # Invalidate by group
    groupCache.invalidateGroup("groupA")
    
    check(groupCache.get("key1").isNone)
    check(groupCache.get("key2").isNone)
    check(groupCache.get("key3").isSome)  # Only in groupB
    
  test "Memory-aware cache":
    let memCache = newMemoryAwareCache[string, string](
      maxMemoryMB = 100  # 100MB limit
    )
    
    # Put items
    memCache.put("key1", "x".repeat(1_000_000))  # ~1MB
    memCache.put("key2", "x".repeat(1_000_000))  # ~1MB
    
    let memStats = memCache.getMemoryStats()
    check(memStats.usedMemoryMB > 0)
    check(memStats.usedMemoryMB < 100)
    
    # Should evict when memory limit approached
    for i in 3..150:
      memCache.put("key" & $i, "x".repeat(1_000_000))
    
    check(memCache.getMemoryStats().usedMemoryMB <= 100)
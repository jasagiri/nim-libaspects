## Cache module provides comprehensive caching capabilities including
## TTL management, eviction policies, distributed caching, and statistics.

import std/[
  tables,
  times,
  options,
  asyncdispatch,
  json,
  sequtils,
  strutils,
  strformat,
  heapqueue,
  locks,
  os
]
import nim_core
import nim_corepkg/ast/cache as nim_core_cache
import nim_corepkg/utils/common as nim_core_common
import nim_corepkg/ast/analyzer as ast_analyzer

type
  CacheEventType* = enum
    Put = "put"
    Get = "get"
    Hit = "hit"
    Miss = "miss"
    Evict = "evict"
    Expire = "expire"
  
  CacheEvent* = object
    eventType*: CacheEventType
    key*: string
    timestamp*: Time
  
  CacheEntry[V] = object
    value: V
    expiry: Option[Time]
    accessCount: int
    lastAccess: Time
    size: int
  
  CacheStats* = object
    hits*: int64
    misses*: int64
    puts*: int64
    evictions*: int64
    expirations*: int64
    hitRate*: float
  
  EvictionPolicy* = enum
    LRU = "lru"  # Least Recently Used
    LFU = "lfu"  # Least Frequently Used
    FIFO = "fifo"  # First In First Out
  
  Cache*[K, V] = ref object of RootObj
    data*: Table[K, CacheEntry[V]]
    maxSize*: int
    currentSize*: int
    defaultTTL*: Duration
    evictionPolicy*: EvictionPolicy
    enableStats*: bool
    stats*: CacheStats
    onEvent*: proc(event: CacheEvent) {.gcsafe.}
    lock: Lock
  
  LoadingCache*[K, V] = ref object of Cache[K, V]
    loader*: proc(key: K): V {.gcsafe.}
  
  AsyncCache*[K, V] = ref object
    cache: Cache[K, V]
  
  MultiLevelCache*[K, V] = ref object
    levels: seq[Cache[K, V]]
  
  DistributedCache*[K, V] = ref object
    namespace: string
    nodes: seq[string]
    localCache: Cache[K, V]
  
  GroupCache*[K, V] = ref object of Cache[K, V]
    groups: Table[string, seq[K]]
    keyGroups: Table[K, seq[string]]
  
  MemoryAwareCache*[K, V] = ref object of Cache[K, V]
    maxMemoryBytes: int64
    currentMemoryBytes: int64
  
  MemoryStats* = object
    usedMemoryMB*: float
    maxMemoryMB*: float
    evictionCount*: int

# Initialize lock
var cacheLock: Lock
initLock(cacheLock)

# Create new cache
proc newCache*[K, V](
  maxSize: int = 1000,
  defaultTTL: Duration = initDuration(0),
  evictionPolicy: EvictionPolicy = LRU,
  enableStats: bool = false
): Cache[K, V] =
  result = Cache[K, V](
    data: initTable[K, CacheEntry[V]](),
    maxSize: maxSize,
    currentSize: 0,
    defaultTTL: defaultTTL,
    evictionPolicy: evictionPolicy,
    enableStats: enableStats,
    stats: CacheStats()
  )
  initLock(result.lock)

# Create LRU cache
proc newLRUCache*[K, V](maxSize: int = 1000): Cache[K, V] =
  result = newCache[K, V](
    maxSize = maxSize,
    evictionPolicy = LRU,
    enableStats = true
  )

# Create LFU cache
proc newLFUCache*[K, V](maxSize: int = 1000): Cache[K, V] =
  result = newCache[K, V](
    maxSize = maxSize,
    evictionPolicy = LFU,
    enableStats = true
  )

# Check if entry is expired
proc isExpired[V](entry: CacheEntry[V]): bool =
  if entry.expiry.isSome:
    return entry.expiry.get() < getTime()
  return false

# Evict entries based on policy
proc evict[K, V](cache: Cache[K, V]) =
  if cache.data.len == 0:
    return
  
  var keyToEvict: K
  var found = false
  
  case cache.evictionPolicy
  of LRU:
    # Find least recently used
    var oldestTime = getTime()
    for key, entry in cache.data.pairs:
      if entry.lastAccess < oldestTime:
        oldestTime = entry.lastAccess
        keyToEvict = key
        found = true
  
  of LFU:
    # Find least frequently used
    var minCount = int.high
    for key, entry in cache.data.pairs:
      if entry.accessCount < minCount:
        minCount = entry.accessCount
        keyToEvict = key
        found = true
  
  of FIFO:
    # Just take the first one (simple implementation)
    for key in cache.data.keys:
      keyToEvict = key
      found = true
      break
  
  if found:
    cache.data.del(keyToEvict)
    inc cache.stats.evictions
    cache.currentSize -= 1
    if not cache.onEvent.isNil:
      cache.onEvent(CacheEvent(
        eventType: CacheEventType.Evict,
        key: $keyToEvict,
        timestamp: getTime()
      ))

# Put value in cache
proc put*[K, V](cache: Cache[K, V], key: K, value: V, ttl: Duration = initDuration(0)) =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  let effectiveTTL = if ttl.inSeconds > 0: ttl else: cache.defaultTTL
  let expiry = if effectiveTTL.inSeconds > 0:
    some(getTime() + effectiveTTL)
  else:
    none(Time)
  
  # Check if we need to evict
  if key notin cache.data and cache.currentSize >= cache.maxSize:
    cache.evict()
  
  let entry = CacheEntry[V](
    value: value,
    expiry: expiry,
    accessCount: 1,
    lastAccess: getTime(),
    size: sizeof(value)
  )
  
  let isNew = key notin cache.data
  cache.data[key] = entry
  
  if isNew:
    inc cache.currentSize
  
  if cache.enableStats:
    inc cache.stats.puts
  
  if not cache.onEvent.isNil:
    cache.onEvent(CacheEvent(
      eventType: CacheEventType.Put,
      key: $key,
      timestamp: getTime()
    ))

# Get value from cache
proc get*[K, V](cache: Cache[K, V], key: K): Option[V] =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  if key in cache.data:
    var entry = cache.data[key]
    
    # Check expiration
    if entry.isExpired:
      cache.data.del(key)
      dec cache.currentSize
      if cache.enableStats:
        inc cache.stats.expirations
        inc cache.stats.misses
      return none(V)
    
    # Update access info
    entry.accessCount += 1
    entry.lastAccess = getTime()
    cache.data[key] = entry
    
    if cache.enableStats:
      inc cache.stats.hits
    
    if not cache.onEvent.isNil:
      cache.onEvent(CacheEvent(
        eventType: CacheEventType.Hit,
        key: $key,
        timestamp: getTime()
      ))
    
    return some(entry.value)
  
  if cache.enableStats:
    inc cache.stats.misses
  
  if not cache.onEvent.isNil:
    cache.onEvent(CacheEvent(
      eventType: CacheEventType.Miss,
      key: $key,
      timestamp: getTime()
    ))
  
  return none(V)

# Invalidate single key
proc invalidate*[K, V](cache: Cache[K, V], key: K) =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  if key in cache.data:
    cache.data.del(key)
    dec cache.currentSize
    if not cache.onEvent.isNil:
      cache.onEvent(CacheEvent(
        eventType: CacheEventType.Evict,
        key: $key,
        timestamp: getTime()
      ))

# Invalidate all entries
proc invalidateAll*[K, V](cache: Cache[K, V]) =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  cache.data.clear()
  cache.currentSize = 0

# Get cache statistics
proc getStats*[K, V](cache: Cache[K, V]): CacheStats =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  result = cache.stats
  if cache.stats.hits + cache.stats.misses > 0:
    result.hitRate = float(cache.stats.hits) / float(cache.stats.hits + cache.stats.misses)
  else:
    result.hitRate = 0.0

# Create loading cache
proc newLoadingCache*[K, V](
  loader: proc(key: K): V {.gcsafe.},
  maxSize: int = 1000,
  defaultTTL: Duration = initDuration(0)
): LoadingCache[K, V] =
  result = LoadingCache[K, V](
    loader: loader
  )
  result.data = initTable[K, CacheEntry[V]]()
  result.maxSize = maxSize
  result.defaultTTL = defaultTTL
  result.evictionPolicy = LRU
  result.enableStats = true
  initLock(result.lock)

# Get with loading
proc get*[K, V](cache: LoadingCache[K, V], key: K): Option[V] =
  # Try regular get first
  let cached = Cache[K, V](cache).get(key)
  if cached.isSome:
    return cached
  
  # Load if not found
  let value = cache.loader(key)
  cache.put(key, value)
  return some(value)

# Create async cache wrapper
proc newAsyncCache*[K, V](): AsyncCache[K, V] =
  result = AsyncCache[K, V](
    cache: newCache[K, V]()
  )

# Async put
proc put*[K, V](cache: AsyncCache[K, V], key: K, value: V, ttl: Duration = initDuration(0)): Future[void] {.async.} =
  cache.cache.put(key, value, ttl)

# Async get  
proc get*[K, V](cache: AsyncCache[K, V], key: K): Future[Option[V]] {.async.} =
  return cache.cache.get(key)

# Compute if absent
proc computeIfAbsent*[K, V](
  cache: AsyncCache[K, V], 
  key: K, 
  compute: proc(): Future[V] {.gcsafe.}
): Future[V] {.async.} =
  let existing = await cache.get(key)
  if existing.isSome:
    return existing.get()
  
  let value = await compute()
  await cache.put(key, value)
  return value

# Create multi-level cache
proc newMultiLevelCache*[K, V](levels: seq[Cache[K, V]]): MultiLevelCache[K, V] =
  result = MultiLevelCache[K, V](
    levels: levels
  )

# Multi-level put
proc put*[K, V](cache: MultiLevelCache[K, V], key: K, value: V, ttl: Duration = initDuration(0)) =
  for level in cache.levels:
    level.put(key, value, ttl)

# Multi-level get with promotion
proc get*[K, V](cache: MultiLevelCache[K, V], key: K): Option[V] =
  for i, level in cache.levels:
    let value = level.get(key)
    if value.isSome:
      # Promote to higher levels
      for j in 0..<i:
        cache.levels[j].put(key, value.get())
      return value
  return none(V)

# Save cache state
proc save*[K, V](cache: Cache[K, V]): JsonNode =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  result = %*{
    "maxSize": cache.maxSize,
    "evictionPolicy": $cache.evictionPolicy,
    "entries": %*{}
  }
  
  for key, entry in cache.data.pairs:
    if not entry.isExpired:
      result["entries"][$key] = %*{
        "value": $(entry.value),  # Simple serialization
        "expiry": if entry.expiry.isSome: entry.expiry.get().toUnix else: 0,
        "accessCount": entry.accessCount
      }

# Load cache state  
proc load*[K, V](cache: Cache[K, V], state: JsonNode) =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  cache.data.clear()
  cache.currentSize = 0
  
  if state.hasKey("maxSize"):
    cache.maxSize = state["maxSize"].getInt()
  
  if state.hasKey("evictionPolicy"):
    cache.evictionPolicy = parseEnum[EvictionPolicy](state["evictionPolicy"].getStr())
  
  if state.hasKey("entries"):
    for key, entryData in state["entries"]:
      when K is string and V is string:
        let value = entryData["value"].getStr()
        let expiry = if entryData["expiry"].getInt() > 0:
          some(fromUnix(entryData["expiry"].getInt()))
        else:
          none(Time)
        
        let entry = CacheEntry[V](
          value: value,
          expiry: expiry,
          accessCount: entryData["accessCount"].getInt(),
          lastAccess: getTime()
        )
        
        cache.data[key] = entry
        inc cache.currentSize

# Pattern-based invalidation
proc invalidatePattern*[K, V](cache: Cache[K, V], pattern: string) =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  var keysToDelete: seq[K] = @[]
  
  for key in cache.data.keys:
    let keyStr = $key
    if keyStr.contains(pattern.replace("*", "")):  # Simple contains check
      keysToDelete.add(key)
  
  for key in keysToDelete:
    cache.data.del(key)
    dec cache.currentSize

# Warmup cache
proc warmup*[K, V](cache: Cache[K, V], data: Table[K, V]) =
  for key, value in data:
    cache.put(key, value)

# Create distributed cache (simplified)
proc newDistributedCache*[K, V](
  namespace: string,
  nodes: seq[string]
): DistributedCache[K, V] =
  result = DistributedCache[K, V](
    namespace: namespace,
    nodes: nodes,
    localCache: newCache[K, V]()
  )

# Distributed put (simplified)
proc put*[K, V](cache: DistributedCache[K, V], key: K, value: V): Future[void] {.async.} =
  # Put in local cache
  cache.localCache.put(key, value)
  # In real implementation, would sync with other nodes

# Distributed get (simplified)
proc get*[K, V](cache: DistributedCache[K, V], key: K): Future[Option[V]] {.async.} =
  # Try local first
  let local = cache.localCache.get(key)
  if local.isSome:
    return local
  # In real implementation, would check other nodes
  return none(V)

# Distributed invalidate all
proc invalidateAll*[K, V](cache: DistributedCache[K, V]): Future[void] {.async.} =
  cache.localCache.invalidateAll()
  # In real implementation, would broadcast to other nodes

# Create group cache
proc newGroupCache*[K, V](): GroupCache[K, V] =
  result = GroupCache[K, V]()
  result.data = initTable[K, CacheEntry[V]]()
  result.groups = initTable[string, seq[K]]()
  result.keyGroups = initTable[K, seq[string]]()
  result.maxSize = 1000
  result.evictionPolicy = LRU
  initLock(result.lock)

# Put with groups
proc put*[K, V](cache: GroupCache[K, V], key: K, value: V, groups: seq[string] = @[]) =
  # Call parent put
  Cache[K, V](cache).put(key, value)
  
  acquire(cache.lock)
  defer: release(cache.lock)
  
  # Update group mappings
  cache.keyGroups[key] = groups
  for group in groups:
    if group notin cache.groups:
      cache.groups[group] = @[]
    cache.groups[group].add(key)

# Get from group cache (just use parent)
proc get*[K, V](cache: GroupCache[K, V], key: K): Option[V] =
  return Cache[K, V](cache).get(key)

# Invalidate by group
proc invalidateGroup*[K, V](cache: GroupCache[K, V], group: string) =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  if group in cache.groups:
    for key in cache.groups[group]:
      cache.data.del(key)
      dec cache.currentSize
      
      # Remove from other groups
      if key in cache.keyGroups:
        for g in cache.keyGroups[key]:
          if g != group and g in cache.groups:
            cache.groups[g].keepItIf(it != key)
        cache.keyGroups.del(key)
    
    cache.groups.del(group)

# Create memory-aware cache
proc newMemoryAwareCache*[K, V](maxMemoryMB: int): MemoryAwareCache[K, V] =
  result = MemoryAwareCache[K, V](
    maxMemoryBytes: maxMemoryMB * 1024 * 1024
  )
  result.data = initTable[K, CacheEntry[V]]()
  result.maxSize = int.high  # No fixed item limit
  result.evictionPolicy = LRU
  result.enableStats = true
  initLock(result.lock)

# Memory stats
proc getMemoryStats*[K, V](cache: MemoryAwareCache[K, V]): MemoryStats =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  result.usedMemoryMB = float(cache.currentMemoryBytes) / 1024.0 / 1024.0
  result.maxMemoryMB = float(cache.maxMemoryBytes) / 1024.0 / 1024.0
  result.evictionCount = int(cache.stats.evictions)

# Memory-aware put
proc put*[K, V](cache: MemoryAwareCache[K, V], key: K, value: V, ttl: Duration = initDuration(0)) =
  acquire(cache.lock)
  defer: release(cache.lock)
  
  let size = sizeof(value)
  
  # Evict until we have space
  while cache.currentMemoryBytes + size > cache.maxMemoryBytes and cache.data.len > 0:
    Cache[K, V](cache).evict()
    
    # Recalculate memory usage
    cache.currentMemoryBytes = 0
    for entry in cache.data.values:
      cache.currentMemoryBytes += entry.size
  
  # Now add the new entry
  let effectiveTTL = if ttl.inSeconds > 0: ttl else: cache.defaultTTL
  let expiry = if effectiveTTL.inSeconds > 0:
    some(getTime() + effectiveTTL)
  else:
    none(Time)
  
  let entry = CacheEntry[V](
    value: value,
    expiry: expiry,
    accessCount: 1,
    lastAccess: getTime(),
    size: size
  )
  
  cache.data[key] = entry
  cache.currentMemoryBytes += size
  inc cache.currentSize
  
  if cache.enableStats:
    inc cache.stats.puts

# Integration with nim-lang-core cache infrastructure
type
  NimCoreCache*[K, V] = ref object of Cache[K, V]
    coreCache: nim_core_cache.AstCache
    
proc newNimCoreCache*[K, V](maxEntries: int = 1000): NimCoreCache[K, V] =
  ## Create a cache that leverages nim-lang-core's AST cache
  result = NimCoreCache[K, V]()
  
  # Create config for nim-lang-core cache
  let config = nim_core_common.Config(
    cacheEnabled: true,
    cacheDir: getTempDir() / "nim-libaspects-cache",
    maxCacheEntries: maxEntries,
    maxCacheAgeMinutes: 60
  )
  result.coreCache = nim_core_cache.newAstCache(config)
  result.data = initTable[K, CacheEntry[V]]()
  result.maxSize = maxEntries
  result.evictionPolicy = LRU
  result.enableStats = true
  initLock(result.lock)

when compiles(nim_core_cache.AstNode):
  proc putAstNode*[K, V](cache: NimCoreCache[K, V], key: K, astNode: ast_analyzer.AstNode) =
    ## Store AST node using nim-lang-core's optimized cache
    acquire(cache.lock)
    defer: release(cache.lock)
    
    # Store in nim-lang-core cache for AST-specific optimizations
    cache.coreCache.put($key, astNode)

  proc getAstNode*[K, V](cache: NimCoreCache[K, V], key: K): Option[ast_analyzer.AstNode] =
    ## Retrieve AST node using nim-lang-core's cache
    acquire(cache.lock)
    defer: release(cache.lock)
    
    # Try nim-lang-core cache
    let astResult = cache.coreCache.get($key)
    if astResult.isSome:
      if cache.enableStats:
        inc cache.stats.hits
      return astResult
    
    if cache.enableStats:
      inc cache.stats.misses
    return none(ast_analyzer.AstNode)

proc analyzeCache*[K, V](cache: Cache[K, V]): seq[string] =
  ## Analyze cache usage patterns
  result = @[]
  
  let stats = cache.stats
  if stats.hits + stats.misses > 0:
    let hitRate = float(stats.hits) / float(stats.hits + stats.misses) * 100
    result.add(fmt"Hit rate: {hitRate:.2f}%")
    
    if hitRate < 50:
      result.add("Low hit rate - consider increasing cache size or reviewing access patterns")
    
    if stats.evictions > stats.puts:
      result.add("High eviction rate - cache may be too small")
  
  # Analyze memory usage for memory-aware caches
  if cache of MemoryAwareCache[K, V]:
    let memCache = MemoryAwareCache[K, V](cache)
    let memStats = memCache.getMemoryStats()
    if memStats.usedMemoryMB / memStats.maxMemoryMB > 0.9:
      result.add("Cache is near memory limit - consider increasing limit")

# Export enhanced functionality
export nim_core_cache
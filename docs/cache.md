# Cache Module

The cache module provides comprehensive caching capabilities including TTL management, eviction policies, distributed caching, and statistics. When integrated with nim-lang-core, it offers optimized AST caching and usage analysis.

## Features

- Multiple eviction policies (LRU, LFU, FIFO)
- TTL (Time To Live) support
- Async cache operations
- Multi-level cache hierarchies
- Group-based invalidation
- Memory-aware caching
- Cache statistics and monitoring
- **Optimized AST caching** (with nim-lang-core)
- **Cache usage analysis** (with nim-lang-core)

## Basic Usage

```nim
import nim_libaspects/cache

# Create a simple cache
let cache = newCache[string, string](
  maxSize = 1000,
  defaultTTL = initDuration(minutes = 10),
  evictionPolicy = LRU
)

# Store and retrieve values
cache.put("key1", "value1")
let value = cache.get("key1")
if value.isSome:
  echo value.get()
```

## Cache Types

### Basic Cache

```nim
let cache = newCache[string, JsonNode](
  maxSize = 1000,
  evictionPolicy = LRU,
  enableStats = true
)
```

### Loading Cache

Automatically loads missing values:

```nim
let loader = proc(key: string): JsonNode =
  # Load from database or compute
  return parseJson("""{"data": "loaded"}""")

let cache = newLoadingCache[string, JsonNode](
  maxSize = 1000,
  loader = loader
)
```

### Async Cache

For asynchronous operations:

```nim
let asyncCache = newAsyncCache[string, string](cache)

# Async operations
await asyncCache.putAsync("key", "value")
let value = await asyncCache.getAsync("key")
```

### Multi-Level Cache

Chain multiple cache levels:

```nim
let l1Cache = newCache[string, string](maxSize = 100)  # Fast, small
let l2Cache = newCache[string, string](maxSize = 1000) # Slower, larger

let multiCache = newMultiLevelCache[string, string](@[l1Cache, l2Cache])
```

### Group Cache

Invalidate groups of related entries:

```nim
let groupCache = newGroupCache[string, string]()

# Put with groups
groupCache.put("user:1", "John", @["users", "active"])
groupCache.put("user:2", "Jane", @["users", "active"])
groupCache.put("user:3", "Bob", @["users", "inactive"])

# Invalidate all active users
groupCache.invalidateGroup("active")
```

### Memory-Aware Cache

Limits cache by memory usage:

```nim
let memCache = newMemoryAwareCache[string, seq[byte]](
  maxMemoryMB = 100  # 100MB limit
)

# Automatically evicts entries when memory limit is reached
```

## Enhanced Features with nim-lang-core

### NimCoreCache

Create a cache that leverages nim-lang-core's optimized AST cache:

```nim
let nimCache = newNimCoreCache[string, string](maxEntries = 1000)

# Uses nim-lang-core's backend for better performance
# Especially optimized for AST and code-related data
```

### AST Node Caching

Store and retrieve AST nodes efficiently:

```nim
let cache = newNimCoreCache[string, string]()

# Store AST nodes (when using with nim-lang-core AST types)
cache.putAstNode("module.nim", astNode)

# Retrieve AST nodes
let node = cache.getAstNode("module.nim")
if node.isSome:
  # Use the cached AST
  discard
```

### Cache Usage Analysis

Analyze cache usage patterns with AI:

```nim
let analysis = cache.analyzeCache()
for insight in analysis:
  echo "Cache insight: ", insight
```

Common insights:
- Low hit rate warnings
- High eviction rate alerts
- Memory usage recommendations
- Cache size optimization suggestions

## Eviction Policies

### LRU (Least Recently Used)

```nim
let lruCache = newCache[string, string](
  maxSize = 100,
  evictionPolicy = LRU
)
```

### LFU (Least Frequently Used)

```nim
let lfuCache = newCache[string, string](
  maxSize = 100,
  evictionPolicy = LFU
)
```

### FIFO (First In First Out)

```nim
let fifoCache = newCache[string, string](
  maxSize = 100,
  evictionPolicy = FIFO
)
```

## TTL Management

Set TTL for individual entries:

```nim
# Global default TTL
let cache = newCache[string, string](
  defaultTTL = initDuration(hours = 1)
)

# Per-entry TTL
cache.put("short-lived", "data", ttl = initDuration(minutes = 5))
cache.put("long-lived", "data", ttl = initDuration(days = 1))
```

## Cache Statistics

Monitor cache performance:

```nim
let stats = cache.getStats()
echo "Hits: ", stats.hits
echo "Misses: ", stats.misses
echo "Hit rate: ", stats.hitRate, "%"
echo "Evictions: ", stats.evictions
```

## Event Handling

React to cache events:

```nim
cache.onEvent = proc(event: CacheEvent) =
  case event.eventType
  of Put:
    echo "Added: ", event.key
  of Hit:
    echo "Cache hit: ", event.key
  of Miss:
    echo "Cache miss: ", event.key
  of Evict:
    echo "Evicted: ", event.key
  of Expire:
    echo "Expired: ", event.key
```

## Distributed Cache

For distributed systems:

```nim
let distributedCache = newDistributedCache[string, string](
  namespace = "myapp",
  nodes = @["node1:6379", "node2:6379"],
  localCache = newCache[string, string](maxSize = 100)
)
```

## Best Practices

1. **Choose appropriate eviction policy**: LRU for general use, LFU for hot data
2. **Set reasonable TTLs**: Balance freshness with performance
3. **Monitor hit rates**: Aim for >80% hit rate
4. **Use memory limits**: Prevent unbounded growth
5. **Group related data**: For efficient invalidation
6. **Analyze usage**: Use AI insights to optimize

## Performance Tips

1. **Pre-warm cache**: Load frequently accessed data on startup
2. **Batch operations**: Use multi-get/put when possible
3. **Appropriate key design**: Include version in keys for easy invalidation
4. **Local caching**: Use multi-level cache for distributed systems
5. **Regular analysis**: Monitor and adjust based on usage patterns

## API Reference

See the main README for complete API documentation.
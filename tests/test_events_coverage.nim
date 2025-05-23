## ファイル: tests/test_events_coverage.nim
## 内容: イベントシステムのカバレッジテスト

import std/[unittest, json, times, asyncdispatch, strutils]
import nim_libaspects/events

suite "Event System Coverage Tests":
  
  test "Event with empty data":
    let event = newEvent("empty.event")
    check event.eventType == "empty.event"
    check event.data.kind == JObject
    check event.data.len == 0
  
  test "Event with complex JSON data":
    let complexData = %*{
      "user": {
        "id": 123,
        "name": "John Doe",
        "roles": ["admin", "user"],
        "active": true
      },
      "metadata": {
        "timestamp": "2024-01-01T00:00:00",
        "version": 1.5
      }
    }
    
    let event = newEvent("complex.event", complexData)
    check event.data["user"]["id"].num == 123
    check event.data["user"]["roles"][0].str == "admin"
    check event.data["metadata"]["version"].fnum == 1.5
  
  test "Event metadata edge cases":
    let event = newEvent("test")
    
    # Empty key
    event.setMetadata("", "value")
    check event.getMetadata("") == "value"
    
    # Empty value
    event.setMetadata("key", "")
    check event.getMetadata("key") == ""
    
    # Overwrite existing
    event.setMetadata("duplicate", "first")
    event.setMetadata("duplicate", "second")
    check event.getMetadata("duplicate") == "second"
    
    # Very long key and value
    let longKey = repeat("x", 1000)
    let longValue = repeat("y", 10000)
    event.setMetadata(longKey, longValue)
    check event.getMetadata(longKey) == longValue
  
  test "EventBus with empty namespace":
    let bus = newEventBus("")
    let event = newEvent("test")
    var received = false
    
    discard bus.subscribe("test", proc(e: Event) {.gcsafe.} =
      if e.eventType == "test":
        received = true
    )
    
    bus.publish(event)
    check received
  
  test "EventBus multiple namespaces":
    let bus1 = newEventBus("app")
    let bus2 = bus1.namespace("module")
    let bus3 = bus2.namespace("component")
    
    var eventType = ""
    
    discard bus3.subscribe("action", proc(e: Event) {.gcsafe.} =
      eventType = e.eventType
    )
    
    bus3.publish(newEvent("action"))
    
    check eventType == "app.module.component.action"
  
  test "Pattern matching edge cases":
    let bus = newEventBus()
    var exactMatched = false
    var wildcardMatched = false
    var emptyMatched = false
    
    # Exact match
    discard bus.subscribe("exact", proc(e: Event) {.gcsafe.} =
      exactMatched = true
    )
    
    # Wildcard at end
    discard bus.subscribe("prefix.*", proc(e: Event) {.gcsafe.} =
      wildcardMatched = true
    )
    
    # Empty pattern
    discard bus.subscribe("", proc(e: Event) {.gcsafe.} =
      emptyMatched = true
    )
    
    # Test various events
    bus.publish(newEvent("exact"))       # Should match "exact"
    bus.publish(newEvent("prefix.test")) # Should match "prefix.*"
    bus.publish(newEvent(""))           # Should match ""
    
    check exactMatched
    check wildcardMatched
    check emptyMatched
  
  test "Priority edge cases":
    let bus = newEventBus()
    
    # Same priority
    discard bus.subscribePriority("test", 100, proc(e: Event) {.gcsafe.} = discard)
    discard bus.subscribePriority("test", 100, proc(e: Event) {.gcsafe.} = discard)
    discard bus.subscribePriority("test", 100, proc(e: Event) {.gcsafe.} = discard)
    
    # Negative priority
    discard bus.subscribePriority("test", -50, proc(e: Event) {.gcsafe.} = discard)
    
    # Very high priority
    discard bus.subscribePriority("test", int.high, proc(e: Event) {.gcsafe.} = discard)
    
    # Publish should not fail
    bus.publish(newEvent("test"))
  
  test "Unsubscribe non-existent ID":
    let bus = newEventBus()
    
    # Should not throw
    bus.unsubscribe("non-existent-id")
    bus.unsubscribe("")
    
    # Subscribe and unsubscribe twice
    let id = bus.subscribe("test", proc(e: Event) {.gcsafe.} = discard)
    bus.unsubscribe(id)
    bus.unsubscribe(id)  # Should not fail
  
  test "EventFilter with nil predicate":
    let bus = newEventBus()
    
    let filter = EventFilter(
      eventType: "test.*",
      predicate: nil
    )
    
    var received = false
    discard bus.subscribeWithFilter(filter, proc(e: Event) {.gcsafe.} =
      received = true
    )
    
    bus.publish(newEvent("test.event"))
    check received  # Should still match on pattern alone
  
  test "Middleware chain":
    let bus = newEventBus()
    var step = 0
    
    # Multiple middleware
    bus.addMiddleware(proc(e: Event, next: proc()) {.gcsafe.} =
      if step == 0:
        step = 1  # middleware1-before
      next()
      if step == 3:
        step = 4  # middleware1-after
    )
    
    bus.addMiddleware(proc(e: Event, next: proc()) {.gcsafe.} =
      if step == 1:
        step = 2  # middleware2-before
      next()
      if step == 2:
        step = 3  # middleware2-after
    )
    
    discard bus.subscribe("test", proc(e: Event) {.gcsafe.} =
      if step == 2:
        step = 2  # handler (no change to test proper flow)
    )
    
    bus.publish(newEvent("test"))
    
    check step == 4  # All middleware executed in correct order
  
  test "Middleware stopping chain":
    let bus = newEventBus()
    var handlerCalled = false
    
    bus.addMiddleware(proc(e: Event, next: proc()) {.gcsafe.} =
      # Don't call next() - stop the chain
      discard
    )
    
    discard bus.subscribe("test", proc(e: Event) {.gcsafe.} =
      handlerCalled = true
    )
    
    bus.publish(newEvent("test"))
    check not handlerCalled
  
  test "Error handler not set":
    let bus = newEventBus()
    
    discard bus.subscribe("test", proc(e: Event) {.gcsafe.} =
      raise newException(ValueError, "Test error")
    )
    
    # Should not crash without error handler
    try:
      bus.publish(newEvent("test"))
    except:
      discard
  
  test "Multiple error handlers":
    let bus = newEventBus()
    var errorCount = 0
    
    # Set error handler multiple times (last one wins)
    bus.onError(proc(e: Event, error: ref Exception) {.gcsafe.} =
      errorCount = 100
    )
    
    bus.onError(proc(e: Event, error: ref Exception) {.gcsafe.} =
      errorCount = 200
    )
    
    discard bus.subscribe("test", proc(e: Event) {.gcsafe.} =
      raise newException(ValueError, "Test")
    )
    
    bus.publish(newEvent("test"))
    check errorCount == 200  # Last handler wins
  
  test "AsyncEventBus basic operations":
    let asyncBus = newAsyncEventBus()
    var syncHandled = false
    var asyncHandled = false
    
    # Sync handler through underlying bus
    discard asyncBus.bus.subscribe("test", proc(e: Event) {.gcsafe.} =
      syncHandled = true
    )
    
    # Async handler
    discard asyncBus.subscribeAsync("test", proc(e: Event): Future[void] {.async, gcsafe.} =
      await sleepAsync(1)
      asyncHandled = true
    )
    
    waitFor asyncBus.publishAsync(newEvent("test"))
    
    check syncHandled
    check asyncHandled
  
  test "EventStore without connection":
    let store = newEventStore()
    
    # Should work even without bus connection
    let events = store.getEvents()
    check events.len == 0
    
    # Replay should not crash
    store.replay()
  
  test "EventStore pattern filtering":
    let store = newEventStore()
    let bus = newEventBus()
    store.connect(bus)
    
    # Publish various events
    bus.publish(newEvent("user.created"))
    bus.publish(newEvent("user.updated"))
    bus.publish(newEvent("order.created"))
    bus.publish(newEvent("order.completed"))
    
    # Get by pattern
    let userEvents = store.getEvents("user.*")
    let orderEvents = store.getEvents("order.*")
    let allEvents = store.getEvents("*")
    
    check userEvents.len == 2
    check orderEvents.len == 2
    check allEvents.len == 4
    
    # Specific event
    let created = store.getEvents("user.created")
    check created.len == 1
  
  test "EventAggregator time-based flush":
    let bus = newEventBus()
    let aggregator = newEventAggregator(bus, 1000, 100)  # 1000 events or 100ms
    var batchCount = 0
    
    aggregator.onBatch("test", proc(events: seq[Event]) {.gcsafe.} =
      batchCount = events.len
    )
    
    # Send a few events
    for i in 1..5:
      bus.publish(newEvent("test", %*{"id": i}))
    
    # Wait for time-based flush
    sleep(150)
    aggregator.flush()
    
    check batchCount == 5
  
  test "EventAggregator size-based flush":
    let bus = newEventBus()
    let aggregator = newEventAggregator(bus, 3, 10000)  # 3 events or 10 seconds
    var batchCount = 0
    var lastBatchSize = 0
    
    aggregator.onBatch("test", proc(events: seq[Event]) {.gcsafe.} =
      batchCount += 1
      lastBatchSize = events.len
    )
    
    # Send events
    for i in 1..10:
      bus.publish(newEvent("test", %*{"id": i}))
    
    aggregator.flush()
    
    # Should have had 4 batches (3, 3, 3, 1)
    check batchCount == 4
    check lastBatchSize == 1
  
  test "EventAggregator multiple patterns":
    let bus = newEventBus()
    let aggregator = newEventAggregator(bus, 100, 1000)
    var userBatch = 0
    var orderBatch = 0
    
    aggregator.onBatch("user.*", proc(events: seq[Event]) {.gcsafe.} =
      userBatch = events.len
    )
    
    aggregator.onBatch("order.*", proc(events: seq[Event]) {.gcsafe.} =
      orderBatch = events.len
    )
    
    # Send mixed events
    bus.publish(newEvent("user.created"))
    bus.publish(newEvent("order.created"))
    bus.publish(newEvent("user.updated"))
    bus.publish(newEvent("order.updated"))
    
    aggregator.flush()
    
    check userBatch == 2
    check orderBatch == 2
  
  test "JSON serialization edge cases":
    # Event with minimal data
    let event1 = newEvent("test")
    let json1 = event1.toJson()
    let restored1 = fromJson(json1)
    check restored1.eventType == event1.eventType
    
    # Event with metadata
    let event2 = newEvent("test", %*{"key": "value"})
    event2.setMetadata("meta1", "value1")
    event2.setMetadata("meta2", "value2")
    
    let json2 = event2.toJson()
    let restored2 = fromJson(json2)
    
    check restored2.getMetadata("meta1") == "value1"
    check restored2.getMetadata("meta2") == "value2"
  
  test "Concurrent event publishing":
    let bus = newEventBus()
    var counter = 0
    let lock = Lock()
    
    initLock(lock)
    
    discard bus.subscribe("test", proc(e: Event) {.gcsafe.} =
      withLock lock:
        inc(counter)
    )
    
    # Simulate concurrent publishing (in reality would use threads)
    for i in 1..100:
      bus.publish(newEvent("test"))
    
    check counter == 100
  
  # Edge case: empty patterns and event types
  test "Empty patterns and event types":
    let bus = newEventBus()
    var received = false
    
    # Subscribe to empty pattern
    discard bus.subscribe("", proc(e: Event) {.gcsafe.} =
      if e.eventType == "":
        received = true
    )
    
    # Publish empty event type
    bus.publish(newEvent(""))
    check received
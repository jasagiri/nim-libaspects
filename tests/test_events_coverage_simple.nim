## ファイル: tests/test_events_coverage_simple.nim
## 内容: イベントシステムのカバレッジテスト（GC-safe版）

import std/[unittest, json, times, asyncdispatch, strutils]
import nim_libaspects/events

suite "Event System Coverage Tests (GC-Safe)":
  
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
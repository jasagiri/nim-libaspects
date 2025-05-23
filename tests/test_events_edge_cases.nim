## ファイル: tests/test_events_edge_cases.nim
## 内容: イベントシステムのエッジケーステスト

import std/[unittest, json, times, strutils, tables]
import nim_libaspects/events

suite "Event System Edge Cases":
  
  test "Event creation with empty data":
    let event = newEvent("empty.event")
    check event.eventType == "empty.event"
    check event.data.kind == JObject
    check event.data.len == 0
  
  test "Event creation with complex JSON data":
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
    
    # Empty key and value
    event.setMetadata("", "value")
    check event.getMetadata("") == "value"
    
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
  
  test "EventBus empty namespace":
    let bus = newEventBus("")
    # Can't check private field, but creation should work
    discard bus
  
  test "EventBus namespace chaining":
    let bus1 = newEventBus("app")
    let bus2 = bus1.namespace("module")
    let bus3 = bus2.namespace("component")
    
    # Can't check private field directly, but we can verify by publishing an event
    discard bus3
  
  test "EventFilter with nil predicate":
    let filter = EventFilter(
      eventType: "test.*",
      predicate: nil
    )
    
    # Should still be valid
    check filter.eventType == "test.*"
    check filter.predicate == nil
  
  test "EventStore without bus":
    let store = newEventStore()
    
    # Should work even without bus connection
    let emptyEvents = store.getEvents()
    check emptyEvents.len == 0
    
    # Replay should not crash even with no connection
    store.replay()
  
  test "JSON serialization edge cases":
    # Event with minimal data
    let event1 = newEvent("test")
    let json1 = event1.toJson()
    let restored1 = fromJson(json1)
    check restored1.eventType == event1.eventType
    check restored1.id == event1.id
    
    # Event with complex metadata
    let event2 = newEvent("test", %*{"key": "value"})
    event2.setMetadata("meta1", "value1")
    event2.setMetadata("meta2", "value2")
    event2.setMetadata("", "empty-key")
    event2.setMetadata("empty-value", "")
    
    let json2 = event2.toJson()
    let restored2 = fromJson(json2)
    
    check restored2.getMetadata("meta1") == "value1"
    check restored2.getMetadata("meta2") == "value2"
    check restored2.getMetadata("") == "empty-key"
    check restored2.getMetadata("empty-value") == ""
  
  test "Event ID and timestamp":
    let before = getTime()
    let event1 = newEvent("test")
    let event2 = newEvent("test")
    let after = getTime()
    
    # Unique IDs
    check event1.id != event2.id
    
    # Timestamp within bounds
    check event1.timestamp >= before
    check event1.timestamp <= after
    check event2.timestamp >= before
    check event2.timestamp <= after
  
  test "Valid event patterns":
    # These should all be valid patterns
    var patterns = @[
      "",              # Empty pattern
      "*",             # Wildcard only
      "test",          # Simple name
      "test.*",        # With wildcard
      "test.sub.*",    # Nested with wildcard
      "a.b.c.d.e",     # Deep nesting
      repeat("x", 100), # Long pattern
    ]
    
    for pattern in patterns:
      let filter = EventFilter(eventType: pattern)
      check filter.eventType == pattern
  
  test "Event type edge cases":
    var eventTypes = @[
      "",                    # Empty
      " ",                   # Whitespace
      "with space",          # With space
      "with.dot",           # With dot
      "with-dash",          # With dash
      "with_underscore",    # With underscore
      "123numeric",         # Starting with number
      repeat("x", 1000),    # Very long
    ]
    
    for eventType in eventTypes:
      let event = newEvent(eventType)
      check event.eventType == eventType
  
  test "Subscription ID format":
    let bus = newEventBus()
    
    # Subscribe and check ID format
    let id1 = bus.subscribe("test", proc(e: Event) {.gcsafe.} = discard)
    let id2 = bus.subscribe("test", proc(e: Event) {.gcsafe.} = discard)
    
    # IDs should be unique
    check id1 != id2
    
    # IDs should be non-empty
    check id1.len > 0
    check id2.len > 0
  
  test "Unsubscribe edge cases":
    let bus = newEventBus()
    
    # Unsubscribe non-existent ID
    bus.unsubscribe("non-existent")
    bus.unsubscribe("")
    
    # Subscribe and unsubscribe multiple times
    let id = bus.subscribe("test", proc(e: Event) {.gcsafe.} = discard)
    bus.unsubscribe(id)
    bus.unsubscribe(id)  # Should not crash
  
  test "Event creation with nil JSON":
    let event = newEvent("test", newJNull())
    check event.eventType == "test"
    check event.data.kind == JNull
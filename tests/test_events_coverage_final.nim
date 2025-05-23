## ファイル: tests/test_events_coverage_final.nim
## 内容: イベントシステムのカバレッジテスト（完全版）

import std/[unittest, json, times, asyncdispatch, strutils, tables]
import nim_libaspects/events

suite "Event System Coverage Tests":
  
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
  
  test "Event metadata operations":
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
    let state = new(bool)
    state[] = false
    
    proc handler(e: Event) {.gcsafe.} =
      if e.eventType == "test":
        state[] = true
    
    discard bus.subscribe("test", handler)
    
    bus.publish(event)
    check state[]
  
  test "EventBus namespace chaining":
    let bus1 = newEventBus("app")
    let bus2 = bus1.namespace("module")
    let bus3 = bus2.namespace("component")
    
    # Capture the event type using a state object
    type State = ref object
      captured: string
    
    let state = State(captured: "")
    
    proc handler(e: Event) {.gcsafe.} =
      state.captured = e.eventType
    
    discard bus3.subscribe("action", handler)
    
    bus3.publish(newEvent("action"))
    
    check state.captured == "app.module.component.action"
  
  test "Pattern matching":
    let bus = newEventBus()
    
    # Use state objects for each pattern
    type MatchState = ref object
      matched: bool
    
    let exactState = MatchState(matched: false)
    let wildcardState = MatchState(matched: false)
    let emptyState = MatchState(matched: false)
    
    proc exactHandler(e: Event) {.gcsafe.} =
      exactState.matched = true
    
    proc wildcardHandler(e: Event) {.gcsafe.} =
      wildcardState.matched = true
    
    proc emptyHandler(e: Event) {.gcsafe.} =
      emptyState.matched = true
    
    discard bus.subscribe("exact", exactHandler)
    discard bus.subscribe("prefix.*", wildcardHandler)
    discard bus.subscribe("", emptyHandler)
    
    # Test various events
    bus.publish(newEvent("exact"))       # Should match "exact"
    bus.publish(newEvent("prefix.test")) # Should match "prefix.*"
    bus.publish(newEvent(""))           # Should match ""
    
    check exactState.matched
    check wildcardState.matched
    check emptyState.matched
  
  test "EventFilter with nil predicate":
    let bus = newEventBus()
    
    let filter = EventFilter(
      eventType: "test.*",
      predicate: nil
    )
    
    let state = new(bool)
    state[] = false
    
    proc handler(e: Event) {.gcsafe.} =
      state[] = true
    
    discard bus.subscribeWithFilter(filter, handler)
    
    bus.publish(newEvent("test.event"))
    check state[]  # Should still match on pattern alone
  
  test "Error handling without handler":
    let bus = newEventBus()
    
    proc errorHandler(e: Event) {.gcsafe.} =
      raise newException(ValueError, "Test error")
    
    discard bus.subscribe("test", errorHandler)
    
    # Should not crash without error handler
    try:
      bus.publish(newEvent("test"))
    except:
      discard
  
  test "EventStore operations":
    let store = newEventStore()
    
    # Should work even without bus connection
    let emptyEvents = store.getEvents()
    check emptyEvents.len == 0
    
    # Connect to bus and publish events
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
  
  test "JSON serialization":
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
    let state = new(bool)
    state[] = false
    
    # Subscribe to empty pattern
    proc emptyHandler(e: Event) {.gcsafe.} =
      if e.eventType == "":
        state[] = true
    
    discard bus.subscribe("", emptyHandler)
    
    # Publish empty event type
    bus.publish(newEvent(""))
    check state[]
  
  test "Event ID uniqueness":
    let event1 = newEvent("test")
    let event2 = newEvent("test")
    check event1.id != event2.id
  
  test "Event timestamp":
    let before = getTime()
    let event = newEvent("test")
    let after = getTime()
    
    check event.timestamp >= before
    check event.timestamp <= after
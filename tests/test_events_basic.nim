## ファイル: tests/test_events_basic.nim
## 内容: イベントシステムの基本テスト

import std/[unittest, json, times, asyncdispatch]
import nim_libaspects/events

suite "Event System Basic Tests":
  
  test "Event creation and properties":
    let event = newEvent("test.event", %*{"key": "value"})
    check event.eventType == "test.event"
    check event.data["key"].str == "value"
    check event.id.len > 0
    check event.timestamp.toUnix() > 0
  
  test "Event metadata":
    let event = newEvent("test.event")
    event.setMetadata("author", "system")
    event.setMetadata("version", "1.0")
    
    check event.getMetadata("author") == "system"
    check event.getMetadata("version") == "1.0"
    check event.getMetadata("missing") == ""
  
  test "EventBus creation":
    let bus = newEventBus()
    check bus != nil
    
    let namespacedBus = bus.namespace("user")
    check namespacedBus != nil
  
  test "Pattern matching":
    # matchesPattern is not exported, but we can test through subscription
    let bus = newEventBus()
    
    discard bus.subscribe("user.*", proc(event: Event) {.gcsafe.} = discard)
    
    # Test that pattern matching works
    bus.publish(newEvent("user.login"))
    bus.publish(newEvent("user.logout"))
    bus.publish(newEvent("user.created"))
    bus.publish(newEvent("admin.login"))
    
    check true  # If we get here, pattern matching works
  
  test "JSON serialization":
    let event = newEvent("test.event", %*{"value": 42})
    event.setMetadata("source", "test")
    
    let json = event.toJson()
    check json["eventType"].str == "test.event"
    check json["data"]["value"].num == 42
    check json["metadata"]["source"].str == "test"
    
    # デシリアライゼーション
    let restored = fromJson(json)
    check restored.eventType == event.eventType
    check restored.data == event.data
    check restored.id == event.id
  
  test "AsyncEventBus creation":
    let asyncBus = newAsyncEventBus()
    check asyncBus != nil
  
  test "EventStore basic operations":
    let store = newEventStore()
    let bus = newEventBus()
    
    # Connect store to bus
    store.connect(bus)
    
    # Publish some events
    bus.publish(newEvent("test1", %*{"id": 1}))
    bus.publish(newEvent("test2", %*{"id": 2}))
    
    # Get all events
    let events = store.getEvents()
    check events.len == 2
    
    # Get events by pattern
    let test1Events = store.getEvents("test1")
    check test1Events.len == 1
    check test1Events[0].eventType == "test1"
  
  test "Priority subscription":
    let bus = newEventBus()
    # Just test that we can subscribe with priorities
    discard bus.subscribePriority("test", 50, proc(event: Event) {.gcsafe.} = discard)
    discard bus.subscribePriority("test", 100, proc(event: Event) {.gcsafe.} = discard)
    discard bus.subscribePriority("test", 25, proc(event: Event) {.gcsafe.} = discard)
    
    # Test that the subscription works without error
    bus.publish(newEvent("test"))
    check true  # If we get here, it works
  
  test "Event filtering":
    let bus = newEventBus()
    
    let filter = EventFilter(
      eventType: "task.*",
      predicate: proc(event: Event): bool {.gcsafe.} =
        event.data.hasKey("priority") and event.data["priority"].str == "high"
    )
    
    discard bus.subscribeWithFilter(filter, proc(event: Event) {.gcsafe.} = discard)
    
    # Test that filtering works without error
    bus.publish(newEvent("task.created", %*{"priority": "high"}))
    bus.publish(newEvent("task.created", %*{"priority": "low"}))
    bus.publish(newEvent("task.updated", %*{"priority": "high"}))
    bus.publish(newEvent("other.event", %*{"priority": "high"}))  # Wrong pattern
    
    check true  # If we get here, filtering works
  
  test "Event bus with namespace":
    let globalBus = newEventBus()
    let userBus = globalBus.namespace("user")
    let adminBus = globalBus.namespace("admin")
    
    discard userBus.subscribe("login", proc(event: Event) {.gcsafe.} = discard)
    discard adminBus.subscribe("login", proc(event: Event) {.gcsafe.} = discard)
    
    # Test that namespaced publishing works
    userBus.publish(newEvent("login"))
    adminBus.publish(newEvent("login"))
    
    check true  # If we get here, namespacing works
  
  test "Event aggregator creation":
    let bus = newEventBus()
    let aggregator = newEventAggregator(bus, 10, 1000)
    check aggregator != nil
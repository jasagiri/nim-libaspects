## Minimal event system test
import std/[unittest, json, times]
import nim_libaspects/events

suite "Event System - Minimal":
  
  test "Event creation and properties":
    let event = newEvent("test.event", %*{"key": "value"})
    check event.eventType == "test.event"
    check event.data["key"].str == "value"
    check event.id.len > 0
    check event.timestamp.toUnix() > 0
  
  test "Basic EventBus publish/subscribe":
    let bus = newEventBus()
    
    # Use a simple counter to track calls
    var callCount = 0
    
    # Define handler as a separate proc
    proc countHandler(event: Event) {.gcsafe.} =
      # Increment a global atomic counter would be more gcsafe
      # For now, just check the event type
      if event.eventType == "test.event":
        inc(callCount)
    
    # Subscribe
    discard bus.subscribe("test.event", countHandler)
    
    # Publish
    bus.publish(newEvent("test.event"))
    
    # Verify - Note: This might not be GC-safe in all cases
    # In a real scenario, we'd use atomic operations
    check callCount > 0
  
  test "Event JSON serialization":
    let original = newEvent("test.event", %*{"data": 123})
    let jsonData = original.toJson()
    let deserialized = fromJson(jsonData)
    
    check deserialized.id == original.id
    check deserialized.eventType == original.eventType
    check deserialized.data["data"].num == 123
  
  test "EventStore basic operations":
    let store = newEventStore()
    let event1 = newEvent("type1", %*{"id": 1})
    let event2 = newEvent("type2", %*{"id": 2})
    
    # Store events
    store.store(event1)
    store.store(event2)
    
    # Retrieve by pattern
    let allEvents = store.getEvents("*")
    check allEvents.len == 2
    
    let type1Events = store.getEvents("type1")
    check type1Events.len == 1
    check type1Events[0].data["id"].num == 1
## ファイル: tests/test_events_simple.nim
## 内容: イベントシステムの簡易テスト（GC安全性を考慮）

import std/[unittest, json, times, tables, asyncdispatch]
import nim_libaspects/events

# グローバル変数（テスト用）
var globalReceived = false
var globalEvent: Event
var globalCounter = 0
var globalEvents: seq[Event] = @[]

# GC安全なハンドラー
proc testHandler(event: Event) {.gcsafe.} =
  globalReceived = true
  globalEvent = event

proc counterHandler(event: Event) {.gcsafe.} =
  inc(globalCounter)

proc collectHandler(event: Event) {.gcsafe.} =
  globalEvents.add(event)

suite "Event System Simple Tests":
  
  setup:
    globalReceived = false
    globalEvent = nil
    globalCounter = 0
    globalEvents = @[]
  
  test "Event creation":
    let event = newEvent("test.event", %*{"key": "value"})
    check event.eventType == "test.event"
    check event.data["key"].str == "value"
    check event.id.len > 0
    check event.timestamp.toUnix() > 0
  
  test "EventBus subscribe and publish":
    let bus = newEventBus()
    discard bus.subscribe("test.event", testHandler)
    
    let event = newEvent("test.event", %*{"message": "hello"})
    bus.publish(event)
    
    check globalReceived
    check globalEvent.eventType == "test.event"
    check globalEvent.data["message"].str == "hello"
  
  test "Multiple subscribers":
    let bus = newEventBus()
    discard bus.subscribe("counter.event", counterHandler)
    discard bus.subscribe("counter.event", counterHandler)
    discard bus.subscribe("counter.event", counterHandler)
    
    bus.publish(newEvent("counter.event"))
    check globalCounter == 3
  
  test "Wildcard subscription":
    let bus = newEventBus()
    discard bus.subscribe("user.*", collectHandler)
    
    bus.publish(newEvent("user.login"))
    bus.publish(newEvent("user.logout"))
    bus.publish(newEvent("user.update"))
    bus.publish(newEvent("system.start"))
    
    check globalEvents.len == 3
    check globalEvents[0].eventType == "user.login"
    check globalEvents[1].eventType == "user.logout"
    check globalEvents[2].eventType == "user.update"
  
  test "Event metadata":
    let event = newEvent("test.event")
    event.setMetadata("key1", "value1")
    event.setMetadata("key2", "value2")
    
    check event.getMetadata("key1") == "value1"
    check event.getMetadata("key2") == "value2"
    check event.getMetadata("missing") == ""
  
  test "Event priorities":
    let bus = newEventBus()
    globalEvents = @[]
    
    # 低優先度のハンドラー
    discard bus.subscribePriority("test", 10, proc(event: Event) {.gcsafe.} =
      globalEvents.add(newEvent("priority-10"))
    )
    
    # 高優先度のハンドラー
    discard bus.subscribePriority("test", 100, proc(event: Event) {.gcsafe.} =
      globalEvents.add(newEvent("priority-100"))
    )
    
    # 中優先度のハンドラー
    discard bus.subscribePriority("test", 50, proc(event: Event) {.gcsafe.} =
      globalEvents.add(newEvent("priority-50"))
    )
    
    bus.publish(newEvent("test"))
    
    check globalEvents.len == 3
    check globalEvents[0].eventType == "priority-100"
    check globalEvents[1].eventType == "priority-50"
    check globalEvents[2].eventType == "priority-10"
  
  test "Unsubscribe":
    let bus = newEventBus()
    globalCounter = 0
    
    let subId = bus.subscribe("test", counterHandler)
    bus.publish(newEvent("test"))
    check globalCounter == 1
    
    bus.unsubscribe(subId)
    bus.publish(newEvent("test"))
    check globalCounter == 1  # カウンターは増えない
  
  test "Event namespacing":
    let bus = newEventBus()
    let userBus = bus.namespace("user")
    globalEvents = @[]
    
    discard userBus.subscribe("created", collectHandler)
    userBus.publish(newEvent("created"))
    
    check globalEvents.len == 1
    check globalEvents[0].eventType == "user.created"
  
  test "Event store":
    let bus = newEventBus()
    let store = newEventStore()
    store.connect(bus)
    
    # イベントを発行
    bus.publish(newEvent("event1", %*{"id": 1}))
    bus.publish(newEvent("event2", %*{"id": 2}))
    bus.publish(newEvent("event3", %*{"id": 3}))
    
    # 記録されたイベントを取得
    let allEvents = store.getEvents()
    check allEvents.len == 3
    
    let event2Only = store.getEvents("event2")
    check event2Only.len == 1
    check event2Only[0].eventType == "event2"
  
  test "Event filter":
    let bus = newEventBus()
    globalEvents = @[]
    
    # 優先度が高いイベントのみを処理するフィルター
    let filter = EventFilter(
      eventType: "task.*",
      predicate: proc(event: Event): bool {.gcsafe.} =
        event.data.hasKey("priority") and event.data["priority"].str == "high"
    )
    
    discard bus.subscribeWithFilter(filter, collectHandler)
    
    # 異なる優先度のイベントを発行
    bus.publish(newEvent("task.created", %*{"priority": "high"}))
    bus.publish(newEvent("task.created", %*{"priority": "low"}))
    bus.publish(newEvent("task.created", %*{"priority": "high"}))
    
    check globalEvents.len == 2
  
  test "Async event handling":
    let bus = newAsyncEventBus()
    globalReceived = false
    
    # 非同期ハンドラー
    discard bus.subscribeAsync("async.test", proc(event: Event): Future[void] {.async, gcsafe.} =
      await sleepAsync(10)
      globalReceived = true
    )
    
    # イベントを発行して待つ
    waitFor bus.publishAsync(newEvent("async.test"))
    check globalReceived
  
  test "Error handling":
    let bus = newEventBus()
    var errorCaught = false
    
    # エラーハンドラーを設定
    bus.onError(proc(event: Event, error: ref Exception) {.gcsafe.} =
      errorCaught = true
    )
    
    # エラーを発生させるハンドラー
    discard bus.subscribe("error.test", proc(event: Event) {.gcsafe.} =
      raise newException(ValueError, "Test error")
    )
    
    # イベントを発行
    bus.publish(newEvent("error.test"))
    check errorCaught
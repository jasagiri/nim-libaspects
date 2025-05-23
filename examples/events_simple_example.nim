## ファイル: examples/events_simple_example.nim
## 内容: イベントシステムのシンプルな使用例

import nim_libaspects/events
import std/[json, times, strformat]

# メインプログラム
proc main() =
  echo "=== Event System Simple Example ==="
  echo ""
  
  # イベントバスの作成
  let bus = newEventBus("example")
  
  # エラーハンドラーの設定
  proc errorHandler(e: Event, error: ref Exception) {.gcsafe.} =
    echo fmt"[ERROR] Event: {e.eventType}, Error: {error.msg}"
  
  bus.onError(errorHandler)
  
  # ユーザーイベントのハンドラー
  proc userCreatedHandler(e: Event) {.gcsafe.} =
    echo fmt"""New user created: {e.data["name"].str} (ID: {e.data["id"].num})"""
  
  proc userUpdatedHandler(e: Event) {.gcsafe.} =
    echo fmt"""User updated: ID {e.data["id"].num}"""
    if e.data.hasKey("name"):
      echo fmt"""  New name: {e.data["name"].str}"""
  
  # イベントの購読
  discard bus.subscribe("user.created", userCreatedHandler)
  discard bus.subscribe("user.updated", userUpdatedHandler)
  
  # 優先度付きハンドラー
  proc criticalHandler(e: Event) {.gcsafe.} =
    echo fmt"""[CRITICAL] {e.eventType}: {e.data["message"].str}"""
  
  discard bus.subscribePriority("critical.*", 100, criticalHandler)
  
  # パターンマッチング
  proc allEventsHandler(e: Event) {.gcsafe.} =
    echo fmt"[ALL] Event: {e.eventType}"
  
  discard bus.subscribe("*", allEventsHandler)
  
  # イベントフィルター
  let orderFilter = EventFilter(
    eventType: "order.*",
    predicate: proc(e: Event): bool =
      e.data.hasKey("amount") and e.data["amount"].num > 100
  )
  
  proc largeOrderHandler(e: Event) {.gcsafe.} =
    echo fmt"""Large order detected: {e.data["amount"].num}"""
  
  discard bus.subscribeWithFilter(orderFilter, largeOrderHandler)
  
  # イベントストア
  let store = newEventStore()
  store.connect(bus)
  
  # ストアハンドラーを手動で追加
  proc storeAllEvents(e: Event) {.gcsafe.} =
    store.store(e)
  
  discard bus.subscribe("*", storeAllEvents)
  
  echo "--- Publishing Events ---"
  
  # ユーザーイベント
  let userCreatedEvent = newEvent("user.created", %*{
    "id": 1,
    "name": "Alice",
    "email": "alice@example.com"
  })
  bus.publish(userCreatedEvent)
  
  let userUpdatedEvent = newEvent("user.updated", %*{
    "id": 1,
    "name": "Alice Smith"
  })
  bus.publish(userUpdatedEvent)
  
  # 注文イベント
  let order1Event = newEvent("order.created", %*{
    "id": 100,
    "amount": 50.0
  })
  bus.publish(order1Event)
  
  let order2Event = newEvent("order.created", %*{
    "id": 101,
    "amount": 150.0  # This will trigger the large order handler
  })
  bus.publish(order2Event)
  
  # 重要なイベント
  let criticalEvent = newEvent("critical.alert", %*{
    "message": "System overload detected"
  })
  bus.publish(criticalEvent)
  
  echo ""
  echo "--- Event Store ---"
  
  let allEvents = store.getEvents()
  echo fmt"Total events stored: {allEvents.len}"
  
  let userEvents = store.getEvents("example.user.*")
  echo fmt"User events: {userEvents.len}"
  
  let orderEvents = store.getEvents("example.order.*")
  echo fmt"Order events: {orderEvents.len}"
  
  echo ""
  echo "--- Namespaced Events ---"
  
  # ネームスペース付きバス
  let moduleBus = bus.namespace("module1")
  
  proc moduleHandler(e: Event) {.gcsafe.} =
    echo fmt"Module event: {e.eventType}"
  
  discard moduleBus.subscribe("action", moduleHandler)
  
  # ネームスペース付きイベントの発行
  moduleBus.publish(newEvent("action"))  # Will be "example.module1.action"
  
  echo ""
  echo "--- JSON Serialization ---"
  
  # イベントのシリアライズ
  let testEvent = newEvent("test.serialize", %*{"data": "value"})
  testEvent.setMetadata("version", "1.0")
  testEvent.setMetadata("source", "example")
  
  let jsonStr = testEvent.toJson()
  echo "Serialized: ", jsonStr
  
  let restored = fromJson(jsonStr)
  echo fmt"Restored event type: {restored.eventType}"
  echo fmt"""Restored metadata: version={restored.getMetadata("version")}, source={restored.getMetadata("source")}"""
  
  echo ""
  echo "=== Example Complete ==="

# 実行
main()
## Test suite for events module - GC Safe Version
## イベントシステムのテストスイート（GCセーフ版）

import std/[unittest, json, asyncdispatch, times, sequtils, atomics]
import nim_libaspects/events

suite "Event System - GC Safe":
  
  test "Event creation":
    # Given: イベントの基本データ
    let eventData = %*{"user": "test", "action": "login"}
    
    # When: イベントを作成
    let event = newEvent("user.login", eventData)
    
    # Then: イベントが正しく作成される
    check event.eventType == "user.login"
    check event.data == eventData
    check event.id.len > 0  # 自動生成されるID
    check event.timestamp.toUnix() > 0  # タイムスタンプが設定される
  
  test "EventBus - subscribe and publish":
    # Given: イベントバス
    let bus = newEventBus()
    
    # グローバル変数を使用してテスト
    var globalTestState {.threadvar.}: tuple[received: bool, eventId: string, eventData: JsonNode]
    globalTestState.received = false
    
    # When: イベントをサブスクライブ
    proc testHandler(event: Event) {.gcsafe.} =
      globalTestState.received = true
      globalTestState.eventId = event.id
      globalTestState.eventData = event.data
    
    discard bus.subscribe("test.event", testHandler)
    
    # When: イベントを発行
    let event = newEvent("test.event", %*{"message": "hello"})
    bus.publish(event)
    
    # Then: ハンドラーが呼ばれる
    check globalTestState.received
    check globalTestState.eventId == event.id
    check globalTestState.eventData == event.data
  
  test "EventBus - multiple subscribers":
    # Given: イベントバスと複数のサブスクライバー
    let bus = newEventBus()
    
    # グローバルカウンター
    var globalCounter {.global.}: Atomic[int]
    globalCounter.store(0)
    
    # When: 複数のハンドラーを登録
    proc incrementHandler(event: Event) {.gcsafe.} =
      discard globalCounter.fetchAdd(1)
    
    discard bus.subscribe("counter.increment", incrementHandler)
    discard bus.subscribe("counter.increment", incrementHandler)
    discard bus.subscribe("counter.increment", incrementHandler)
    
    # When: イベントを発行
    bus.publish(newEvent("counter.increment"))
    
    # Then: 全てのハンドラーが呼ばれる
    check globalCounter.load() == 3
  
  test "EventBus - unsubscribe":
    # Given: イベントバスとサブスクリプション
    let bus = newEventBus()
    
    # グローバルカウンター
    var unsubCounter {.global.}: Atomic[int]
    unsubCounter.store(0)
    
    # When: サブスクライブしてIDを取得
    proc unsubHandler(event: Event) {.gcsafe.} =
      discard unsubCounter.fetchAdd(1)
    
    let subId = bus.subscribe("test.event", unsubHandler)
    
    # イベントを発行（受信される）
    bus.publish(newEvent("test.event"))
    check unsubCounter.load() == 1
    
    # When: アンサブスクライブ
    bus.unsubscribe(subId)
    
    # When: 再度イベントを発行
    bus.publish(newEvent("test.event"))
    
    # Then: 受信されない
    check unsubCounter.load() == 1
  
  test "Event store - basic operations":
    # Given: イベントストア
    let store = newEventStore()
    
    # When: イベントを保存
    let event1 = newEvent("test.event", %*{"id": 1})
    let event2 = newEvent("test.event", %*{"id": 2})
    let event3 = newEvent("other.event", %*{"id": 3})
    
    store.store(event1)
    store.store(event2)
    store.store(event3)
    
    # Then: イベントを取得できる
    check store.size() == 3
    check store.get(event1.id).isSome
    check store.get(event1.id).get().id == event1.id
    
    # When: イベントタイプで取得
    let testEvents = store.getByType("test.event")
    check testEvents.len == 2
  
  test "Event serialization":
    # Given: イベント
    let originalEvent = newEvent("test.event", %*{
      "user": "john",
      "age": 30,
      "active": true
    })
    
    # When: JSONにシリアライズ
    let jsonStr = originalEvent.toJson().pretty()
    
    # When: デシリアライズ
    let deserializedEvent = fromJson(parseJson(jsonStr))
    
    # Then: 元のイベントと同じ
    check deserializedEvent.id == originalEvent.id
    check deserializedEvent.eventType == originalEvent.eventType
    check deserializedEvent.data == originalEvent.data
    check deserializedEvent.timestamp == originalEvent.timestamp
  
  test "Event priority handling":
    # Given: 優先度付きイベントバス
    let bus = newEventBus()
    
    # グローバル実行順序記録
    var globalExecutionOrder {.threadvar.}: seq[int]
    globalExecutionOrder = @[]
    
    # When: 異なる優先度でサブスクライブ
    proc priority1Handler(event: Event) {.gcsafe.} =
      {.gcsafe.}:
        globalExecutionOrder.add(1)
    
    proc priority2Handler(event: Event) {.gcsafe.} =
      {.gcsafe.}:
        globalExecutionOrder.add(2)
    
    proc priority3Handler(event: Event) {.gcsafe.} =
      {.gcsafe.}:
        globalExecutionOrder.add(3)
    
    discard bus.subscribePriority("priority.test", 100, priority1Handler)
    discard bus.subscribePriority("priority.test", 50, priority2Handler)
    discard bus.subscribePriority("priority.test", 200, priority3Handler)
    
    # When: イベントを発行
    bus.publish(newEvent("priority.test"))
    
    # Then: 優先度順に実行される（高い順）
    check globalExecutionOrder == @[3, 1, 2]  # 200, 100, 50
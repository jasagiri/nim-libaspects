## Test suite for events module
## イベントシステムのテストスイート

import std/[unittest, json, asyncdispatch, times, sequtils]
import nim_libaspects/events

suite "Event System":
  
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
    var received = false
    var receivedEvent: Event
    
    # When: イベントをサブスクライブ (明示的なハンドラー関数)
    proc handler(event: Event) {.gcsafe.} =
      received = true
      receivedEvent = event
    
    discard bus.subscribe("test.event", handler)
    
    # When: イベントを発行
    let event = newEvent("test.event", %*{"message": "hello"})
    bus.publish(event)
    
    # Then: ハンドラーが呼ばれる
    check received
    check receivedEvent.id == event.id
    check receivedEvent.data == event.data
  
  test "EventBus - multiple subscribers":
    # Given: イベントバスと複数のサブスクライバー
    let bus = newEventBus()
    var count = 0
    
    # When: 複数のハンドラーを登録 (明示的なハンドラー関数)
    proc incrementCounter(event: Event) {.gcsafe.} =
      inc(count)
    
    discard bus.subscribe("counter.increment", incrementCounter)
    discard bus.subscribe("counter.increment", incrementCounter)
    discard bus.subscribe("counter.increment", incrementCounter)
    
    # When: イベントを発行
    bus.publish(newEvent("counter.increment"))
    
    # Then: 全てのハンドラーが呼ばれる
    check count == 3
  
  test "EventBus - wildcard subscription":
    # Given: イベントバスとワイルドカードサブスクリプション
    let bus = newEventBus()
    var events: seq[Event] = @[]
    
    # When: ワイルドカードでサブスクライブ (明示的なハンドラー関数)
    proc collectEvents(event: Event) {.gcsafe.} =
      events.add(event)
    
    discard bus.subscribe("user.*", collectEvents)
    
    # When: 異なるユーザーイベントを発行
    bus.publish(newEvent("user.login", %*{"id": 1}))
    bus.publish(newEvent("user.logout", %*{"id": 2}))
    bus.publish(newEvent("user.update", %*{"id": 3}))
    bus.publish(newEvent("system.start"))  # これは受信しない
    
    # Then: ユーザーイベントのみ受信
    check events.len == 3
    check events[0].eventType == "user.login"
    check events[1].eventType == "user.logout"
    check events[2].eventType == "user.update"
  
  test "EventBus - unsubscribe":
    # Given: イベントバスとサブスクリプション
    let bus = newEventBus()
    var count = 0
    
    # When: サブスクライブしてIDを取得 (明示的なハンドラー関数)
    proc countHandler(event: Event) {.gcsafe.} =
      inc(count)
    
    let subId = bus.subscribe("test.event", countHandler)
    
    # イベントを発行（受信される）
    bus.publish(newEvent("test.event"))
    check count == 1
    
    # When: アンサブスクライブ
    bus.unsubscribe(subId)
    
    # When: 再度イベントを発行
    bus.publish(newEvent("test.event"))
    
    # Then: 受信されない
    check count == 1
  
  test "Async event handling":
    # Given: 非同期イベントバス
    let bus = newAsyncEventBus()
    var processed = false
    
    # When: 非同期ハンドラーを登録 (明示的なハンドラー関数)
    proc asyncHandler(event: Event) {.async.} =
      await sleepAsync(10)  # 非同期処理のシミュレーション
      processed = true
    
    discard bus.subscribeAsync("async.test", asyncHandler)
    
    # When: イベントを発行
    let event = newEvent("async.test")
    waitFor bus.publishAsync(event)
    
    # Then: 非同期処理が完了
    check processed
  
  test "Event filtering":
    # Given: フィルター付きイベントバス
    let bus = newEventBus()
    var highPriorityEvents: seq[Event] = @[]
    
    # When: フィルター条件でサブスクライブ (明示的なハンドラー関数)
    let filter = EventFilter(
      eventType: "task.*",
      predicate: proc(event: Event): bool =
        event.data.hasKey("priority") and event.data["priority"].str == "high"
    )
    
    proc highPriorityHandler(event: Event) {.gcsafe.} =
      highPriorityEvents.add(event)
    
    discard bus.subscribeWithFilter(filter, highPriorityHandler)
    
    # When: 異なる優先度のイベントを発行
    bus.publish(newEvent("task.created", %*{"priority": "high", "id": 1}))
    bus.publish(newEvent("task.created", %*{"priority": "low", "id": 2}))
    bus.publish(newEvent("task.created", %*{"priority": "high", "id": 3}))
    bus.publish(newEvent("user.created", %*{"priority": "high", "id": 4}))  # 違うタイプ
    
    # Then: 高優先度のタスクイベントのみ受信
    check highPriorityEvents.len == 2
    check highPriorityEvents[0].data["id"].num == 1
    check highPriorityEvents[1].data["id"].num == 3
  
  test "Event store - store and retrieve":
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
    
    # When: 時間範囲で取得（全イベント）
    let now = getTime()
    let allEvents = store.getByTimeRange(now - initDuration(hours = 1), now)
    check allEvents.len == 3
  
  test "Event aggregator":
    # Given: イベントアグリゲーター
    let aggregator = newEventAggregator(100, 5)
    
    # When: イベントを追加
    for i in 1..3:
      aggregator.add(newEvent("test.event", %*{"id": i}))
    
    # Then: まだ処理されない（バッチサイズ未満）
    var processed = false
    
    proc batchHandler(events: seq[Event]) {.gcsafe.} =
      processed = true
      check events.len == 3
    
    aggregator.process(batchHandler)
    check not processed
    
    # When: バッチサイズに達する
    for i in 4..5:
      aggregator.add(newEvent("test.event", %*{"id": i}))
    
    # Then: バッチ処理される
    aggregator.process(batchHandler)
    check processed
  
  test "Event priority handling":
    # Given: 優先度付きイベントバス
    let bus = newEventBus()
    var executionOrder: seq[int] = @[]
    
    # When: 異なる優先度でサブスクライブ (明示的なハンドラー関数)
    proc handler1(event: Event) {.gcsafe.} =
      executionOrder.add(1)
    
    proc handler2(event: Event) {.gcsafe.} =
      executionOrder.add(2)
    
    proc handler3(event: Event) {.gcsafe.} =
      executionOrder.add(3)
    
    discard bus.subscribePriority("priority.test", 100, handler1)
    discard bus.subscribePriority("priority.test", 50, handler2)
    discard bus.subscribePriority("priority.test", 200, handler3)
    
    # When: イベントを発行
    bus.publish(newEvent("priority.test"))
    
    # Then: 優先度順に実行される（高い順）
    check executionOrder == @[3, 1, 2]  # 200, 100, 50
  
  test "Event namespace isolation":
    # Given: 異なる名前空間のイベントバス
    let bus = newEventBus()
    var moduleACount = 0
    var moduleBCount = 0
    
    # When: 名前空間付きでサブスクライブ (明示的なハンドラー関数)
    proc moduleAHandler(event: Event) {.gcsafe.} =
      inc(moduleACount)
    
    proc moduleBHandler(event: Event) {.gcsafe.} =
      inc(moduleBCount)
    
    discard bus.subscribeNamespaced("moduleA", "test.event", moduleAHandler)
    discard bus.subscribeNamespaced("moduleB", "test.event", moduleBHandler)
    
    # When: 特定の名前空間にイベントを発行
    bus.publishNamespaced("moduleA", newEvent("test.event"))
    
    # Then: その名前空間のハンドラーのみ呼ばれる
    check moduleACount == 1
    check moduleBCount == 0
  
  test "Event error handling":
    # Given: エラーハンドラー付きイベントバス
    let bus = newEventBus()
    var errorCaught = false
    
    # エラーハンドラーを設定
    bus.setErrorHandler(proc(event: Event, error: ref Exception) {.gcsafe.} =
      errorCaught = true
      check error.msg == "Handler error"
    )
    
    # When: エラーを投げるハンドラーを登録 (明示的なハンドラー関数)
    proc errorHandler(event: Event) {.gcsafe.} =
      raise newException(ValueError, "Handler error")
    
    proc successHandler(event: Event) {.gcsafe.} =
      # このハンドラーは正常に実行される
      check true
    
    discard bus.subscribe("error.test", errorHandler)
    discard bus.subscribe("success.test", successHandler)
    
    # When: イベントを発行
    bus.publish(newEvent("error.test"))
    bus.publish(newEvent("success.test"))
    
    # Then: エラーがキャッチされ、他のハンドラーは影響を受けない
    check errorCaught
  
  test "Event replay from store":
    # Given: イベントストアとバス
    let store = newEventStore()
    let bus = newEventBus()
    var replayedEvents: seq[Event] = @[]
    
    # When: 過去のイベントを保存
    for i in 1..5:
      let event = newEvent("historical.event", %*{"id": i})
      store.store(event)
    
    # When: リプレイハンドラーを登録 (明示的なハンドラー関数)
    proc replayHandler(event: Event) {.gcsafe.} =
      replayedEvents.add(event)
    
    discard bus.subscribe("historical.event", replayHandler)
    
    # When: ストアからイベントをリプレイ
    store.replay(bus, "historical.event")
    
    # Then: 全てのイベントが再生される
    check replayedEvents.len == 5
    for i, event in replayedEvents:
      check event.data["id"].num == i + 1
  
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
  
  test "Performance - high volume events":
    # Given: 高頻度イベント発行のテスト
    let bus = newEventBus()
    var processedCount = 0
    
    # When: シンプルなカウンターハンドラー (明示的なハンドラー関数)
    proc performanceHandler(event: Event) {.gcsafe.} =
      atomicInc(processedCount)
    
    discard bus.subscribe("perf.test", performanceHandler)
    
    # When: 大量のイベントを発行
    let startTime = epochTime()
    for i in 1..10000:
      bus.publish(newEvent("perf.test", %*{"id": i}))
    let endTime = epochTime()
    
    # Then: 全イベントが処理される
    check processedCount == 10000
    let duration = endTime - startTime
    echo &"  Processed 10000 events in {duration:.3f} seconds ({10000/duration:.0f} events/sec)"
  
  test "Advanced pattern matching":
    # Given: 複雑なパターンマッチング
    let bus = newEventBus()
    var matchedEvents: seq[string] = @[]
    
    # When: 複数パターンでサブスクライブ (明示的なハンドラー関数)
    proc complexPatternHandler(event: Event) {.gcsafe.} =
      matchedEvents.add(event.eventType)
    
    discard bus.subscribe("order.*", complexPatternHandler)
    discard bus.subscribePriority("order.*.completed", 100, complexPatternHandler)
    
    # When: 様々なイベントを発行
    bus.publish(newEvent("order.created"))
    bus.publish(newEvent("order.payment.completed"))
    bus.publish(newEvent("order.shipping.completed"))
    bus.publish(newEvent("user.login"))  # マッチしない
    
    # Then: 期待されるイベントがマッチ
    check matchedEvents.len == 5  # order.*で3つ、order.*.completedで2つ
    check "order.created" in matchedEvents
    check "order.payment.completed" in matchedEvents
    check "order.shipping.completed" in matchedEvents
    check "user.login" notin matchedEvents
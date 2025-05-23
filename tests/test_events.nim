## ファイル: tests/test_events.nim
## 内容: イベントシステムのBDD仕様

import std/[unittest, json, tables, strutils, times, asyncdispatch]
import nim_libaspects/events

suite "Event System BDD Specification":
  
  test "Event creation and properties":
    # Given: イベントパラメータ
    let eventType = "user.login"
    let data = %*{"userId": 123, "username": "john", "ip": "192.168.1.1"}
    
    # When: イベントを作成
    let event = newEvent(eventType, data)
    
    # Then: イベントが正しく作成される
    check event.eventType == eventType
    check event.data == data
    check event.id.len > 0  # 自動生成されるID
    check event.timestamp.toUnix() > 0  # タイムスタンプが設定される
  
  test "EventBus - subscribe and publish":
    # Given: イベントバス
    let bus = newEventBus()
    var received = false
    var receivedEvent: Event
    
    # When: イベントをサブスクライブ
    discard bus.subscribe("test.event", proc(event: Event) {.gcsafe.} =
      {.gcsafe.}:
        received = true
        receivedEvent = event
    )
    
    # When: イベントを発行
    let event = newEvent("test.event", %*{"message": "hello"})
    bus.publish(event)
    
    # Then: ハンドラーが呼ばれる
    check received
    check receivedEvent.eventType == "test.event"
    check receivedEvent.data["message"].str == "hello"
  
  test "EventBus - multiple subscribers":
    # Given: イベントバスと複数のサブスクライバー
    let bus = newEventBus()
    var count = 0
    
    # When: 複数のハンドラーを登録
    discard bus.subscribe("counter.increment") do (event: Event):
      inc(count)
    
    discard bus.subscribe("counter.increment") do (event: Event):
      inc(count)
    
    discard bus.subscribe("counter.increment") do (event: Event):
      inc(count)
    
    # When: イベントを発行
    bus.publish(newEvent("counter.increment"))
    
    # Then: 全てのハンドラーが呼ばれる
    check count == 3
  
  test "EventBus - wildcard subscription":
    # Given: イベントバスとワイルドカードサブスクリプション
    let bus = newEventBus()
    var events: seq[Event] = @[]
    
    # When: ワイルドカードでサブスクライブ
    discard bus.subscribe("user.*") do (event: Event):
      events.add(event)
    
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
    
    # When: サブスクライブしてIDを取得
    let subId = bus.subscribe("test.event") do (event: Event):
      inc(count)
    
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
    
    # When: 非同期ハンドラーを登録
    discard bus.subscribeAsync("async.test", proc(event: Event) {.async.} =
      await sleepAsync(10)  # 非同期処理のシミュレーション
      processed = true
    )
    
    # When: イベントを発行
    let event = newEvent("async.test")
    waitFor bus.publishAsync(event)
    
    # Then: 非同期処理が完了
    check processed
  
  test "Event filtering":
    # Given: フィルター付きイベントバス
    let bus = newEventBus()
    var highPriorityEvents: seq[Event] = @[]
    
    # When: フィルター条件でサブスクライブ
    let filter = EventFilter(
      eventType: "task.*",
      predicate: proc(event: Event): bool =
        event.data.hasKey("priority") and event.data["priority"].str == "high"
    )
    
    discard bus.subscribeWithFilter(filter) do (event: Event):
      highPriorityEvents.add(event)
    
    # When: 異なる優先度のイベントを発行
    bus.publish(newEvent("task.created", %*{"priority": "high", "id": 1}))
    bus.publish(newEvent("task.created", %*{"priority": "low", "id": 2}))
    bus.publish(newEvent("task.created", %*{"priority": "high", "id": 3}))
    bus.publish(newEvent("task.created", %*{"id": 4}))  # priority なし
    
    # Then: 高優先度のイベントのみ受信
    check highPriorityEvents.len == 2
    check highPriorityEvents[0].data["id"].num == 1
    check highPriorityEvents[1].data["id"].num == 3
  
  test "Event store - record and replay":
    # Given: イベントストア
    let store = newEventStore()
    let bus = newEventBus()
    
    # イベントバスをストアに接続
    store.connect(bus)
    
    # When: イベントを発行（自動的に記録される）
    bus.publish(newEvent("order.created", %*{"orderId": 1, "amount": 100}))
    bus.publish(newEvent("order.updated", %*{"orderId": 1, "amount": 150}))
    bus.publish(newEvent("order.shipped", %*{"orderId": 1}))
    
    # Then: イベントが記録される
    let events = store.getEvents("order.*")
    check events.len == 3
    
    # When: イベントをリプレイ
    var replayedEvents: seq[Event] = @[]
    discard bus.subscribe("order.*") do (event: Event):
      replayedEvents.add(event)
    
    store.replay("order.*")
    
    # Then: 全イベントが再生される
    check replayedEvents.len == 3
    check replayedEvents[0].eventType == "order.created"
    check replayedEvents[1].eventType == "order.updated"
    check replayedEvents[2].eventType == "order.shipped"
  
  test "Event middleware":
    # Given: ミドルウェア付きイベントバス
    let bus = newEventBus()
    var middlewareProcessed = false
    var handlerProcessed = false
    
    # When: ミドルウェアを追加
    bus.addMiddleware(proc(event: Event, next: proc()) =
      # イベントを変更または検証
      middlewareProcessed = true
      if event.data.hasKey("authorized") and event.data["authorized"].bval:
        next()  # 次のミドルウェアまたはハンドラーへ
    )
    
    # When: ハンドラーを登録
    discard bus.subscribe("secure.action") do (event: Event):
      handlerProcessed = true
    
    # When: 認証されていないイベント
    bus.publish(newEvent("secure.action", %*{"authorized": false}))
    check middlewareProcessed
    check not handlerProcessed
    
    # When: 認証されたイベント
    middlewareProcessed = false
    bus.publish(newEvent("secure.action", %*{"authorized": true}))
    check middlewareProcessed
    check handlerProcessed
  
  test "Event priorities":
    # Given: 優先度付きイベントバス
    let bus = newEventBus()
    var processOrder: seq[int] = @[]
    
    # When: 異なる優先度のハンドラーを登録
    discard bus.subscribePriority("priority.test", 100) do (event: Event):
      processOrder.add(100)
    
    discard bus.subscribePriority("priority.test", 50) do (event: Event):
      processOrder.add(50)
    
    discard bus.subscribePriority("priority.test", 200) do (event: Event):
      processOrder.add(200)
    
    # When: イベントを発行
    bus.publish(newEvent("priority.test"))
    
    # Then: 優先度順に処理される
    check processOrder == @[200, 100, 50]
  
  test "Event metadata":
    # Given: メタデータ付きイベント
    let event = newEvent("user.action", %*{"action": "click"})
    
    # When: メタデータを追加
    event.setMetadata("source", "web")
    event.setMetadata("version", "1.0")
    event.setMetadata("correlationId", "abc123")
    
    # Then: メタデータが取得できる
    check event.getMetadata("source") == "web"
    check event.getMetadata("version") == "1.0"
    check event.getMetadata("correlationId") == "abc123"
    check event.getMetadata("missing") == ""
  
  test "Event error handling":
    # Given: エラーハンドリング付きイベントバス
    let bus = newEventBus()
    var errorHandled = false
    var successHandled = false
    
    # When: エラーハンドラーを設定
    bus.onError(proc(event: Event, error: ref Exception) =
      errorHandled = true
    )
    
    # When: エラーを発生させるハンドラー
    discard bus.subscribe("error.test") do (event: Event):
      raise newException(ValueError, "Test error")
    
    # When: 正常なハンドラー
    discard bus.subscribe("success.test") do (event: Event):
      successHandled = true
    
    # When: イベントを発行
    bus.publish(newEvent("error.test"))
    bus.publish(newEvent("success.test"))
    
    # Then: エラーが適切に処理される
    check errorHandled
    check successHandled
  
  test "Event namespacing":
    # Given: 名前空間付きイベントバス
    let globalBus = newEventBus()
    let userBus = globalBus.namespace("user")
    let orderBus = globalBus.namespace("order")
    
    var userEvents: seq[string] = @[]
    var orderEvents: seq[string] = @[]
    
    # When: 各名前空間でサブスクライブ
    userBus.subscribe("created") do (event: Event):
      userEvents.add(event.eventType)
    
    orderBus.subscribe("created") do (event: Event):
      orderEvents.add(event.eventType)
    
    # When: 名前空間経由でイベントを発行
    userBus.publish(newEvent("created"))
    orderBus.publish(newEvent("created"))
    
    # Then: 正しい名前空間で受信
    check userEvents == @["user.created"]
    check orderEvents == @["order.created"]
  
  test "Event aggregation":
    # Given: イベント集約
    let bus = newEventBus()
    let aggregator = newEventAggregator(bus, 100, 1000)  # 100イベントまたは1秒
    
    var batchReceived = false
    var eventCount = 0
    
    # When: バッチハンドラーを設定
    aggregator.onBatch("metrics.*", proc(events: seq[Event]) =
      batchReceived = true
      eventCount = events.len
    )
    
    # When: 複数のメトリクスイベントを発行
    for i in 1..50:
      bus.publish(newEvent("metrics.cpu", %*{"value": i}))
    
    # Time-based aggregation をトリガー
    sleep(1100)
    aggregator.flush()
    
    # Then: バッチとして受信
    check batchReceived
    check eventCount == 50
  
  # 統合テスト
  test "Complete event workflow":
    # Given: 完全なイベントシステム
    let bus = newEventBus()
    let store = newEventStore()
    store.connect(bus)
    
    var workflow: seq[string] = @[]
    
    # ミドルウェアで認証チェック
    bus.addMiddleware(proc(event: Event, next: proc()) =
      if event.getMetadata("authenticated") == "true":
        workflow.add("auth_passed")
        next()
      else:
        workflow.add("auth_failed")
    )
    
    # 優先度付きハンドラー
    discard bus.subscribePriority("order.*", 100) do (event: Event):
      workflow.add("handle_" & event.eventType)
    
    # エラーハンドリング
    bus.onError(proc(event: Event, error: ref Exception) =
      workflow.add("error_handled")
    )
    
    # When: 認証されたイベント
    let event1 = newEvent("order.created", %*{"id": 1})
    event1.setMetadata("authenticated", "true")
    bus.publish(event1)
    
    # When: 認証されていないイベント
    let event2 = newEvent("order.updated", %*{"id": 1})
    event2.setMetadata("authenticated", "false")
    bus.publish(event2)
    
    # Then: ワークフローが正しい
    check workflow == @[
      "auth_passed",
      "handle_order.created",
      "auth_failed"
    ]
    
    # イベントストアの確認
    let storedEvents = store.getEvents("order.*")
    check storedEvents.len == 2  # 両方のイベントが記録される
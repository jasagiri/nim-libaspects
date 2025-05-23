## ファイル: examples/events_example.nim
## 内容: イベントシステムの使用例

import nim_libaspects/events
import std/[json, times, strformat, asyncdispatch, random]

# アプリケーションのイベントシステムをセットアップ
proc setupEventSystem(): EventBus =
  let bus = newEventBus("example")
  
  # エラーハンドリング
  bus.onError(proc(e: Event, error: ref Exception) {.gcsafe.} =
    echo fmt"[ERROR] Event: {e.eventType}, Error: {error.msg}"
  )
  
  # ログミドルウェア
  proc logMiddleware(e: Event, next: proc()) {.gcsafe.} =
    echo fmt"[MIDDLEWARE] Processing: {e.eventType}"
    next()
  
  bus.addMiddleware(logMiddleware)
  
  return bus

# ユーザー関連のイベントハンドラ
proc setupUserHandlers(bus: EventBus) =
  # ユーザー作成
  discard bus.subscribe("user.created", proc(e: Event) {.gcsafe.} =
    echo fmt"New user created: {e.data["name"].str} (ID: {e.data["id"].num})"
  )
  
  # ユーザー更新
  discard bus.subscribe("user.updated", proc(e: Event) {.gcsafe.} =
    echo fmt"User updated: ID {e.data["id"].num}"
    if e.data.hasKey("name"):
      echo fmt"  New name: {e.data["name"].str}"
  )
  
  # ユーザー削除
  discard bus.subscribe("user.deleted", proc(e: Event) {.gcsafe.} =
    echo fmt"User deleted: ID {e.data["id"].num}"
  )

# 注文処理システム
proc setupOrderHandlers(bus: EventBus) =
  # 注文作成
  discard bus.subscribe("order.created", proc(e: Event) {.gcsafe.} =
    echo fmt"New order #{e.data["orderId"].num} from user {e.data["userId"].num}"
    echo fmt"  Amount: ${e.data["amount"].fnum:.2f}"
    
    # 在庫確認をトリガー
    bus.publish(newEvent("inventory.check", %*{
      "orderId": e.data["orderId"],
      "items": e.data["items"]
    }))
  )
  
  # 在庫確認結果
  discard bus.subscribe("inventory.checked", proc(e: Event) {.gcsafe.} =
    let orderId = e.data["orderId"].num
    let available = e.data["available"].bval
    
    if available:
      echo fmt"  ✓ Inventory available for order #{orderId}"
      # 支払い処理をトリガー
      bus.publish(newEvent("payment.process", %*{
        "orderId": orderId,
        "amount": e.data["amount"]
      }))
    else:
      echo fmt"  ✗ Inventory not available for order #{orderId}"
      bus.publish(newEvent("order.failed", %*{
        "orderId": orderId,
        "reason": "out_of_stock"
      }))
  )
  
  # 支払い処理
  discard bus.subscribe("payment.process", proc(e: Event) {.gcsafe.} =
    let orderId = e.data["orderId"].num
    echo fmt"Processing payment for order #{orderId}"
    
    # シミュレーション: 80%の確率で成功
    if rand(1.0) < 0.8:
      bus.publish(newEvent("payment.completed", %*{
        "orderId": orderId,
        "transactionId": fmt"TXN-{orderId}-{epochTime()}"
      }))
    else:
      bus.publish(newEvent("payment.failed", %*{
        "orderId": orderId,
        "reason": "insufficient_funds"
      }))
  )
  
  # 支払い完了
  discard bus.subscribe("payment.completed", proc(e: Event) {.gcsafe.} =
    echo fmt"  ✓ Payment completed: {e.data["transactionId"].str}"
    bus.publish(newEvent("order.completed", e.data))
  )
  
  # 支払い失敗
  discard bus.subscribe("payment.failed", proc(e: Event) {.gcsafe.} =
    echo fmt"  ✗ Payment failed: {e.data["reason"].str}"
    bus.publish(newEvent("order.failed", e.data))
  )
  
  # 注文完了
  discard bus.subscribe("order.completed", proc(e: Event) {.gcsafe.} =
    echo fmt"✅ Order #{e.data["orderId"].num} completed successfully!"
  )
  
  # 注文失敗
  discard bus.subscribe("order.failed", proc(e: Event) {.gcsafe.} =
    echo fmt"❌ Order #{e.data["orderId"].num} failed: {e.data["reason"].str}"
  )

# メトリクスアグリゲーション
proc setupMetricsAggregation(bus: EventBus) =
  let aggregator = newEventAggregator(bus, maxBatchSize = 5, maxWaitTime = 2000)
  
  aggregator.onBatch("metrics.*", proc(events: seq[Event]) {.gcsafe.} =
    echo fmt"📊 Processing {events.len} metrics:"
    var cpuSum = 0.0
    var memSum = 0.0
    
    for event in events:
      case event.eventType
      of "metrics.cpu":
        cpuSum += event.data["value"].fnum
      of "metrics.memory":
        memSum += event.data["value"].fnum
      else:
        discard
    
    if events.len > 0:
      echo fmt"  Average CPU: {cpuSum / events.len.float:.1f}%"
      echo fmt"  Average Memory: {memSum / events.len.float:.1f}MB"
  )
  
  # メトリクスの生成
  proc generateMetrics(bus: EventBus) {.async.} =
    for i in 1..10:
      bus.publish(newEvent("metrics.cpu", %*{
        "value": rand(100.0),
        "timestamp": epochTime()
      }))
      bus.publish(newEvent("metrics.memory", %*{
        "value": rand(8192.0),
        "timestamp": epochTime()
      }))
      await sleepAsync(300)
  
  # 非同期でメトリクスを生成
  asyncCheck generateMetrics(bus)

# イベントストアでの監査
proc setupAuditing(bus: EventBus): EventStore =
  let store = newEventStore(maxEvents = 100)
  store.connect(bus)
  
  # 重要なイベントのみフィルタリング
  discard bus.subscribe("*.completed", proc(e: Event) {.gcsafe.} =
    echo fmt"[AUDIT] Stored: {e.eventType}"
  )
  
  discard bus.subscribe("*.failed", proc(e: Event) {.gcsafe.} =
    echo fmt"[AUDIT] Stored: {e.eventType}"
  )
  
  return store

# メインアプリケーション
proc main() {.async.} =
  echo "=== Event System Example ==="
  echo ""
  
  # セットアップ
  let bus = setupEventSystem()
  setupUserHandlers(bus)
  setupOrderHandlers(bus)
  setupMetricsAggregation(bus)
  let store = setupAuditing(bus)
  
  # ユーザーイベントのシミュレーション
  echo "--- User Events ---"
  bus.publish(newEvent("user.created", %*{
    "id": 1,
    "name": "Alice",
    "email": "alice@example.com"
  }))
  
  bus.publish(newEvent("user.updated", %*{
    "id": 1,
    "name": "Alice Smith"
  }))
  
  echo ""
  
  # 注文フローのシミュレーション
  echo "--- Order Processing ---"
  bus.publish(newEvent("order.created", %*{
    "orderId": 1001,
    "userId": 1,
    "amount": 99.99,
    "items": ["item-1", "item-2"]
  }))
  
  # 在庫チェック結果をシミュレート
  await sleepAsync(100)
  bus.publish(newEvent("inventory.checked", %*{
    "orderId": 1001,
    "amount": 99.99,
    "available": true
  }))
  
  await sleepAsync(500)
  echo ""
  
  # メトリクスの待機
  echo "--- Metrics Aggregation ---"
  await sleepAsync(3000)
  echo ""
  
  # 監査ログの表示
  echo "--- Audit Log ---"
  let auditEvents = store.getEvents()
  echo fmt"Total events stored: {auditEvents.len}"
  for event in auditEvents[^min(5, auditEvents.len)..^1]:
    echo fmt"  {event.timestamp}: {event.eventType}"
  
  echo ""
  echo "=== Example Complete ==="

# 実行
waitFor main()
# Event System Documentation

## 概要

nim-libsのイベントシステムは、イベント駆動アーキテクチャのための包括的なソリューションを提供します。
このシステムは以下のコア機能を含みます：

- イベントバス（EventBus）によるパブリッシュ／サブスクライブパターン
- イベントフィルタリングとルーティング
- 非同期イベント処理
- イベントの永続化とリプレイ
- イベントアグリゲーション

## アーキテクチャ

### コンポーネント

```nim
# イベント
Event = ref object
  id*: string
  eventType*: string
  data*: JsonNode
  timestamp*: Time

# イベントバス
EventBus = ref object
  subscriptions: seq[Subscription]
  middleware: seq[EventMiddleware]
  errorHandler: EventErrorHandler
  lock: Lock
  namespacePrefix: string

# イベントストア
EventStore = ref object
  events: seq[Event]
  bus: EventBus
  maxEvents: int

# イベントアグリゲータ
EventAggregator = ref object
  bus: EventBus
  buffer: seq[Event]
  handler: EventBatchHandler
  maxBatchSize: int
  maxWaitTime: int
  lastFlush: Time
```

## 基本的な使用方法

### イベントの作成

```nim
import nim_libaspects/events
import std/json

# シンプルなイベント
let event = newEvent("user.created")

# データ付きイベント
let userEvent = newEvent("user.created", %*{
  "userId": 123,
  "name": "John Doe",
  "email": "john@example.com"
})

# メタデータの追加
userEvent.setMetadata("source", "web-api")
userEvent.setMetadata("version", "1.0")
```

### イベントバスの使用

```nim
# イベントバスの作成
let bus = newEventBus()

# サブスクライブ
let subscriptionId = bus.subscribe("user.*", proc(e: Event) =
  echo "User event received: ", e.eventType
  echo "Data: ", e.data
)

# イベントのパブリッシュ
bus.publish(newEvent("user.created", %*{"id": 1}))
bus.publish(newEvent("user.updated", %*{"id": 1, "name": "Jane"}))

# アンサブスクライブ
bus.unsubscribe(subscriptionId)
```

### パターンマッチング

```nim
# ワイルドカードパターン
discard bus.subscribe("order.*", proc(e: Event) =
  echo "Order event: ", e.eventType
)

# 全てのイベントをキャッチ
discard bus.subscribe("*", proc(e: Event) =
  echo "Any event: ", e.eventType
)

# 特定のイベント
discard bus.subscribe("payment.completed", proc(e: Event) =
  echo "Payment completed"
)
```

### 優先度付きサブスクリプション

```nim
# 高優先度ハンドラ（最初に実行）
discard bus.subscribePriority("critical.*", 100, proc(e: Event) =
  echo "Critical event (high priority)"
)

# 通常優先度
discard bus.subscribePriority("normal.*", 50, proc(e: Event) =
  echo "Normal event"
)

# 低優先度ハンドラ（最後に実行）
discard bus.subscribePriority("log.*", 10, proc(e: Event) =
  echo "Log event (low priority)"
)
```

### イベントフィルタリング

```nim
# カスタムフィルタ
let filter = EventFilter(
  eventType: "order.*",
  predicate: proc(e: Event): bool =
    if e.data.hasKey("amount"):
      return e.data["amount"].num > 100
    return false
)

discard bus.subscribeWithFilter(filter, proc(e: Event) =
  echo "Large order: ", e.data["amount"]
)
```

### ミドルウェア

```nim
# ロギングミドルウェア
bus.addMiddleware(proc(e: Event, next: proc()) =
  echo "Before: ", e.eventType
  next()
  echo "After: ", e.eventType
)

# 認証ミドルウェア
bus.addMiddleware(proc(e: Event, next: proc()) =
  if not e.hasMetadata("auth"):
    echo "Unauthorized event"
    return  # nextを呼ばないことでチェーンを停止
  next()
)
```

### エラーハンドリング

```nim
# グローバルエラーハンドラ
bus.onError(proc(e: Event, error: ref Exception) =
  echo "Error in event handler: ", error.msg
  echo "Event: ", e.eventType
)

# エラーを発生させるハンドラ
discard bus.subscribe("test", proc(e: Event) =
  raise newException(ValueError, "Test error")
)
```

### ネームスペース

```nim
# ネームスペース付きバス
let appBus = newEventBus("app")
let userBus = appBus.namespace("user")
let authBus = userBus.namespace("auth")

# イベントは自動的にプレフィックスが付く
authBus.publish(newEvent("login"))  # => "app.user.auth.login"
```

## 高度な機能

### 非同期イベント処理

```nim
import std/asyncdispatch

# 非同期イベントバス
let asyncBus = newAsyncEventBus()

# 非同期ハンドラ
discard asyncBus.subscribeAsync("process.*", proc(e: Event): Future[void] {.async.} =
  echo "Processing async: ", e.eventType
  await sleepAsync(1000)
  echo "Done processing: ", e.eventType
)

# 非同期パブリッシュ
await asyncBus.publishAsync(newEvent("process.data"))
```

### イベントストア

```nim
# イベントストアの作成
let store = newEventStore()
store.connect(bus)

# 全てのイベントが自動的に保存される
bus.publish(newEvent("test1"))
bus.publish(newEvent("test2"))

# イベントの取得
let allEvents = store.getEvents()
let testEvents = store.getEvents("test*")
let recentEvents = store.getEventsSince(getTime() - 3600)

# イベントのリプレイ
store.replay()  # 全イベントを再パブリッシュ
store.replay("test*")  # パターンマッチでリプレイ
```

### イベントアグリゲータ

```nim
# バッチ処理のためのアグリゲータ
let aggregator = newEventAggregator(bus, 
  maxBatchSize = 100,
  maxWaitTime = 5000  # 5秒
)

# バッチハンドラ
aggregator.onBatch("metrics.*", proc(events: seq[Event]) =
  echo "Processing batch of ", events.len, " metrics"
  # バッチ処理ロジック
)

# イベントは自動的にバッファリングされる
for i in 1..150:
  bus.publish(newEvent("metrics.cpu", %*{"value": i}))
  
# 手動フラッシュも可能
aggregator.flush()
```

### イベントのシリアライズ

```nim
# JSONへのシリアライズ
let event = newEvent("test", %*{"data": "value"})
event.setMetadata("meta", "data")

let jsonStr = event.toJson()
echo jsonStr

# JSONからのデシリアライズ
let restored = fromJson(jsonStr)
echo restored.eventType
echo restored.getMetadata("meta")
```

## ベストプラクティス

### 1. イベント命名規則

```nim
# 良い例：名詞.動詞形式
"user.created"
"order.completed"
"payment.processed"

# ネームスペースを活用
"app.module.entity.action"
```

### 2. エラーハンドリング

```nim
# 常にエラーハンドラを設定
bus.onError(proc(e: Event, error: ref Exception) =
  # ログ記録、通知など
)

# ハンドラ内でのエラー処理
discard bus.subscribe("important", proc(e: Event) =
  try:
    # 処理
  except:
    # ローカルエラー処理
)
```

### 3. メモリ管理

```nim
# イベントストアのサイズ制限
let store = newEventStore(maxEvents = 10000)

# 定期的なクリーンアップ
store.clear()
```

### 4. パフォーマンス考慮

```nim
# 高頻度イベントにはアグリゲータを使用
let aggregator = newEventAggregator(bus, 1000, 1000)

# 重要度による優先度設定
discard bus.subscribePriority("critical.*", 100, criticalHandler)
discard bus.subscribePriority("normal.*", 50, normalHandler)
```

## サンプルアプリケーション

```nim
import nim_libaspects/events
import std/[json, times, asyncdispatch]

# アプリケーションイベントバス
let appBus = newEventBus("myapp")

# エラーハンドリング
appBus.onError(proc(e: Event, error: ref Exception) =
  echo "[ERROR] Event: ", e.eventType, " Error: ", error.msg
)

# ロギングミドルウェア
appBus.addMiddleware(proc(e: Event, next: proc()) =
  echo "[LOG] Event: ", e.eventType, " at ", e.timestamp
  next()
)

# ビジネスロジックハンドラ
discard appBus.subscribe("order.created", proc(e: Event) =
  echo "New order: ", e.data["orderId"]
  # 在庫確認
  appBus.publish(newEvent("inventory.check", e.data))
)

discard appBus.subscribe("inventory.checked", proc(e: Event) =
  if e.data["available"].bval:
    appBus.publish(newEvent("payment.process", e.data))
  else:
    appBus.publish(newEvent("order.failed", %*{
      "orderId": e.data["orderId"],
      "reason": "out_of_stock"
    }))
)

# イベントストアで監査証跡を保持
let auditStore = newEventStore()
auditStore.connect(appBus)

# アプリケーション実行
appBus.publish(newEvent("order.created", %*{
  "orderId": 123,
  "amount": 99.99,
  "items": ["item1", "item2"]
}))
```

## トラブルシューティング

### 一般的な問題

1. **イベントが受信されない**
   - パターンマッチングを確認
   - サブスクリプションが有効か確認
   - ネームスペースプレフィックスを確認

2. **メモリリーク**
   - サブスクリプションのアンサブスクライブを忘れずに
   - イベントストアのサイズを制限
   - 循環参照に注意

3. **パフォーマンス問題**
   - 高頻度イベントにアグリゲータを使用
   - 適切な優先度を設定
   - 非同期処理を活用

## API リファレンス

完全なAPIドキュメントは、[nim-libs API documentation](../htmldocs/events.html)を参照してください。
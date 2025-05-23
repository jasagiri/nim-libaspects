## ファイル: src/nim_libaspects/events.nim
## 内容: イベントシステム実装

import std/[tables, json, times, locks, strutils, asyncdispatch, oids, sequtils]

# イベント関連の型定義
type
  Event* = ref object
    id*: string
    eventType*: string
    data*: JsonNode
    timestamp*: Time
    metadata: Table[string, string]
  
  EventHandler* = proc(event: Event) {.gcsafe.}
  AsyncEventHandler* = proc(event: Event): Future[void] {.gcsafe.}
  EventMiddleware* = proc(event: Event, next: proc()) {.gcsafe.}
  EventErrorHandler* = proc(event: Event, error: ref Exception) {.gcsafe.}
  EventFilter* = object
    eventType*: string
    predicate*: proc(event: Event): bool {.gcsafe.}
  
  Subscription = object
    id: string
    pattern: string
    handler: EventHandler
    priority: int
    filter: EventFilter
  
  EventBus* = ref object
    subscriptions: seq[Subscription]
    middleware: seq[EventMiddleware]
    errorHandler: EventErrorHandler
    lock: Lock
    namespacePrefix: string
  
  AsyncEventBus* = ref object
    bus: EventBus
    asyncHandlers: Table[string, seq[AsyncEventHandler]]
  
  EventStore* = ref object
    events: seq[Event]
    bus: EventBus
    lock: Lock
  
  EventAggregator* = ref object
    bus: EventBus
    buffers: Table[string, seq[Event]]
    handlers: Table[string, proc(events: seq[Event]) {.gcsafe.}]
    maxSize: int
    maxAge: Duration
    lastFlush: Table[string, Time]
    lock: Lock

# Event implementation
proc newEvent*(eventType: string, data: JsonNode = newJObject()): Event =
  result = Event(
    id: $genOid(),
    eventType: eventType,
    data: data,
    timestamp: getTime(),
    metadata: initTable[string, string]()
  )

proc setMetadata*(event: Event, key, value: string) =
  event.metadata[key] = value

proc getMetadata*(event: Event, key: string): string =
  event.metadata.getOrDefault(key, "")

# EventBus implementation
proc newEventBus*(namespacePrefix: string = ""): EventBus =
  result = EventBus(
    subscriptions: @[],
    middleware: @[],
    errorHandler: nil,
    namespacePrefix: namespacePrefix
  )
  initLock(result.lock)

proc subscribe*(bus: EventBus, pattern: string, handler: EventHandler): string =
  withLock bus.lock:
    let id = $genOid()
    bus.subscriptions.add(Subscription(
      id: id,
      pattern: if bus.namespacePrefix != "": bus.namespacePrefix & "." & pattern else: pattern,
      handler: handler,
      priority: 0,
      filter: EventFilter()
    ))
    result = id

proc subscribePriority*(bus: EventBus, pattern: string, priority: int, handler: EventHandler): string =
  withLock bus.lock:
    let id = $genOid()
    let subscription = Subscription(
      id: id,
      pattern: if bus.namespacePrefix != "": bus.namespacePrefix & "." & pattern else: pattern,
      handler: handler,
      priority: priority,
      filter: EventFilter()
    )
    
    # 優先度順に挿入
    var inserted = false
    for i in 0..<bus.subscriptions.len:
      if bus.subscriptions[i].priority < priority:
        bus.subscriptions.insert(subscription, i)
        inserted = true
        break
    
    if not inserted:
      bus.subscriptions.add(subscription)
    
    result = id

proc subscribeWithFilter*(bus: EventBus, filter: EventFilter, handler: EventHandler): string =
  withLock bus.lock:
    let id = $genOid()
    bus.subscriptions.add(Subscription(
      id: id,
      pattern: filter.eventType,
      handler: handler,
      priority: 0,
      filter: filter
    ))
    result = id

proc unsubscribe*(bus: EventBus, id: string) =
  withLock bus.lock:
    bus.subscriptions = bus.subscriptions.filterIt(it.id != id)

proc matchesPattern(eventType, pattern: string): bool =
  if pattern.endsWith("*"):
    let prefix = pattern[0..^2]
    result = eventType.startsWith(prefix)
  else:
    result = eventType == pattern

proc publish*(bus: EventBus, event: Event) =
  var handlers: seq[tuple[handler: EventHandler, priority: int]] = @[]
  
  # Collect matching handlers
  withLock bus.lock:
    # Apply namespace prefix if set
    if bus.namespacePrefix != "" and not event.eventType.startsWith(bus.namespacePrefix):
      event.eventType = bus.namespacePrefix & "." & event.eventType
    
    for sub in bus.subscriptions:
      if matchesPattern(event.eventType, sub.pattern):
        # Apply filter if present
        if sub.filter.predicate != nil:
          if not sub.filter.predicate(event):
            continue
        handlers.add((sub.handler, sub.priority))
  
  # Execute middleware chain
  proc executeHandlers() =
    for (handler, _) in handlers:
      try:
        handler(event)
      except Exception as e:
        if bus.errorHandler != nil:
          bus.errorHandler(event, e)
  
  if bus.middleware.len > 0:
    var index = 0
    proc nextMiddleware() =
      if index < bus.middleware.len:
        let middleware = bus.middleware[index]
        inc(index)
        middleware(event, nextMiddleware)
      else:
        executeHandlers()
    
    nextMiddleware()
  else:
    executeHandlers()

proc addMiddleware*(bus: EventBus, middleware: EventMiddleware) =
  withLock bus.lock:
    bus.middleware.add(middleware)

proc onError*(bus: EventBus, handler: EventErrorHandler) =
  bus.errorHandler = handler

proc namespace*(bus: EventBus, prefix: string): EventBus =
  let fullPrefix = if bus.namespacePrefix != "":
    bus.namespacePrefix & "." & prefix
  else:
    prefix
  
  result = newEventBus(fullPrefix)
  result.middleware = bus.middleware
  result.errorHandler = bus.errorHandler

# AsyncEventBus implementation
proc newAsyncEventBus*(): AsyncEventBus =
  result = AsyncEventBus(
    bus: newEventBus(),
    asyncHandlers: initTable[string, seq[AsyncEventHandler]]()
  )

proc subscribeAsync*(bus: AsyncEventBus, pattern: string, handler: AsyncEventHandler): string =
  let id = $genOid()
  if pattern notin bus.asyncHandlers:
    bus.asyncHandlers[pattern] = @[]
  bus.asyncHandlers[pattern].add(handler)
  result = id

proc publishAsync*(bus: AsyncEventBus, event: Event): Future[void] {.async.} =
  # 同期ハンドラーを実行
  bus.bus.publish(event)
  
  # 非同期ハンドラーを実行
  var futures: seq[Future[void]] = @[]
  
  for pattern, handlers in bus.asyncHandlers:
    if matchesPattern(event.eventType, pattern):
      for handler in handlers:
        futures.add(handler(event))
  
  # 全ての非同期ハンドラーを待つ
  if futures.len > 0:
    await all(futures)

# EventStore implementation
proc newEventStore*(): EventStore =
  result = EventStore(
    events: @[],
    bus: nil
  )
  initLock(result.lock)

proc connect*(store: EventStore, bus: EventBus) =
  store.bus = bus
  # We need a different approach for capturing events in EventStore
  # due to GC safety constraints

proc store*(store: EventStore, event: Event) =
  withLock store.lock:
    store.events.add(event)

proc getEvents*(store: EventStore, pattern: string = "*"): seq[Event] =
  withLock store.lock:
    result = @[]
    for event in store.events:
      if matchesPattern(event.eventType, pattern):
        result.add(event)

proc replay*(store: EventStore, pattern: string = "*") =
  let events = store.getEvents(pattern)
  for event in events:
    store.bus.publish(event)

# EventAggregator implementation
proc newEventAggregator*(bus: EventBus, maxSize: int, maxAgeMs: int): EventAggregator =
  result = EventAggregator(
    bus: bus,
    buffers: initTable[string, seq[Event]](),
    handlers: initTable[string, proc(events: seq[Event]) {.gcsafe.}](),
    maxSize: maxSize,
    maxAge: initDuration(milliseconds = maxAgeMs),
    lastFlush: initTable[string, Time]()
  )
  initLock(result.lock)

proc onBatch*(aggregator: EventAggregator, pattern: string, handler: proc(events: seq[Event]) {.gcsafe.}) =
  aggregator.handlers[pattern] = handler
  
  # Set up event listener
  discard aggregator.bus.subscribe(pattern) do (event: Event):
    withLock aggregator.lock:
      if pattern notin aggregator.buffers:
        aggregator.buffers[pattern] = @[]
        aggregator.lastFlush[pattern] = getTime()
      
      aggregator.buffers[pattern].add(event)
      
      # Check if we need to flush
      let shouldFlush = aggregator.buffers[pattern].len >= aggregator.maxSize or
                       getTime() - aggregator.lastFlush[pattern] >= aggregator.maxAge
      
      if shouldFlush:
        let events = aggregator.buffers[pattern]
        aggregator.buffers[pattern] = @[]
        aggregator.lastFlush[pattern] = getTime()
        
        # Call handler with batch
        if pattern in aggregator.handlers:
          aggregator.handlers[pattern](events)

proc flush*(aggregator: EventAggregator) =
  withLock aggregator.lock:
    for pattern, events in aggregator.buffers:
      if events.len > 0 and pattern in aggregator.handlers:
        aggregator.handlers[pattern](events)
        aggregator.buffers[pattern] = @[]
        aggregator.lastFlush[pattern] = getTime()

# Helper functions
proc toJson*(event: Event): JsonNode =
  result = %*{
    "id": event.id,
    "eventType": event.eventType,
    "data": event.data,
    "timestamp": event.timestamp.toUnix(),
    "metadata": event.metadata
  }

proc fromJson*(json: JsonNode): Event =
  result = Event(
    id: json["id"].str,
    eventType: json["eventType"].str,
    data: json["data"],
    timestamp: fromUnix(json["timestamp"].num),
    metadata: initTable[string, string]()
  )
  
  for key, value in json["metadata"]:
    result.metadata[key] = value.str
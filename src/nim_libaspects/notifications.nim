## notifications.nim
## 通知システムの実装

import std/[json, times, strformat, tables, sequtils, options, oids, asyncdispatch, httpclient, strutils, math]
import ./logging

type
  NotificationSeverity* = enum
    nsInfo = "info"
    nsMedium = "medium"  
    nsHigh = "high"
    nsCritical = "critical"
  
  NotificationStatus* = enum
    nsPending = "pending"
    nsSent = "sent"
    nsFailed = "failed"
    nsRetrying = "retrying"
  
  HttpMethod* = enum
    hmGet = "GET"
    hmPost = "POST"
    hmPut = "PUT"
    hmDelete = "DELETE"
  
  Notification* = ref object
    id*: string
    title*: string
    message*: string
    severity*: NotificationSeverity
    metadata*: JsonNode
    timestamp*: Time
    status*: NotificationStatus
  
  NotificationChannel* = ref object of RootObj
    name*: string
  
  NotificationResult* = object
    channelName*: string
    notification*: Notification
    success*: bool
    error*: string
    attempts*: int
    timestamp*: Time
  
  NotificationTemplate* = object
    name*: string
    titleTemplate*: string
    messageTemplate*: string
    defaultSeverity*: NotificationSeverity
  
  NotificationRoute* = object
    name*: string
    filter*: proc(n: Notification): bool {.gcsafe.}
    channels*: seq[string]
  
  RetryPolicy* = object
    maxAttempts*: int
    backoffMultiplier*: float
    initialDelayMs*: int
  
  RateLimit* = object
    maxPerMinute*: int
    maxPerHour*: int
  
  AggregationConfig* = object
    window*: Duration
    groupBy*: seq[string]
    maxBatchSize*: int
  
  NotificationManager* = ref object
    channels*: Table[string, NotificationChannel]
    templates*: Table[string, NotificationTemplate]
    routes*: seq[NotificationRoute]
    retryPolicy*: RetryPolicy
    rateLimits*: Table[string, RateLimit]
    aggregationConfig*: AggregationConfig
    persistenceEnabled*: bool
    persistencePath*: string
  
  # Email channel types
  EmailConfig* = object
    host*: string
    port*: int
    username*: string
    password*: string
    useTLS*: bool
    fromAddr*: string
  
  EmailChannel* = ref object of NotificationChannel
    config*: EmailConfig
  
  # Slack channel types
  SlackChannel* = ref object of NotificationChannel
    webhookUrl*: string
    defaultChannel*: string
  
  # Discord channel types
  DiscordChannel* = ref object of NotificationChannel
    webhookUrl*: string
  
  # Webhook channel types
  WebhookConfig* = object
    url*: string
    httpMethod*: HttpMethod
    headers*: Table[string, string]
    timeout*: int
  
  WebhookChannel* = ref object of NotificationChannel
    config*: WebhookConfig
  
  # Test channel for testing
  TestChannel* = ref object of NotificationChannel
    sentNotifications*: seq[Notification]
  
  # Failing channel for testing retry logic
  FailingChannel* = ref object of NotificationChannel
    failCount*: int
    attemptCount*: int

# Notification creation
proc newNotification*(title, message: string, severity: NotificationSeverity, 
                     metadata: JsonNode = nil): Notification =
  result = Notification(
    id: $genOid(),
    title: title,
    message: message,
    severity: severity,
    metadata: if metadata.isNil: newJObject() else: metadata,
    timestamp: getTime(),
    status: nsPending
  )

# Template rendering
proc render*(tmpl: NotificationTemplate, params: JsonNode): Notification =
  var title = tmpl.titleTemplate
  var message = tmpl.messageTemplate
  
  # Simple template variable replacement
  for key, value in params:
    let placeholder = "{" & key & "}"
    title = title.replace(placeholder, value.getStr())
    message = message.replace(placeholder, value.getStr())
  
  result = newNotification(title, message, tmpl.defaultSeverity, params)

# Channel implementations
proc newEmailChannel*(host: string, port: int, username, password: string): EmailChannel =
  result = EmailChannel(
    name: "email",
    config: EmailConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      useTLS: true,
      fromAddr: username
    )
  )

proc newEmailChannel*(config: EmailConfig): EmailChannel =
  result = EmailChannel(name: "email", config: config)

proc newSlackChannel*(webhookUrl, defaultChannel: string): SlackChannel =
  result = SlackChannel(
    name: "slack",
    webhookUrl: webhookUrl,
    defaultChannel: defaultChannel
  )

proc formatNotification*(channel: SlackChannel, notification: Notification): JsonNode =
  # Format notification for Slack
  result = %*{
    "text": notification.title,
    "attachments": [{
      "text": notification.message,
      "color": case notification.severity
        of nsInfo: "good"
        of nsMedium: "warning"  
        of nsHigh: "danger"
        of nsCritical: "#ff0000",
      "fields": if notification.metadata.hasKey("fields"):
        notification.metadata["fields"]
      else:
        newJArray(),
      "footer": if notification.metadata.hasKey("footer"):
        notification.metadata["footer"]
      else:
        newJString("Notification System"),
      "ts": notification.timestamp.toUnix()
    }]
  }
  
  # Merge additional metadata if present
  if notification.metadata.hasKey("color"):
    result["attachments"][0]["color"] = notification.metadata["color"]

proc newDiscordChannel*(webhookUrl: string): DiscordChannel =
  result = DiscordChannel(
    name: "discord",
    webhookUrl: webhookUrl
  )

proc formatNotification*(channel: DiscordChannel, notification: Notification): JsonNode =
  # Format notification for Discord
  result = %*{
    "content": notification.title,
    "embeds": [{
      "description": notification.message,
      "color": case notification.severity
        of nsInfo: 0x00ff00
        of nsMedium: 0xffff00
        of nsHigh: 0xff8800
        of nsCritical: 0xff0000
    }]
  }
  
  # Merge embed data if present
  if notification.metadata.hasKey("embed"):
    for key, value in notification.metadata["embed"]:
      result["embeds"][0][key] = value

proc newWebhookChannel*(url: string): WebhookChannel =
  result = WebhookChannel(
    name: "webhook",
    config: WebhookConfig(
      url: url,
      httpMethod: hmPost,
      headers: initTable[string, string](),
      timeout: 30
    )
  )

proc newWebhookChannel*(config: WebhookConfig): WebhookChannel =
  result = WebhookChannel(name: "webhook", config: config)

proc newTestChannel*(name: string): TestChannel =
  result = TestChannel(
    name: name,
    sentNotifications: @[]
  )

proc newFailingChannel*(name: string, failCount: int): FailingChannel =
  result = FailingChannel(
    name: name,
    failCount: failCount,
    attemptCount: 0
  )

# Async send methods
method sendAsync*(channel: NotificationChannel, notification: Notification): Future[NotificationResult] {.base, async.} =
  # Base implementation
  result = NotificationResult(
    channelName: channel.name,
    notification: notification,
    success: false,
    error: "Not implemented",
    attempts: 1,
    timestamp: getTime()
  )

method sendAsync*(channel: TestChannel, notification: Notification): Future[NotificationResult] {.async.} =
  # Test channel just stores the notification
  channel.sentNotifications.add(notification)
  result = NotificationResult(
    channelName: channel.name,
    notification: notification,
    success: true,
    error: "",
    attempts: 1,
    timestamp: getTime()
  )

method sendAsync*(channel: FailingChannel, notification: Notification): Future[NotificationResult] {.async.} =
  # Failing channel fails the first N attempts
  inc(channel.attemptCount)
  
  if channel.attemptCount <= channel.failCount:
    result = NotificationResult(
      channelName: channel.name,
      notification: notification,
      success: false,
      error: "Simulated failure",
      attempts: channel.attemptCount,
      timestamp: getTime()
    )
  else:
    result = NotificationResult(
      channelName: channel.name,
      notification: notification,
      success: true,
      error: "",
      attempts: channel.attemptCount,
      timestamp: getTime()
    )

# Notification Manager
proc newNotificationManager*(): NotificationManager =
  result = NotificationManager(
    channels: initTable[string, NotificationChannel](),
    templates: initTable[string, NotificationTemplate](),
    routes: @[],
    retryPolicy: RetryPolicy(maxAttempts: 1, backoffMultiplier: 1.0, initialDelayMs: 0),
    rateLimits: initTable[string, RateLimit](),
    aggregationConfig: AggregationConfig(window: initDuration(), groupBy: @[], maxBatchSize: 0),
    persistenceEnabled: false,
    persistencePath: ""
  )

proc addChannel*(manager: NotificationManager, channel: NotificationChannel) =
  manager.channels[channel.name] = channel

proc addTemplate*(manager: NotificationManager, tmpl: NotificationTemplate) =
  manager.templates[tmpl.name] = tmpl

proc addRoute*(manager: NotificationManager, route: NotificationRoute) =
  manager.routes.add(route)

proc setRetryPolicy*(manager: NotificationManager, policy: RetryPolicy) =
  manager.retryPolicy = policy

proc setRateLimit*(manager: NotificationManager, channelName: string, limit: RateLimit) =
  manager.rateLimits[channelName] = limit

proc enableAggregation*(manager: NotificationManager, config: AggregationConfig) =
  manager.aggregationConfig = config

proc enablePersistence*(manager: NotificationManager, path: string) =
  manager.persistenceEnabled = true
  manager.persistencePath = path

proc createFromTemplate*(manager: NotificationManager, templateName: string, params: JsonNode): Notification =
  if templateName in manager.templates:
    result = manager.templates[templateName].render(params)
  else:
    raise newException(ValueError, "Template not found: " & templateName)

proc send*(manager: NotificationManager, notification: Notification, channels: seq[string]): Future[seq[NotificationResult]] {.async.} =
  result = @[]
  
  for channelName in channels:
    if channelName in manager.channels:
      let channel = manager.channels[channelName]
      
      # Check rate limiting (simplified)
      if channelName in manager.rateLimits:
        # For now, just simulate rate limit check
        if false:  # Would implement actual rate limiting logic
          result.add(NotificationResult(
            channelName: channelName,
            notification: notification,
            success: false,
            error: "Rate limit exceeded",
            attempts: 0,
            timestamp: getTime()
          ))
          continue
      
      # Send with retry logic
      var attempts = 0
      var lastResult: NotificationResult
      
      while attempts < manager.retryPolicy.maxAttempts:
        inc(attempts)
        lastResult = await channel.sendAsync(notification)
        lastResult.attempts = attempts
        
        if lastResult.success:
          break
          
        # Exponential backoff
        if attempts < manager.retryPolicy.maxAttempts:
          let delay = int(float(manager.retryPolicy.initialDelayMs) * pow(manager.retryPolicy.backoffMultiplier, float(attempts - 1)))
          await sleepAsync(delay)
      
      result.add(lastResult)

proc sendRouted*(manager: NotificationManager, notification: Notification): Future[seq[NotificationResult]] {.async.} =
  var channels: seq[string] = @[]
  
  # Apply routing rules
  for route in manager.routes:
    if route.filter(notification):
      channels.add(route.channels)
  
  # Remove duplicates
  channels = deduplicate(channels)
  
  # Send to matched channels
  if channels.len > 0:
    result = await manager.send(notification, channels)
  else:
    result = @[]

# Stub implementations for advanced features
proc schedule*(manager: NotificationManager, notification: Notification, channels: seq[string], delay: Duration): string =
  # Simplified scheduling - just return a fake ID
  result = $genOid()

proc processScheduled*(manager: NotificationManager) =
  # Process scheduled notifications
  discard

proc getHistory*(manager: NotificationManager, startTime, endTime: Time, channels: seq[string], severities: seq[NotificationSeverity]): seq[tuple[notification: Notification, result: NotificationResult]] =
  # Return empty history for now
  result = @[]

proc sendAggregated*(manager: NotificationManager, notification: Notification, channels: seq[string]): string =
  # Simplified aggregation - just return a fake ID  
  result = $genOid()

proc flushAggregated*(manager: NotificationManager) =
  # Flush aggregated notifications
  discard
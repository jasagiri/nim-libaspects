## tests/test_notifications.nim
## 通知システムのBDD仕様

import std/[unittest, json, times, tables, strformat, asyncdispatch, options]
import nim_libaspects/notifications

suite "Notification System BDD Specification":
  
  test "Notification creation and properties":
    # Given: 通知パラメータ
    let title = "System Alert"
    let message = "Database connection lost"
    let severity = NotificationSeverity.nsHigh
    let metadata = %*{"component": "database", "retry_count": 3}
    
    # When: 通知を作成
    let notification = newNotification(title, message, severity, metadata)
    
    # Then: 通知が正しく作成される
    check notification.title == title
    check notification.message == message
    check notification.severity == severity
    check notification.metadata == metadata
    check notification.id.len > 0
    check notification.timestamp.toUnix() > 0
    check notification.status == NotificationStatus.nsPending
  
  test "Notification channel abstraction":
    # Given: 異なる通知チャンネル
    let emailChannel = newEmailChannel("smtp.example.com", 587, "user@example.com", "password")
    let slackChannel = newSlackChannel("webhook-url", "#alerts")
    let discordChannel = newDiscordChannel("webhook-url")
    let webhookChannel = newWebhookChannel("https://api.example.com/notify")
    
    # Then: 全てのチャンネルが共通インターフェースを実装
    check emailChannel.name == "email"
    check slackChannel.name == "slack"
    check discordChannel.name == "discord"
    check webhookChannel.name == "webhook"
  
  test "Notification manager - send to single channel":
    # Given: 通知マネージャーとチャンネル
    let manager = newNotificationManager()
    let testChannel = newTestChannel("test")
    manager.addChannel(testChannel)
    
    # When: 通知を送信
    let notification = newNotification("Test", "Test message", NotificationSeverity.nsInfo)
    let results = waitFor manager.send(notification, @["test"])
    
    # Then: 通知が送信される
    check results.len == 1
    check results[0].channelName == "test"
    check results[0].success
    check results[0].notification.id == notification.id
    
    # テストチャンネルが通知を受信
    check testChannel.sentNotifications.len == 1
    check testChannel.sentNotifications[0].id == notification.id
  
  test "Notification manager - send to multiple channels":
    # Given: 複数のチャンネルを持つマネージャー
    let manager = newNotificationManager()
    let channel1 = newTestChannel("channel1")
    let channel2 = newTestChannel("channel2")
    let channel3 = newTestChannel("channel3")
    
    manager.addChannel(channel1)
    manager.addChannel(channel2)
    manager.addChannel(channel3)
    
    # When: 複数チャンネルに送信
    let notification = newNotification("Multi", "To multiple channels", NotificationSeverity.nsHigh)
    let results = waitFor manager.send(notification, @["channel1", "channel2"])
    
    # Then: 指定されたチャンネルのみに送信
    check results.len == 2
    check channel1.sentNotifications.len == 1
    check channel2.sentNotifications.len == 1
    check channel3.sentNotifications.len == 0
  
  test "Notification templates":
    # Given: 通知テンプレート
    let tmpl = NotificationTemplate(
      name: "error_alert",
      titleTemplate: "Error in {component}",
      messageTemplate: "Error: {error_message}\nComponent: {component}\nTime: {timestamp}",
      defaultSeverity: NotificationSeverity.nsHigh
    )
    
    # When: テンプレートから通知を作成
    let params = %*{
      "component": "UserService",
      "error_message": "Connection timeout",
      "timestamp": $now()
    }
    
    let notification = tmpl.render(params)
    
    # Then: テンプレートが適用される
    check notification.title == "Error in UserService"
    check "Connection timeout" in notification.message
    check "UserService" in notification.message
    check notification.severity == NotificationSeverity.nsHigh
  
  test "Email channel configuration and sending":
    # Given: メールチャンネル設定
    let emailConfig = EmailConfig(
      host: "smtp.gmail.com",
      port: 587,
      username: "test@example.com",
      password: "password",
      useTLS: true,
      fromAddr: "noreply@example.com"
    )
    
    let emailChannel = newEmailChannel(emailConfig)
    
    # When: メール通知を準備
    let notification = newNotification(
      "Test Email",
      "This is a test email notification",
      NotificationSeverity.nsInfo,
      %*{
        "to": ["user1@example.com", "user2@example.com"],
        "cc": ["cc@example.com"],
        "attachments": []
      }
    )
    
    # Then: メールチャンネルが正しく設定される
    check emailChannel.name == "email"
    check emailChannel.config.host == "smtp.gmail.com"
    check emailChannel.config.useTLS == true
  
  test "Slack channel with rich formatting":
    # Given: Slackチャンネル
    let slackChannel = newSlackChannel("https://hooks.slack.com/services/xxx", "#general")
    
    # When: リッチフォーマットの通知
    let notification = newNotification(
      "Deployment Success",
      "Version 1.2.3 deployed to production",
      NotificationSeverity.nsInfo,
      %*{
        "color": "good",
        "fields": [
          {"title": "Version", "value": "1.2.3", "short": true},
          {"title": "Environment", "value": "Production", "short": true}
        ],
        "footer": "Deployment Bot",
        "ts": $now().toUnix()
      }
    )
    
    # Then: Slack固有のフォーマットが適用される
    let payload = slackChannel.formatNotification(notification)
    check payload["attachments"][0]["color"].str == "good"
    check payload["attachments"][0]["fields"].len == 2
  
  test "Discord channel with embeds":
    # Given: Discordチャンネル
    let discordChannel = newDiscordChannel("https://discord.com/api/webhooks/xxx")
    
    # When: 埋め込み付き通知
    let notification = newNotification(
      "Server Status",
      "All systems operational",
      NotificationSeverity.nsInfo,
      %*{
        "embed": {
          "color": 0x00ff00,
          "fields": [
            {"name": "CPU", "value": "45%", "inline": true},
            {"name": "Memory", "value": "62%", "inline": true}
          ],
          "thumbnail": {"url": "https://example.com/icon.png"}
        }
      }
    )
    
    # Then: Discord固有のフォーマットが適用される
    let payload = discordChannel.formatNotification(notification)
    check payload["embeds"][0]["color"].num == 0x00ff00
    check payload["embeds"][0]["fields"].len == 2
  
  test "Webhook channel with custom headers":
    # Given: Webhookチャンネル
    let webhookConfig = WebhookConfig(
      url: "https://api.example.com/notifications",
      httpMethod: HttpMethod.hmPost,
      headers: {"Authorization": "Bearer token123", "X-Source": "nim-libs"},
      timeout: 30
    )
    
    let webhookChannel = newWebhookChannel(webhookConfig)
    
    # When: カスタムペイロードの通知
    let notification = newNotification(
      "Custom Event",
      "Something happened",
      NotificationSeverity.nsMedium,
      %*{
        "event_type": "user_action",
        "user_id": 12345,
        "timestamp": $now()
      }
    )
    
    # Then: Webhook設定が正しく適用される
    check webhookChannel.config.headers["Authorization"] == "Bearer token123"
    check webhookChannel.config.httpMethod == HttpMethod.hmPost
  
  test "Notification retry mechanism":
    # Given: リトライ設定付きマネージャー
    let manager = newNotificationManager()
    let failingChannel = newFailingChannel("flaky", failCount = 2)
    manager.addChannel(failingChannel)
    
    manager.setRetryPolicy(RetryPolicy(
      maxAttempts: 3,
      backoffMultiplier: 2.0,
      initialDelayMs: 100
    ))
    
    # When: 通知を送信（最初の2回は失敗）
    let notification = newNotification("Retry Test", "Will fail twice", NotificationSeverity.nsHigh)
    let results = waitFor manager.send(notification, @["flaky"])
    
    # Then: リトライ後に成功
    check results[0].success
    check results[0].attempts == 3
    check failingChannel.attemptCount == 3
  
  test "Notification filtering and routing":
    # Given: フィルター付きマネージャー
    let manager = newNotificationManager()
    let criticalChannel = newTestChannel("critical")
    let generalChannel = newTestChannel("general")
    
    manager.addChannel(criticalChannel)
    manager.addChannel(generalChannel)
    
    # ルーティングルールを設定
    manager.addRoute(NotificationRoute(
      name: "critical_only",
      filter: proc(n: Notification): bool = n.severity == NotificationSeverity.nsCritical,
      channels: @["critical"]
    ))
    
    manager.addRoute(NotificationRoute(
      name: "all_others",
      filter: proc(n: Notification): bool = n.severity != NotificationSeverity.nsCritical,
      channels: @["general"]
    ))
    
    # When: 異なる重要度の通知を送信
    let critical = newNotification("Critical", "System down", NotificationSeverity.nsCritical)
    let info = newNotification("Info", "Update available", NotificationSeverity.nsInfo)
    
    discard waitFor manager.sendRouted(critical)
    discard waitFor manager.sendRouted(info)
    
    # Then: 適切なチャンネルにルーティング
    check criticalChannel.sentNotifications.len == 1
    check criticalChannel.sentNotifications[0].severity == NotificationSeverity.nsCritical
    check generalChannel.sentNotifications.len == 1
    check generalChannel.sentNotifications[0].severity == NotificationSeverity.nsInfo
  
  test "Notification rate limiting":
    # Given: レート制限付きマネージャー
    let manager = newNotificationManager()
    let channel = newTestChannel("limited")
    manager.addChannel(channel)
    
    manager.setRateLimit("limited", RateLimit(
      maxPerMinute: 2,
      maxPerHour: 10
    ))
    
    # When: レート制限を超える通知を送信
    var results: seq[NotificationResult] = @[]
    for i in 1..5:
      let notification = newNotification(&"Test {i}", "Rate limited", NotificationSeverity.nsInfo)
      results.add waitFor manager.send(notification, @["limited"])
    
    # Then: 制限を超えた通知は拒否される
    check results[0].success
    check results[1].success
    check not results[2].success
    check results[2].error == "Rate limit exceeded"
  
  test "Notification scheduling":
    # Given: スケジューリング対応マネージャー
    let manager = newNotificationManager()
    let channel = newTestChannel("scheduled")
    manager.addChannel(channel)
    
    # When: 遅延通知をスケジュール
    let notification = newNotification("Scheduled", "Send later", NotificationSeverity.nsInfo)
    let delay = initDuration(seconds = 2)
    let scheduleId = manager.schedule(notification, @["scheduled"], delay)
    
    # 即座にはチャンネルに届かない
    check channel.sentNotifications.len == 0
    
    # When: 待機後
    sleep(2100)
    manager.processScheduled()
    
    # Then: 通知が送信される
    check channel.sentNotifications.len == 1
    check channel.sentNotifications[0].id == notification.id
  
  test "Notification persistence and history":
    # Given: 永続化対応マネージャー
    let manager = newNotificationManager()
    manager.enablePersistence("notifications.db")
    
    let channel = newTestChannel("persistent")
    manager.addChannel(channel)
    
    # When: 通知を送信
    let notification = newNotification("Persistent", "Saved to DB", NotificationSeverity.nsMedium)
    let results = waitFor manager.send(notification, @["persistent"])
    
    # Then: 通知履歴を取得できる
    let history = manager.getHistory(
      startTime = now() - initDuration(hours = 1),
      endTime = now(),
      channels = @["persistent"],
      severities = @[NotificationSeverity.nsMedium]
    )
    
    check history.len == 1
    check history[0].notification.id == notification.id
    check history[0].result.success
  
  test "Notification aggregation":
    # Given: 集約対応マネージャー
    let manager = newNotificationManager()
    let channel = newTestChannel("aggregated")
    manager.addChannel(channel)
    
    manager.enableAggregation(AggregationConfig(
      window: initDuration(minutes = 5),
      groupBy: @["component", "severity"],
      maxBatchSize: 10
    ))
    
    # When: 同じコンポーネントから複数の通知
    for i in 1..5:
      let notification = newNotification(
        "Error",
        &"Error {i} in UserService",
        NotificationSeverity.nsHigh,
        %*{"component": "UserService"}
      )
      discard manager.sendAggregated(notification, @["aggregated"])
    
    # 集約をフラッシュ
    manager.flushAggregated()
    
    # Then: 集約された通知が送信される
    check channel.sentNotifications.len == 1
    let aggregated = channel.sentNotifications[0]
    check aggregated.title == "5 errors in UserService"
    check "Error 1" in aggregated.message
    check "Error 5" in aggregated.message
  
  test "Complete notification workflow":
    # Given: 完全な通知システム
    let manager = newNotificationManager()
    
    # 複数のチャンネルを設定
    let emailChannel = newTestChannel("email")
    let slackChannel = newTestChannel("slack")
    let webhookChannel = newTestChannel("webhook")
    
    manager.addChannel(emailChannel)
    manager.addChannel(slackChannel)
    manager.addChannel(webhookChannel)
    
    # テンプレートを設定
    let errorTemplate = NotificationTemplate(
      name: "system_error",
      titleTemplate: "Error: {error_type}",
      messageTemplate: "System error occurred\nType: {error_type}\nComponent: {component}\nDetails: {details}",
      defaultSeverity: NotificationSeverity.nsHigh
    )
    manager.addTemplate(errorTemplate)
    
    # ルーティングルールを設定
    manager.addRoute(NotificationRoute(
      name: "critical_all",
      filter: proc(n: Notification): bool = n.severity == NotificationSeverity.nsCritical,
      channels: @["email", "slack", "webhook"]
    ))
    
    manager.addRoute(NotificationRoute(
      name: "high_email_slack",
      filter: proc(n: Notification): bool = n.severity == NotificationSeverity.nsHigh,
      channels: @["email", "slack"]
    ))
    
    # When: テンプレートを使用して通知を作成・送信
    let notification = manager.createFromTemplate("system_error", %*{
      "error_type": "DatabaseConnectionLost",
      "component": "UserService",
      "details": "Connection timeout after 30s"
    })
    
    let results = waitFor manager.sendRouted(notification)
    
    # Then: 適切なチャンネルに送信される
    check results.len == 2  # High severity -> email and slack only
    check emailChannel.sentNotifications.len == 1
    check slackChannel.sentNotifications.len == 1
    check webhookChannel.sentNotifications.len == 0
    
    # 送信された通知の内容を確認
    let sentNotification = emailChannel.sentNotifications[0]
    check sentNotification.title == "Error: DatabaseConnectionLost"
    check "UserService" in sentNotification.message
    check "Connection timeout after 30s" in sentNotification.message
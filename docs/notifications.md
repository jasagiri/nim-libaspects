# Notification System

The notification system provides a flexible framework for sending notifications through various channels with support for templates, routing, retry mechanisms, and aggregation.

## Overview

The notification system consists of:
- **NotificationManager**: Central coordinator for notification handling
- **NotificationChannel**: Abstract interface for various notification channels
- **NotificationTemplate**: Reusable templates for consistent messaging
- **NotificationRoute**: Rule-based routing to specific channels
- **Retry & Rate Limiting**: Built-in reliability and throttling

## Features

- Multiple channel support (Email, Slack, Discord, Webhooks, etc.)
- Template-based message generation
- Flexible routing rules
- Automatic retry with exponential backoff
- Rate limiting per channel
- Notification aggregation
- Asynchronous sending
- Extensible channel interface

## Basic Usage

```nim
import nim_libaspects/notifications

# Create notification manager
let manager = newNotificationManager()

# Add channels
let emailChannel = newEmailChannel("smtp.example.com", 587, "user@example.com", "password")
let slackChannel = newSlackChannel("https://hooks.slack.com/services/xxx", "#alerts")

manager.addChannel(emailChannel)
manager.addChannel(slackChannel)

# Send a notification
let notification = newNotification(
  "System Alert",
  "Database connection lost",
  NotificationSeverity.nsHigh,
  %*{"component": "database", "error": "timeout"}
)

let results = waitFor manager.send(notification, @["email", "slack"])
```

## Notification Severity Levels

- `nsInfo`: Informational messages
- `nsMedium`: Warning-level notifications  
- `nsHigh`: High priority alerts
- `nsCritical`: Critical system failures

## Channel Types

### Email Channel

Send notifications via SMTP:

```nim
let emailConfig = EmailConfig(
  host: "smtp.gmail.com",
  port: 587,
  username: "notifications@example.com",
  password: "app_password",
  useTLS: true,
  fromAddr: "noreply@example.com"
)

let emailChannel = newEmailChannel(emailConfig)
```

### Slack Channel

Send to Slack using webhooks:

```nim
let slackChannel = newSlackChannel(
  webhookUrl = "https://hooks.slack.com/services/xxx",
  defaultChannel = "#general"
)

# Rich formatting support
let notification = newNotification(
  "Deployment Complete",
  "Version 2.0.0 deployed to production",
  NotificationSeverity.nsInfo,
  %*{
    "color": "good",
    "fields": [
      {"title": "Version", "value": "2.0.0", "short": true},
      {"title": "Environment", "value": "Production", "short": true}
    ]
  }
)
```

### Discord Channel

Send to Discord using webhooks:

```nim
let discordChannel = newDiscordChannel("https://discord.com/api/webhooks/xxx")

# Discord embeds support
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
      ]
    }
  }
)
```

### Webhook Channel

Generic webhook integration:

```nim
let webhookConfig = WebhookConfig(
  url: "https://api.example.com/notifications",
  httpMethod: HttpMethod.hmPost,
  headers: {
    "Authorization": "Bearer token123",
    "Content-Type": "application/json"
  }.toTable,
  timeout: 30
)

let webhookChannel = newWebhookChannel(webhookConfig)
```

## Templates

Create reusable notification templates:

```nim
let errorTemplate = NotificationTemplate(
  name: "system_error",
  titleTemplate: "Error in {component}",
  messageTemplate: "Error: {error_message}\nComponent: {component}\nTime: {timestamp}",
  defaultSeverity: NotificationSeverity.nsHigh
)

manager.addTemplate(errorTemplate)

# Use template
let notification = manager.createFromTemplate("system_error", %*{
  "component": "UserService",
  "error_message": "Connection timeout",
  "timestamp": $now()
})
```

## Routing

Define routing rules to automatically send notifications to appropriate channels:

```nim
# Route critical notifications to all channels
manager.addRoute(NotificationRoute(
  name: "critical_all",
  filter: proc(n: Notification): bool = n.severity == NotificationSeverity.nsCritical,
  channels: @["email", "slack", "pagerduty"]
))

# Route database errors to DBA team
manager.addRoute(NotificationRoute(
  name: "database_alerts",
  filter: proc(n: Notification): bool = 
    n.metadata.hasKey("component") and n.metadata["component"].str == "database",
  channels: @["dba_email", "dba_slack"]
))

# Send routed notification
let results = waitFor manager.sendRouted(notification)
```

## Retry Policy

Configure automatic retry with exponential backoff:

```nim
manager.setRetryPolicy(RetryPolicy(
  maxAttempts: 3,
  backoffMultiplier: 2.0,
  initialDelayMs: 1000
))
```

## Rate Limiting

Prevent notification flooding:

```nim
manager.setRateLimit("email", RateLimit(
  maxPerMinute: 10,
  maxPerHour: 100
))
```

## Aggregation

Batch similar notifications:

```nim
manager.enableAggregation(AggregationConfig(
  window: initDuration(minutes = 5),
  groupBy: @["component", "severity"],
  maxBatchSize: 50
))

# Send aggregated notifications
for i in 1..10:
  let notification = newNotification(
    "API Error",
    $"Request {i} failed",
    NotificationSeverity.nsHigh,
    %*{"component": "API"}
  )
  discard manager.sendAggregated(notification, @["ops_team"])

# Flush aggregated notifications
manager.flushAggregated()
```

## Custom Channels

Implement custom notification channels:

```nim
type
  SmsChannel = ref object of NotificationChannel
    apiKey: string
    sender: string

method sendAsync(channel: SmsChannel, notification: Notification): Future[NotificationResult] {.async.} =
  # Implement SMS sending logic
  let client = newHttpClient()
  client.headers["Authorization"] = "Bearer " & channel.apiKey
  
  let payload = %*{
    "to": notification.metadata["phone_number"].str,
    "from": channel.sender,
    "message": notification.message
  }
  
  try:
    let response = await client.postContent(
      "https://api.sms-provider.com/send",
      $payload
    )
    result = NotificationResult(
      channelName: channel.name,
      notification: notification,
      success: true,
      attempts: 1,
      timestamp: getTime()
    )
  except:
    result = NotificationResult(
      channelName: channel.name,
      notification: notification,
      success: false,
      error: getCurrentExceptionMsg(),
      attempts: 1,
      timestamp: getTime()
    )
```

## Best Practices

1. **Use Templates**: Create templates for consistent messaging
2. **Set Appropriate Severity**: Use correct severity levels for proper routing
3. **Include Metadata**: Add relevant context in metadata for debugging
4. **Configure Retries**: Set reasonable retry policies for critical notifications
5. **Implement Rate Limiting**: Prevent notification storms
6. **Test Channels**: Verify channel configuration before production use
7. **Monitor Results**: Check notification results for delivery failures

## Advanced Usage

### Scheduled Notifications

```nim
let notification = newNotification("Reminder", "Weekly backup due", NotificationSeverity.nsInfo)
let scheduleId = manager.schedule(notification, @["email"], initDuration(hours = 24))
```

### Notification History

```nim
let history = manager.getHistory(
  startTime = now() - initDuration(days = 7),
  endTime = now(),
  channels = @["email", "slack"],
  severities = @[NotificationSeverity.nsHigh, NotificationSeverity.nsCritical]
)

for entry in history:
  echo $entry.notification.title & " - " & $entry.result.success
```

### Persistence

Enable notification persistence for audit trails:

```nim
manager.enablePersistence("/var/lib/notifications/history.db")
```

## Troubleshooting

### Common Issues

1. **Channel Connection Failures**
   - Verify credentials and network connectivity
   - Check firewall rules for SMTP/webhook URLs
   - Ensure TLS/SSL certificates are valid

2. **Rate Limit Exceeded**
   - Adjust rate limits based on actual usage
   - Implement notification aggregation
   - Use severity-based filtering

3. **Template Rendering Errors**
   - Ensure all template variables are provided
   - Use default values for optional fields
   - Validate template syntax

4. **Retry Failures**
   - Check retry policy configuration
   - Monitor for persistent failures
   - Implement fallback channels

## API Reference

### Types

```nim
type
  NotificationSeverity* = enum
    nsInfo, nsMedium, nsHigh, nsCritical
  
  Notification* = ref object
    id*: string
    title*: string
    message*: string  
    severity*: NotificationSeverity
    metadata*: JsonNode
    timestamp*: Time
    status*: NotificationStatus
  
  NotificationResult* = object
    channelName*: string
    notification*: Notification
    success*: bool
    error*: string
    attempts*: int
    timestamp*: Time
```

### Core Functions

- `newNotification(title, message, severity, metadata): Notification`
- `newNotificationManager(): NotificationManager`
- `send(manager, notification, channels): Future[seq[NotificationResult]]`
- `sendRouted(manager, notification): Future[seq[NotificationResult]]`
- `createFromTemplate(manager, templateName, params): Notification`

### Channel Constructors

- `newEmailChannel(config): EmailChannel`
- `newSlackChannel(webhookUrl, defaultChannel): SlackChannel`
- `newDiscordChannel(webhookUrl): DiscordChannel`
- `newWebhookChannel(config): WebhookChannel`
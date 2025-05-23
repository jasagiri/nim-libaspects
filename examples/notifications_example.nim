## Notification System Example
##
## This example demonstrates various features of the notification system
## including multiple channels, templates, routing, and retry mechanisms.

import std/[json, asyncdispatch, times, strformat]
import nim_libaspects/notifications

proc main() {.async.} =
  echo "Notification System Example"
  echo "=" * 40
  
  # Create notification manager
  let manager = newNotificationManager()
  
  # Set up channels
  echo "\n1. Setting up notification channels..."
  
  # Email channel
  let emailChannel = newTestChannel("email")  # Using test channel for demo
  manager.addChannel(emailChannel)
  
  # Slack channel
  let slackChannel = newTestChannel("slack")
  manager.addChannel(slackChannel)
  
  # Critical alerts channel
  let criticalChannel = newTestChannel("critical")
  manager.addChannel(criticalChannel)
  
  echo "  ✓ Email channel configured"
  echo "  ✓ Slack channel configured"
  echo "  ✓ Critical alerts channel configured"
  
  # Configure templates
  echo "\n2. Creating notification templates..."
  
  let errorTemplate = NotificationTemplate(
    name: "system_error",
    titleTemplate: "Error: {error_type} in {component}",
    messageTemplate: "System error detected\nType: {error_type}\nComponent: {component}\nDetails: {details}\nTime: {timestamp}",
    defaultSeverity: NotificationSeverity.nsHigh
  )
  
  let infoTemplate = NotificationTemplate(
    name: "system_info",
    titleTemplate: "Info: {event}",
    messageTemplate: "{event} completed successfully\nComponent: {component}\nDuration: {duration}ms",
    defaultSeverity: NotificationSeverity.nsInfo
  )
  
  manager.addTemplate(errorTemplate)
  manager.addTemplate(infoTemplate)
  
  echo "  ✓ Error template created"
  echo "  ✓ Info template created"
  
  # Configure routing rules
  echo "\n3. Setting up routing rules..."
  
  # Route critical notifications to all channels
  manager.addRoute(NotificationRoute(
    name: "critical_broadcast",
    filter: proc(n: Notification): bool = n.severity == NotificationSeverity.nsCritical,
    channels: @["email", "slack", "critical"]
  ))
  
  # Route high priority to email and slack
  manager.addRoute(NotificationRoute(
    name: "high_priority",
    filter: proc(n: Notification): bool = n.severity == NotificationSeverity.nsHigh,
    channels: @["email", "slack"]
  ))
  
  # Route info to slack only
  manager.addRoute(NotificationRoute(
    name: "info_slack",
    filter: proc(n: Notification): bool = n.severity == NotificationSeverity.nsInfo,
    channels: @["slack"]
  ))
  
  echo "  ✓ Critical broadcast rule"
  echo "  ✓ High priority rule"
  echo "  ✓ Info to Slack rule"
  
  # Configure retry policy
  echo "\n4. Configuring retry policy..."
  manager.setRetryPolicy(RetryPolicy(
    maxAttempts: 3,
    backoffMultiplier: 2.0,
    initialDelayMs: 500
  ))
  echo "  ✓ Retry policy set (max 3 attempts, 2x backoff)"
  
  # Send notifications
  echo "\n5. Sending notifications..."
  
  # Direct notification
  let directNotification = newNotification(
    "Direct Alert",
    "This is a direct notification to specific channels",
    NotificationSeverity.nsMedium,
    %*{"source": "example", "test": true}
  )
  
  echo "\n  Sending direct notification..."
  let directResults = await manager.send(directNotification, @["email", "slack"])
  for result in directResults:
    echo &"    {result.channelName}: {result.success} (attempts: {result.attempts})"
  
  # Template-based notification
  echo "\n  Sending template-based notification..."
  let errorNotification = manager.createFromTemplate("system_error", %*{
    "error_type": "ConnectionTimeout",
    "component": "DatabaseService",
    "details": "Connection to primary database timed out after 30s",
    "timestamp": $now()
  })
  
  let errorResults = await manager.sendRouted(errorNotification)
  for result in errorResults:
    echo &"    {result.channelName}: {result.success}"
  
  # Critical notification (goes to all channels)
  echo "\n  Sending critical notification..."
  let criticalNotification = newNotification(
    "System Failure",
    "Complete system failure detected. Immediate action required!",
    NotificationSeverity.nsCritical,
    %*{
      "affected_systems": ["database", "cache", "api"],
      "downtime_start": $now(),
      "estimated_impact": "All services unavailable"
    }
  )
  
  let criticalResults = await manager.sendRouted(criticalNotification)
  for result in criticalResults:
    echo &"    {result.channelName}: {result.success}"
  
  # Info notification (slack only)
  echo "\n  Sending info notification..."
  let infoNotification = manager.createFromTemplate("system_info", %*{
    "event": "Daily backup",
    "component": "BackupService",
    "duration": "2543"
  })
  
  let infoResults = await manager.sendRouted(infoNotification)
  for result in infoResults:
    echo &"    {result.channelName}: {result.success}"
  
  # Test retry mechanism
  echo "\n6. Testing retry mechanism..."
  
  # Add a failing channel
  let failingChannel = newFailingChannel("unreliable", failCount = 2)
  manager.addChannel(failingChannel)
  
  let retryNotification = newNotification(
    "Retry Test",
    "This notification will fail twice before succeeding",
    NotificationSeverity.nsHigh
  )
  
  let retryResults = await manager.send(retryNotification, @["unreliable"])
  for result in retryResults:
    echo &"  {result.channelName}: {result.success} (attempts: {result.attempts})"
    if not result.success:
      echo &"    Error: {result.error}"
  
  # Show summary
  echo "\n7. Notification Summary:"
  echo "=" * 40
  
  # Count notifications by channel
  echo "\nNotifications sent by channel:"
  echo &"  Email: {cast[TestChannel](emailChannel).sentNotifications.len}"
  echo &"  Slack: {cast[TestChannel](slackChannel).sentNotifications.len}"
  echo &"  Critical: {cast[TestChannel](criticalChannel).sentNotifications.len}"
  echo &"  Unreliable: {failingChannel.attemptCount} attempts"
  
  # Show notification details
  echo "\nEmail channel notifications:"
  for i, notif in cast[TestChannel](emailChannel).sentNotifications:
    echo &"  {i+1}. {notif.title} (Severity: {notif.severity})"
  
  echo "\nSlack channel notifications:"
  for i, notif in cast[TestChannel](slackChannel).sentNotifications:
    echo &"  {i+1}. {notif.title} (Severity: {notif.severity})"
  
  echo "\nExample completed successfully!"

when isMainModule:
  waitFor main()
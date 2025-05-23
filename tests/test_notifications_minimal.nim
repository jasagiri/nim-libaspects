## Minimal notification system test
import std/[unittest, json, times, tables, asyncdispatch]
import nim_libaspects/notifications

suite "Notification System - Minimal":
  
  test "Notification creation":
    let notification = newNotification(
      "Test Title", 
      "Test Message", 
      NotificationSeverity.nsInfo,
      %*{"key": "value"}
    )
    
    check notification.title == "Test Title"
    check notification.message == "Test Message"
    check notification.severity == NotificationSeverity.nsInfo
    check notification.metadata["key"].str == "value"
    check notification.id.len > 0
    check notification.status == NotificationStatus.nsPending
  
  test "Basic notification manager":
    let manager = newNotificationManager()
    let testChannel = newTestChannel("test")
    manager.addChannel(testChannel)
    
    let notification = newNotification("Test", "Message", NotificationSeverity.nsInfo)
    let results = waitFor manager.send(notification, @["test"])
    
    check results.len == 1
    check results[0].success
    check results[0].channelName == "test"
    
    # Check test channel received it
    check testChannel.sentNotifications.len == 1
    check testChannel.sentNotifications[0].id == notification.id
  
  test "Notification template":
    let tmpl = NotificationTemplate(
      name: "test_template",
      titleTemplate: "Hello {name}",
      messageTemplate: "Welcome {name}!",
      defaultSeverity: NotificationSeverity.nsInfo
    )
    
    let notification = tmpl.render(%*{"name": "John"})
    check notification.title == "Hello John"
    check notification.message == "Welcome John!"
  
  test "Email channel creation":
    let emailConfig = EmailConfig(
      host: "smtp.example.com",
      port: 587,
      username: "test@example.com",
      password: "password",
      useTLS: true,
      fromAddr: "noreply@example.com"
    )
    
    let channel = newEmailChannel(emailConfig)
    check channel.name == "email"
    check channel.config.host == "smtp.example.com"
  
  test "Retry mechanism":
    let manager = newNotificationManager()
    let failingChannel = newFailingChannel("test", failCount = 2)
    manager.addChannel(failingChannel)
    
    manager.setRetryPolicy(RetryPolicy(
      maxAttempts: 3,
      backoffMultiplier: 1.0,
      initialDelayMs: 10
    ))
    
    let notification = newNotification("Test", "Retry", NotificationSeverity.nsHigh)
    let results = waitFor manager.send(notification, @["test"])
    
    check results.len == 1
    check results[0].success  # Should succeed on 3rd attempt
    check results[0].attempts == 3
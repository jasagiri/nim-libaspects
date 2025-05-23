## tests/test_logging_metrics.nim
## ロギングとメトリクスの統合テスト

import std/[unittest, times, json, strformat, tables]
import nim_libaspects/[logging, metrics, logging_metrics]

suite "Logging with Metrics Integration":
  
  test "Basic logging with metrics":
    # Given: ロガーとメトリクスコレクターを作成
    let collector = newMetricsCollector()
    let logger = newMetricsLogger("test.metrics", collector)
    
    # When: メトリクスを統合したロギング
    logger.info("Request processed", %*{
      "duration_ms": 125,
      "status": "200",
      "method": "GET",
      "endpoint": "/api/users"
    })
    
    # Then: メトリクスが自動的に収集される
    let durationHist = collector.getHistogram("request_duration_ms")
    check durationHist.isSome
    # Basic auto-extraction should create the histogram
  
  test "Error logging with metrics":
    # Given: メトリクス統合ロガー
    let logger = newLogger("test.errors")
    let collector = newMetricsCollector()
    logger.attachMetrics(collector)
    
    # When: エラーをログ
    logger.error("Database connection failed", %*{
      "error": "connection_timeout",
      "retry_count": 3,
      "db_host": "db.example.com"
    })
    
    # Then: エラーメトリクスが更新される
    let errorCounter = collector.getCounter("errors_total")
    check errorCounter.isSome
    check errorCounter.get().getValue(["type", "connection_timeout"]) == 1
  
  test "Performance metrics in logs":
    # Given: パフォーマンス追跡付きロガー
    let logger = newLogger("test.performance")
    let collector = newMetricsCollector()
    logger.attachMetrics(collector)
    
    # When: パフォーマンスメトリクスを含むログ
    let timer = startTimer()
    # 何か処理...
    let duration = timer.elapsed()
    
    logger.info("Task completed", %*{
      "task": "data_processing",
      "duration_ms": duration.inMilliseconds,
      "records_processed": 1000,
      "memory_mb": 45.5
    })
    
    # Then: タイミングメトリクスが記録される
    let taskTimer = collector.getTimer("task_duration_ms")
    check taskTimer.isSome
    check taskTimer.get().getCount(["task", "data_processing"]) == 1
  
  test "Log level based metrics":
    # Given: レベル別メトリクス収集
    let logger = newLogger("test.levels")
    let collector = newMetricsCollector()
    logger.attachMetrics(collector)
    
    # When: 異なるレベルでログ
    logger.debug("Debug message")
    logger.info("Info message")
    logger.warn("Warning message")
    logger.error("Error message")
    
    # Then: レベル別カウンターが更新される
    let logCounter = collector.getCounter("logs_total")
    check logCounter.isSome
    check logCounter.get().getValue(["level", "debug"]) == 1
    check logCounter.get().getValue(["level", "info"]) == 1
    check logCounter.get().getValue(["level", "warn"]) == 1
    check logCounter.get().getValue(["level", "error"]) == 1
  
  test "Custom metrics extraction":
    # Given: カスタムメトリクス抽出設定
    let logger = newLogger("test.custom")
    let collector = newMetricsCollector()
    
    # カスタム抽出ルールを定義
    logger.attachMetrics(collector, MetricsConfig(
      extractors: @[
        MetricsExtractor(
          pattern: "request.*",
          counters: @["method", "status"],
          histograms: @["duration_ms"],
          gauges: @["active_connections"]
        ),
        MetricsExtractor(
          pattern: "cache.*",
          counters: @["operation"],
          gauges: @["size_mb", "hit_ratio"]
        )
      ]
    ))
    
    # When: パターンに一致するログ
    logger.info("request.complete", %*{
      "method": "POST",
      "status": 201,
      "duration_ms": 230,
      "active_connections": 15
    })
    
    logger.info("cache.stats", %*{
      "operation": "get",
      "size_mb": 128.5,
      "hit_ratio": 0.85
    })
    
    # Then: カスタムメトリクスが抽出される
    let requestDuration = collector.getHistogram("request_duration_ms")
    check requestDuration.isSome
    
    let cacheSize = collector.getGauge("cache_size_mb")
    check cacheSize.isSome
    check cacheSize.get().getValue() == 128.5
  
  test "Distributed tracing integration":
    # Given: 分散トレーシング対応ロガー
    let logger = newLogger("test.tracing")
    let collector = newMetricsCollector()
    logger.attachMetrics(collector)
    
    # When: トレース情報付きログ
    let traceId = "abc123"
    let spanId = "def456"
    
    logger.info("Service call", %*{
      "trace_id": traceId,
      "span_id": spanId,
      "service": "user-service",
      "operation": "getUser",
      "duration_ms": 45
    })
    
    # Then: トレースメトリクスが記録される
    let traceCounter = collector.getCounter("traces_total")
    check traceCounter.isSome
    check traceCounter.get().getValue(["service", "user-service"]) == 1
  
  test "Metrics middleware for logger":
    # Given: ミドルウェアとしてのメトリクス
    let logger = newLogger("test.middleware")
    let collector = newMetricsCollector()
    
    # メトリクスミドルウェアを追加
    logger.addMiddleware(proc(record: LogRecord): LogRecord =
      # 全てのログにタイムスタンプメトリクスを追加
      var newRecord = record
      newRecord.fields["metric_timestamp"] = %* epochTime()
      
      # レベルごとのカウンターを更新
      let counter = collector.getOrCreateCounter("log_levels_total", "Count of logs by level")
      counter.inc(@["level", $record.level])
      
      return newRecord
    )
    
    # When: ログを出力
    logger.info("Test message")
    
    # Then: ミドルウェアが実行される
    let levelCounter = collector.getCounter("log_levels_total")
    check levelCounter.isSome
    check levelCounter.get().getValue(["level", "INFO"]) == 1
  
  test "Metrics in structured logs":
    # Given: 構造化ログでのメトリクス
    let logger = newLogger("test.structured")
    let collector = newMetricsCollector()
    logger.attachMetrics(collector)
    
    # When: 構造化フィールドを含むログ
    logger.withFields(%*{
      "user_id": 123,
      "action": "login",
      "ip": "192.168.1.1"
    }).info("User login", %*{
      "success": true,
      "auth_method": "password",
      "duration_ms": 150
    })
    
    # Then: 構造化フィールドからメトリクスが抽出される
    let authCounter = collector.getCounter("auth_attempts_total")
    check authCounter.isSome
    check authCounter.get().getValue(["method", "password", "success", "true"]) == 1
  
  test "Real-time metrics dashboard":
    # Given: リアルタイムダッシュボード用メトリクス
    let logger = newLogger("test.dashboard")
    let collector = newMetricsCollector()
    logger.attachMetrics(collector)
    
    # When: 継続的なログとメトリクス
    for i in 1..10:
      logger.info(fmt"Request {i}", %*{
        "endpoint": "/api/data",
        "response_time_ms": i * 10,
        "status": if i mod 3 == 0: 500 else: 200
      })
    
    # Then: ダッシュボード用の集計データが利用可能
    let summary = collector.getSummary()
    check summary["http_requests_total"]["value"].getInt() == 10
    check summary["http_errors_total"]["value"].getInt() == 3
    check summary["response_time_ms"]["p99"].getFloat() > 0
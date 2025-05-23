## ファイル: tests/test_integration_reporting.nim
## 内容: レポーティングモジュールの統合テスト

import std/[unittest, json, tables, strutils, os, times]
import nim_libaspects/[reporting, metrics, logging]

# カスタムハンドラの定義
type CollectorHandler = ref object of LogHandler
  logs: ptr seq[string]

method handle(handler: CollectorHandler, record: LogRecord) =
  handler.logs[].add($record.level & ": " & record.message)

suite "Reporting Integration Tests":
  
  test "Integration with metrics module":
    # メトリクスの収集
    let registry = newMetricsRegistry()
    let counter = registry.counter("test.requests")
    let gauge = registry.gauge("test.memory")
    let histogram = registry.histogram("test.duration")
    
    # データの追加
    counter.inc()
    counter.inc()
    gauge.set(1024.0)
    histogram.observe(10.5)
    histogram.observe(20.3)
    histogram.observe(15.7)
    
    # レポートの生成
    var builder = newReportBuilder("Metrics Report")
    builder.addSection("Application Metrics")
    
    # カウンターメトリクス
    builder.addItem("Request Count", $counter.value, "Total requests processed")
    
    # ゲージメトリクス  
    builder.addItem("Memory Usage", $gauge.value & " MB", "Current memory consumption")
    
    # ヒストグラムメトリクス
    let stats = histogram.getStatistics()
    let avgDuration = if stats.count > 0: stats.mean else: 0.0
    builder.addItem("Average Duration", $avgDuration & " ms", "Response time average")
    
    let report = builder.build()
    check report.sections[0].items[0].value == "2.0"
    check report.sections[0].items[1].value == "1024.0 MB"
  
  test "Integration with logging module":
    # ログハンドラの設定
    let logger = newLogger("test")
    var logs: seq[string] = @[]
    
    # カスタムハンドラでログを収集
    let collector = CollectorHandler(logs: addr logs)
    logger.addHandler(collector)
    
    # ログの記録
    logger.info("Starting process")
    logger.warn("Low memory")
    logger.error("Connection failed")
    
    # ログレポートの生成
    var builder = newReportBuilder("Log Analysis Report")
    builder.addSection("Log Summary")
    
    var errorCount = 0
    var warningCount = 0
    var infoCount = 0
    
    for log in logs:
      if log.startsWith("ERROR"):
        inc(errorCount)
      elif log.startsWith("WARN"):
        inc(warningCount)
      elif log.startsWith("INFO"):
        inc(infoCount)
    
    builder.addItem("Total Logs", $logs.len)
    builder.addItem("Errors", $errorCount)
    builder.addItem("Warnings", $warningCount)
    builder.addItem("Info", $infoCount)
    
    # ログ詳細
    builder.addSection("Recent Logs")
    for log in logs:
      let parts = log.split(": ", 1)
      if parts.len == 2:
        builder.addItem(parts[0], parts[1])
    
    let report = builder.build()
    check report.sections[0].items[0].value == "3"
    check report.sections[0].items[1].value == "1"  # 1 error
    check report.sections[0].items[2].value == "1"  # 1 warning
  
  test "Combined metrics and logging report":
    # メトリクスとログを組み合わせた総合レポート
    let registry = newMetricsRegistry()
    let requestCounter = registry.counter("api.requests", @["endpoint", "status"])
    let responseTime = registry.histogram("api.response_time", @["endpoint"])
    
    # APIリクエストのシミュレーション
    requestCounter.inc(@["/users", "200"])
    requestCounter.inc(@["/users", "200"])
    requestCounter.inc(@["/users", "404"])
    requestCounter.inc(@["/products", "200"])
    requestCounter.inc(@["/products", "500"])
    
    responseTime.observe(125.0, @["/users"])
    responseTime.observe(89.0, @["/users"])
    responseTime.observe(234.0, @["/products"])
    
    # レポート生成
    var builder = newReportBuilder("API Performance Report")
    builder.setMetadata("period", "Last 24 hours")
    builder.setMetadata("service", "api-gateway")
    
    # サマリーセクション
    builder.addSection("Executive Summary")
    let totalRequests = requestCounter.value
    builder.addItem("Total API Requests", $totalRequests)
    
    # エンドポイント別の統計
    builder.addSection("Endpoint Statistics")
    let table = builder.beginTable(@["Endpoint", "Requests", "Avg Response Time"])
    table.addRow(@["/users", "3", "107.0 ms"])
    table.addRow(@["/products", "2", "234.0 ms"])
    table.endTable()
    
    # エラー分析
    builder.addSection("Error Analysis")
    builder.addItem("4xx Errors", "1", "Client errors")
    builder.addItem("5xx Errors", "1", "Server errors")
    
    let report = builder.build()
    
    # テンプレートを使用してHTMLレポートを生成
    let htmlFormatter = reporting.newHtmlFormatter()
    htmlFormatter.setTheme("dark")
    htmlFormatter.setStyle("dashboard")
    
    let html = htmlFormatter.format(report)
    check "API Performance Report" in html
    check "Executive Summary" in html
    check "Total API Requests" in html
  
  test "Progress reporting with metrics":
    # プログレスレポーターとメトリクスの組み合わせ
    let progressReporter = newProgressReporter("Data Processing Pipeline")
    let registry = newMetricsRegistry()
    let processedItems = registry.counter("pipeline.items_processed")
    let processingTime = registry.timer("pipeline.processing_time")
    
    # データ処理のシミュレーション
    progressReporter.beginTask("Data Loading")
    sleep(100)
    progressReporter.completeTask("Data Loading", "Loaded 10,000 records")
    
    progressReporter.beginTask("Data Transformation")
    let timer = processingTime.start()
    for i in 1..100:
      processedItems.inc()
      if i mod 25 == 0:
        progressReporter.updateProgress("Data Transformation", i, $i & " items processed")
        sleep(50)
    discard timer.stop()
    progressReporter.completeTask("Data Transformation", "Transformed " & $processedItems.value & " items")
    
    progressReporter.beginTask("Data Export")
    sleep(150)
    progressReporter.completeTask("Data Export", "Exported to database")
    
    # 統合レポートの生成
    let progressReport = progressReporter.generateReport()
    
    # 新しいアグリゲーターを使って統合
    let aggregator = newReportAggregator("Pipeline Execution Summary")
    aggregator.addReport(progressReport)
    
    # メトリクスレポートを別途作成
    var metricsBuilder = newReportBuilder("Performance Metrics")
    metricsBuilder.addSection("Performance Metrics")
    metricsBuilder.addItem("Total Items Processed", $processedItems.value)
    metricsBuilder.addItem("Average Processing Time", $(processingTime.averageTime()) & " ms/item")
    metricsBuilder.addItem("Total Processing Time", $(processingTime.totalTime()) & " ms")
    
    let metricsReport = metricsBuilder.build()
    aggregator.addReport(metricsReport)
    let finalReport = aggregator.aggregate()
    
    # レポートの検証
    check finalReport.sections.len >= 2
    check "Data Loading" in finalReport.sections[0].items[0].label
    check "Performance Metrics" in finalReport.sections[^1].title
    
    # JSONフォーマットでのエクスポート
    let jsonFormatter = reporting.newJsonFormatter()
    let jsonStr = jsonFormatter.format(finalReport)
    let jsonData = parseJson(jsonStr)
    
    check jsonData["title"].str == "Pipeline Execution Summary"
    check jsonData["sections"].len >= 2
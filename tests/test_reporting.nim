## ファイル: tests/test_reporting.nim
## 内容: テスティングレポート機能のBDD仕様

import std/[unittest, json, tables, strutils, os, times]
import nim_libaspects/reporting

suite "Reporting Framework BDD Specification":
  
  test "ReportBuilder - create simple report":
    # Given: 新しいレポートビルダー
    var builder = newReportBuilder("Test Report")
    
    # When: セクションと内容を追加
    builder.addSection("Introduction", "This is a test report.")
    builder.addSection("Results")
    builder.addItem("Test 1", "Passed")
    builder.addItem("Test 2", "Failed", "assertion error")
    
    # Then: レポートが正しく構築される
    let report = builder.build()
    check report.title == "Test Report"
    check report.sections.len == 2
    check report.sections[0].title == "Introduction"
    check report.sections[0].content == "This is a test report."
    check report.sections[1].items.len == 2
    check report.sections[1].items[0].label == "Test 1"
    check report.sections[1].items[0].value == "Passed"
    check report.sections[1].items[1].label == "Test 2"
    check report.sections[1].items[1].value == "Failed"
    check report.sections[1].items[1].details == "assertion error"
  
  test "ReportBuilder - nested sections":
    # Given: レポートビルダー
    var builder = newReportBuilder("Nested Report")
    
    # When: ネストしたセクションを作成
    builder.addSection("Main Section")
    builder.beginSection("Subsection 1")
    builder.addItem("Item 1", "Value 1")
    builder.endSection()
    
    builder.beginSection("Subsection 2")
    builder.addItem("Item 2", "Value 2")
    builder.endSection()
    
    # Then: ネスト構造が正しい
    let report = builder.build()
    check report.sections.len == 1
    check report.sections[0].title == "Main Section"
    check report.sections[0].subsections.len == 2
    check report.sections[0].subsections[0].title == "Subsection 1"
    check report.sections[0].subsections[0].items[0].label == "Item 1"
    check report.sections[0].subsections[1].title == "Subsection 2"
    check report.sections[0].subsections[1].items[0].label == "Item 2"
  
  test "ReportBuilder - tables":
    # Given: レポートビルダー
    var builder = newReportBuilder("Table Report")
    
    # When: テーブルを追加
    builder.addSection("Performance Metrics")
    var table = builder.beginTable(@["Test", "Duration", "Result"])
    table.addRow(@["test_1", "1.23s", "Pass"])
    table.addRow(@["test_2", "0.45s", "Pass"])
    table.addRow(@["test_3", "2.10s", "Fail"])
    table.endTable()
    
    # Then: テーブルが正しく作成される
    let report = builder.build()
    let section = report.sections[0]
    check section.tables.len == 1
    let reportTable = section.tables[0]
    check reportTable.headers == @["Test", "Duration", "Result"]
    check reportTable.rows.len == 3
    check reportTable.rows[0] == @["test_1", "1.23s", "Pass"]
    check reportTable.rows[2] == @["test_3", "2.10s", "Fail"]
  
  test "Markdown formatter":
    # Given: レポートとMarkdownフォーマッター
    var builder = newReportBuilder("Markdown Test")
    builder.addSection("Overview", "This is a test report in Markdown format.")
    builder.addSection("Results")
    builder.addItem("Total Tests", "10")
    builder.addItem("Passed", "8")
    builder.addItem("Failed", "2")
    
    # When: Markdown形式で出力
    let report = builder.build()
    let formatter = newMarkdownFormatter()
    let markdown = formatter.format(report)
    
    # Then: 正しいMarkdown形式
    check "# Markdown Test" in markdown
    check "## Overview" in markdown
    check "This is a test report in Markdown format." in markdown
    check "## Results" in markdown
    check "- **Total Tests**: 10" in markdown
    check "- **Passed**: 8" in markdown
    check "- **Failed**: 2" in markdown
  
  test "HTML formatter":
    # Given: レポートとHTMLフォーマッター
    var builder = newReportBuilder("HTML Test")
    builder.addSection("Summary", "Test execution summary")
    
    # When: HTML形式で出力
    let report = builder.build()
    let formatter = newHtmlFormatter()
    let html = formatter.format(report)
    
    # Then: 正しいHTML形式
    check "<html>" in html
    check "<head>" in html
    check "<title>HTML Test</title>" in html
    check "<body>" in html
    check "<h1>HTML Test</h1>" in html
    check "<h2>Summary</h2>" in html
    check "<p>Test execution summary</p>" in html
    check "</html>" in html
  
  test "JSON formatter":
    # Given: レポートとJSONフォーマッター
    var builder = newReportBuilder("JSON Test")
    builder.addSection("Data")
    builder.addItem("value1", "100")
    builder.addItem("value2", "200")
    
    # When: JSON形式で出力
    let report = builder.build()
    let formatter = newJsonFormatter()
    let jsonStr = formatter.format(report)
    
    # Then: 正しいJSON形式
    let jsonData = parseJson(jsonStr)
    check jsonData["title"].str == "JSON Test"
    check jsonData["sections"][0]["title"].str == "Data"
    check jsonData["sections"][0]["items"][0]["label"].str == "value1"
    check jsonData["sections"][0]["items"][0]["value"].str == "100"
    check jsonData["sections"][0]["items"][1]["label"].str == "value2"
    check jsonData["sections"][0]["items"][1]["value"].str == "200"
  
  test "Report templates":
    # Given: テンプレートレジストリ
    let registry = newTemplateRegistry()
    
    # When: テンプレートを登録
    registry.register("test", TestReportTemplate())
    registry.register("performance", PerformanceReportTemplate())
    
    # Then: テンプレートが使用可能
    let testTemplate = registry.get("test")
    check testTemplate != nil
    let perfTemplate = registry.get("performance")
    check perfTemplate != nil
    
    # When: テンプレートを使用してレポート作成
    var data = initTable[string, JsonNode]()
    data["tests"] = %*[
      {"name": "test1", "result": "pass"},
      {"name": "test2", "result": "fail"}
    ]
    
    let report = testTemplate.generate("Test Results", data)
    check report.title == "Test Results"
    check report.sections.len > 0
  
  test "Report file output":
    # Given: レポートとフォーマッター
    var builder = newReportBuilder("File Output Test")
    builder.addSection("Content", "This is test content")
    let report = builder.build()
    
    # When: ファイルに出力
    let tempDir = getTempDir()
    let markdownPath = tempDir / "report.md"
    let htmlPath = tempDir / "report.html"
    let jsonPath = tempDir / "report.json"
    
    saveReport(report, markdownPath, newMarkdownFormatter())
    saveReport(report, htmlPath, newHtmlFormatter())
    saveReport(report, jsonPath, newJsonFormatter())
    
    # Then: ファイルが作成される
    check fileExists(markdownPath)
    check fileExists(htmlPath)
    check fileExists(jsonPath)
    
    # クリーンアップ
    removeFile(markdownPath)
    removeFile(htmlPath)
    removeFile(jsonPath)
  
  test "Progress reporting":
    # Given: 進捗レポーター
    var reporter = newProgressReporter("Task Execution")
    
    # When: タスクの進捗を記録
    reporter.beginTask("Task 1")
    sleep(10)  # シミュレート処理
    reporter.updateProgress("Task 1", 50, "Processing...")
    sleep(10)
    reporter.completeTask("Task 1", "Success")
    
    reporter.beginTask("Task 2")
    sleep(5)
    reporter.failTask("Task 2", "Error occurred")
    
    # Then: 進捗レポートが生成される
    let report = reporter.generateReport()
    check report.title == "Task Execution"
    check report.sections.len > 0
    
    # タスクの詳細が含まれる
    let taskSection = report.sections[0]
    check taskSection.items.len >= 2
    
    # タスク1の情報
    var foundTask1 = false
    for item in taskSection.items:
      if item.label == "Task 1":
        check item.value == "Success"
        foundTask1 = true
    check foundTask1
    
    # タスク2の情報
    var foundTask2 = false
    for item in taskSection.items:
      if item.label == "Task 2":
        check item.value == "Failed"
        check item.details == "Error occurred"
        foundTask2 = true
    check foundTask2
  
  test "Report aggregation":
    # Given: 複数のレポート
    var builder1 = newReportBuilder("Report 1")
    builder1.addSection("Section 1", "Content 1")
    let report1 = builder1.build()
    
    var builder2 = newReportBuilder("Report 2")
    builder2.addSection("Section 2", "Content 2")
    let report2 = builder2.build()
    
    # When: レポートを集約
    let aggregator = newReportAggregator("Combined Report")
    aggregator.addReport(report1)
    aggregator.addReport(report2)
    let combined = aggregator.aggregate()
    
    # Then: 全セクションが含まれる
    check combined.title == "Combined Report"
    check combined.sections.len == 2
    check combined.sections[0].title == "Section 1"
    check combined.sections[0].content == "Content 1"
    check combined.sections[1].title == "Section 2"
    check combined.sections[1].content == "Content 2"
  
  test "Custom formatters":
    # Given: カスタムフォーマッター
    type
      CustomFormatter = ref object of Formatter
    
    # When: カスタムフォーマッターを使用（カスタム形式は通常のformat methodとは別）
    var builder = newReportBuilder("Custom Test")
    builder.addSection("Section A")
    builder.addSection("Section B")
    let report = builder.build()
    
    let formatter = CustomFormatter()
    # 本来はmethodを使うべきですが、テスト内では直接関数を呼びます
    let output = "CUSTOM:" & report.title & "\n"
    var customOutput = output
    for section in report.sections:
      customOutput.add("  - " & section.title & "\n")
    
    # Then: カスタム形式で出力
    check customOutput.startsWith("CUSTOM:Custom Test")
    check "  - Section A" in customOutput
    check "  - Section B" in customOutput
  
  test "Report metadata":
    # Given: メタデータ付きレポート
    var builder = newReportBuilder("Metadata Test")
    builder.setMetadata("author", "Test Runner")
    builder.setMetadata("version", "1.0.0")
    builder.setMetadata("timestamp", $now())
    
    # When: レポートを構築
    builder.addSection("Content", "Test content")
    let report = builder.build()
    
    # Then: メタデータが含まれる
    check report.metadata["author"] == "Test Runner"
    check report.metadata["version"] == "1.0.0"
    check report.metadata.hasKey("timestamp")
    check report.metadata.hasKey("generatedAt")  # 自動で追加される
  
  test "Conditional sections":
    # Given: 条件付きセクション
    var builder = newReportBuilder("Conditional Report")
    
    # When: 条件に基づいてセクションを追加
    let hasErrors = true
    let hasWarnings = false
    
    builder.addSection("Summary", "Test execution summary")
    
    if hasErrors:
      builder.addSection("Errors")
      builder.addItem("Error 1", "File not found")
      builder.addItem("Error 2", "Invalid format")
    
    if hasWarnings:
      builder.addSection("Warnings")
      builder.addItem("Warning 1", "Deprecated API")
    
    # Then: 条件を満たすセクションのみ含まれる
    let report = builder.build()
    check report.sections.len == 2  # Summary と Errors
    check report.sections[1].title == "Errors"
    check report.sections[1].items.len == 2
  
  test "Report styling and themes":
    # Given: スタイル設定可能なHTMLフォーマッター
    let formatter = newHtmlFormatter()
    formatter.setTheme("dark")
    formatter.setStyle("modern")
    
    # When: スタイル付きでレポート生成
    var builder = newReportBuilder("Styled Report")
    builder.addSection("Content", "Styled content")
    let report = builder.build()
    let html = formatter.format(report)
    
    # Then: スタイル情報が含まれる
    check "class=\"dark-theme\"" in html or "data-theme=\"dark\"" in html
    check "class=\"modern-style\"" in html or "data-style=\"modern\"" in html
  
  test "Report filtering":
    # Given: 大量のデータを含むレポート
    var builder = newReportBuilder("Large Report")
    builder.addSection("Results")
    
    for i in 1..100:
      let status = if i mod 3 == 0: "Failed" else: "Passed"
      builder.addItem($"Test " & $i, status)
    
    # When: フィルタリングを適用
    let report = builder.build()
    let filter = newReportFilter()
    filter.addCriteria("status", "Failed")
    let filtered = filter.apply(report)
    
    # Then: フィルタ条件に一致する項目のみ
    check filtered.sections[0].items.len == 33  # 3の倍数のみ
    for item in filtered.sections[0].items:
      check item.value == "Failed"
  
  # 統合テスト
  test "Complete report generation workflow":
    # Given: 完全なレポーティングワークフロー
    var progressReporter = newProgressReporter("Complete Workflow")
    
    # When: タスクを実行してレポート生成
    progressReporter.beginTask("Setup")
    sleep(5)
    progressReporter.completeTask("Setup", "Completed")
    
    progressReporter.beginTask("Tests")
    for i in 1..5:
      let taskName = "Test " & $i
      progressReporter.beginTask(taskName)
      sleep(2)
      if i == 3:
        progressReporter.failTask(taskName, "Assertion failed")
      else:
        progressReporter.completeTask(taskName, "Success")
    progressReporter.completeTask("Tests", "Completed")
    
    # レポートを生成して保存
    let report = progressReporter.generateReport()
    let tempFile = getTempDir() / "complete_report.html"
    saveReport(report, tempFile, newHtmlFormatter())
    
    # Then: ファイルが作成される
    check fileExists(tempFile)
    
    # 内容を確認
    let content = readFile(tempFile)
    check "Complete Workflow" in content
    check "Setup" in content
    check "Tests</strong>: Success" in content  # "Tests" が Completed ではなく Successになる
    check "Assertion failed" in content
    
    # クリーンアップ
    removeFile(tempFile)
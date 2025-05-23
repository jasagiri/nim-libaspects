## ファイル: tests/test_reporting_coverage.nim
## 内容: レポーティングモジュールの追加カバレッジテスト

import std/[unittest, json, tables, strutils, os, tempfiles]
import nim_libaspects/reporting

suite "Reporting Module - Coverage Tests":
  
  test "Edge cases - empty reports":
    # 空のレポート
    var builder = newReportBuilder("Empty Report")
    let report = builder.build()
    
    check report.title == "Empty Report"
    check report.sections.len == 0
    check report.metadata.hasKey("generatedAt")
    
    # フォーマッターで出力
    let markdown = newMarkdownFormatter().format(report)
    check "# Empty Report" in markdown
  
  test "Edge cases - special characters":
    # 特殊文字を含むレポート
    var builder = newReportBuilder("Report & Test < > \"quotes\"")
    builder.addSection("Section & Test", "Content with <special> \"characters\" & apostrophe's")
    builder.addItem("Label & 'test'", "Value < > \"test\"", "Details & \"more\"")
    
    let report = builder.build()
    
    # HTML エスケープが正しく行われる
    let html = newHtmlFormatter().format(report)
    check "&amp;" in html
    check "&lt;" in html
    check "&gt;" in html
    check "&quot;" in html
    check "&#39;" in html
  
  test "Deep nesting":
    # 深いネスト構造のレポート
    var builder = newReportBuilder("Deep Nesting")
    builder.addSection("Level 1")
    
    for i in 1..3:
      builder.beginSection($"Level 2-" & $i)
      for j in 1..2:
        builder.beginSection($"Level 3-" & $i & "-" & $j)
        builder.addItem($"Item-" & $i & "-" & $j, $"Value")
        builder.endSection()
      builder.endSection()
    
    let report = builder.build()
    
    # 構造が正しい
    check report.sections[0].title == "Level 1"
    check report.sections[0].subsections.len == 3
    check report.sections[0].subsections[0].subsections.len == 2
    check report.sections[0].subsections[0].subsections[0].items[0].label == "Item-1-1"
  
  test "Large data sets":
    # 大量のデータを含むレポート
    var builder = newReportBuilder("Large Report")
    builder.addSection("Performance Results")
    
    let table = builder.beginTable(@["ID", "Name", "Score", "Status"])
    for i in 1..1000:
      table.addRow(@[$i, $"Test " & $i, $(90 + i mod 10), if i mod 7 == 0: "Failed" else: "Passed"])
    table.endTable()
    
    let report = builder.build()
    
    check report.sections[0].tables[0].rows.len == 1000
    
    # フォーマット可能か確認
    let markdown = newMarkdownFormatter().format(report)
    check markdown.len > 10000  # 十分な長さがある
  
  test "Custom metadata validation":
    # カスタムメタデータの検証
    var builder = newReportBuilder("Metadata Test")
    builder.setMetadata("version", "1.2.3")
    builder.setMetadata("environment", "production")
    builder.setMetadata("build_number", "456")
    
    let report = builder.build()
    
    check report.metadata["version"] == "1.2.3"
    check report.metadata["environment"] == "production"
    check report.metadata["build_number"] == "456"
    check report.metadata.hasKey("generatedAt")
  
  test "Progress reporter - concurrent tasks":
    # 同時実行タスクのテスト
    var reporter = newProgressReporter("Concurrent Test")
    
    # 複数タスクを同時に開始
    reporter.beginTask("Task A")
    reporter.beginTask("Task B")
    reporter.beginTask("Task C")
    
    # 進捗更新
    reporter.updateProgress("Task A", 50, "Processing...")
    reporter.updateProgress("Task B", 30, "Loading data...")
    
    # タスク完了（異なる順序）
    reporter.completeTask("Task B", "Done")
    reporter.failTask("Task C", "Network error")
    reporter.completeTask("Task A", "Success")
    
    let report = reporter.generateReport()
    
    check report.sections.len > 0
    
    # 全タスクが含まれる
    let items = report.sections[0].items
    check items.len == 3
  
  test "Template system - error handling":
    # テンプレートエラーハンドリング
    let registry = newTemplateRegistry()
    
    # 存在しないテンプレート
    let tmpl = registry.get("nonexistent")
    check tmpl == nil
    
    # ベースメソッド呼び出し
    let baseTmpl = ReportTemplate()
    
    expect CatchableError:
      discard baseTmpl.generate("Test", initTable[string, JsonNode]())
  
  test "Filter combination":
    # 複数フィルター条件の組み合わせ
    var builder = newReportBuilder("Filter Test")
    builder.addSection("Results")
    
    for i in 1..20:
      let status = if i mod 3 == 0: "Failed" elif i mod 5 == 0: "Warning" else: "Passed"
      builder.addItem($"Test " & $i, status, $"Priority: " & $(i mod 4))
    
    let report = builder.build()
    let filter = newReportFilter()
    
    # Failed のみフィルター
    filter.addCriteria("status", "Failed")
    let filtered = filter.apply(report)
    
    var failedCount = 0
    for item in filtered.sections[0].items:
      if item.value == "Failed":
        inc(failedCount)
    
    check failedCount > 0
    check filtered.sections[0].items.len == failedCount
  
  test "Table edge cases":
    # テーブルの境界ケース
    var builder = newReportBuilder("Table Edge Cases")
    builder.addSection("Tests")
    
    # 空のテーブル
    let emptyTable = builder.beginTable(@["Col1", "Col2"])
    emptyTable.endTable()
    
    # 長いヘッダー名
    let longHeaders = builder.beginTable(@["Very Long Header Name That Might Cause Issues", "A", "B"])
    longHeaders.addRow(@["Value 1", "2", "3"])
    longHeaders.endTable()
    
    # 特殊文字を含むセル
    let specialTable = builder.beginTable(@["Name", "Value"])
    specialTable.addRow(@["Test | Pipe", "Value & Special"])
    specialTable.addRow(@["Line\nBreak", "Tab\tChar"])
    specialTable.endTable()
    
    let report = builder.build()
    
    check report.sections[0].tables.len == 3
    check report.sections[0].tables[0].rows.len == 0  # 空のテーブル
    check report.sections[0].tables[1].headers[0].len > 30  # 長いヘッダー
    check "|" in report.sections[0].tables[2].rows[0][0]  # 特殊文字
  
  test "HTML theme and style":
    # HTMLテーマとスタイルの詳細テスト
    let formatter = newHtmlFormatter()
    
    # 異なるテーマ設定
    formatter.setTheme("dark")
    formatter.setStyle("compact")
    
    var builder = newReportBuilder("Styled Report")
    builder.addSection("Content")
    builder.addItem("Key", "Value")
    
    let report = builder.build()
    let html = formatter.format(report)
    
    check "data-theme=\"dark\"" in html
    check "data-style=\"compact\"" in html
  
  test "Report aggregation - metadata handling":
    # レポート集約時のメタデータ処理
    var builder1 = newReportBuilder("Report 1")
    builder1.setMetadata("source", "system1")
    builder1.addSection("Data 1")
    let report1 = builder1.build()
    
    var builder2 = newReportBuilder("Report 2")
    builder2.setMetadata("source", "system2")
    builder2.addSection("Data 2")
    let report2 = builder2.build()
    
    let aggregator = newReportAggregator("Combined")
    aggregator.addReport(report1)
    aggregator.addReport(report2)
    let combined = aggregator.aggregate()
    
    # メタデータは新しく生成される
    check combined.metadata.hasKey("generatedAt")
    check combined.sections.len == 2
    check combined.sections[0].title == "Data 1"
    check combined.sections[1].title == "Data 2"
  
  test "File output - error handling":
    # ファイル出力のエラーハンドリング
    var builder = newReportBuilder("File Error Test")
    builder.addSection("Test")
    let report = builder.build()
    
    # 無効なパスへの保存を試行
    let invalidPath = "/invalid/path/that/does/not/exist/report.html"
    
    expect IOError:
      saveReport(report, invalidPath, newHtmlFormatter())
  
  test "JSON formatter - complex structures":
    # 複雑な構造のJSON出力
    var builder = newReportBuilder("Complex JSON")
    builder.setMetadata("version", "2.0")
    builder.addSection("Main")
    builder.addItem("Simple", "Value")
    
    builder.beginSection("Nested")
    let table = builder.beginTable(@["A", "B"])
    table.addRow(@["1", "2"])
    table.endTable()
    builder.endSection()
    
    let report = builder.build()
    let jsonStr = newJsonFormatter().format(report)
    let json = parseJson(jsonStr)
    
    # JSON構造の検証
    check json["title"].str == "Complex JSON"
    check json["metadata"]["version"].str == "2.0"
    check json["sections"][0]["subsections"][0]["tables"][0]["rows"][0][0].str == "1"
  
  test "Memory management - large reports":
    # 大規模レポートのメモリ管理
    when not defined(js):  # JavaScriptバックエンドではスキップ
      var builder = newReportBuilder("Memory Test")
      builder.addSection("Large Data")
      
      # 大量のアイテムを追加
      for i in 1..10000:
        builder.addItem($"Item " & $i, $"Value " & $i)
      
      let report = builder.build()
      
      # GCを明示的に実行
      GC_fullCollect()
      
      # レポートが正しく構築されている
      check report.sections[0].items.len == 10000
      
      # 各フォーマッターでも問題なく処理できる
      let markdown = newMarkdownFormatter().format(report)
      let html = newHtmlFormatter().format(report)
      let json = newJsonFormatter().format(report)
      
      check markdown.len > 100000
      check html.len > 100000
      check json.len > 100000

  # テンプレートの宣言的な使用法
  template testReportGeneration(name: string, setup: untyped, check: untyped) =
    test name:
      var builder {.inject.} = newReportBuilder(name)
      setup
      let report {.inject.} = builder.build()
      check
  
  testReportGeneration "Declarative test 1":
    builder.addSection("Test Section")
    builder.addItem("Key", "Value")
  do:
    check report.sections.len == 1
    check report.sections[0].items[0].label == "Key"
  
  testReportGeneration "Declarative test 2":
    builder.setMetadata("test", "true")
    builder.addSection("Empty")
  do:
    check report.metadata["test"] == "true"
    check report.sections[0].items.len == 0
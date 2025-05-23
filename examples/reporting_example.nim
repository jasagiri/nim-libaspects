## ファイル: examples/reporting_example.nim
## 内容: レポーティングフレームワークの使用例

import std/[json, tables, strutils, times, os, random]
import nim_libaspects/reporting

# サンプルデータの生成
proc generateSampleData(): seq[tuple[name: string, status: string, duration: float, error: string]] =
  randomize()
  result = @[]
  
  for i in 1..50:
    let name = "test_" & $i
    let duration = rand(100) / 10.0
    let status = if rand(10) > 2: "passed" else: "failed"
    let error = if status == "failed": "Assertion error at line " & $rand(1000) else: ""
    
    result.add((name: name, status: status, duration: duration, error: error))

# メインのレポート生成
proc generateTestExecutionReport(): Report =
  echo "Generating test execution report..."
  
  var builder = newReportBuilder("Test Execution Report")
  
  # メタデータの設定
  builder.setMetadata("generated_by", "reporting_example")
  builder.setMetadata("version", "1.0.0")
  builder.setMetadata("environment", "development")
  builder.setMetadata("run_id", $rand(100000))
  
  # サマリーセクション
  builder.addSection("Executive Summary", "Automated test execution results for the current build")
  
  # テストデータの生成
  let testData = generateSampleData()
  let passed = testData.filterIt(it.status == "passed").len
  let failed = testData.filterIt(it.status == "failed").len
  let totalDuration = testData.mapIt(it.duration).foldl(a + b)
  
  # 統計セクション
  builder.addSection("Test Statistics")
  builder.addItem("Total Tests", $testData.len)
  builder.addItem("Passed", $passed, $(passed.float / testData.len.float * 100) & "%" )
  builder.addItem("Failed", $failed, $(failed.float / testData.len.float * 100) & "%")
  builder.addItem("Total Duration", $totalDuration & "s")
  builder.addItem("Average Duration", $(totalDuration / testData.len.float) & "s")
  
  # 結果テーブル
  builder.addSection("Detailed Results")
  let table = builder.beginTable(@["Test Name", "Status", "Duration (s)", "Error"])
  
  for test in testData:
    table.addRow(@[test.name, test.status, $test.duration, test.error])
  
  table.endTable()
  
  # 失敗したテストの詳細
  if failed > 0:
    builder.addSection("Failed Tests Detail")
    for test in testData:
      if test.status == "failed":
        builder.addItem(test.name, "Failed", test.error)
  
  # パフォーマンス分析
  builder.addSection("Performance Analysis")
  let slowTests = testData.filterIt(it.duration > 5.0)
  
  if slowTests.len > 0:
    builder.beginSection("Slow Tests (>5s)")
    for test in slowTests:
      builder.addItem(test.name, $test.duration & "s")
    builder.endSection()
  
  # グラフデータ（実際のグラフではなく、データの準備）
  builder.addSection("Test Duration Distribution")
  var distribution = initTable[string, int]()
  for test in testData:
    let bucket = if test.duration < 1.0: "<1s"
                elif test.duration < 3.0: "1-3s"
                elif test.duration < 5.0: "3-5s"
                else: ">5s"
    distribution[bucket] = distribution.getOrDefault(bucket, 0) + 1
  
  for bucket, count in distribution:
    builder.addItem(bucket, $count & " tests")
  
  result = builder.build()

# 進捗レポートのデモ
proc demonstrateProgressReporting() =
  echo "\nDemonstrating progress reporting..."
  
  var reporter = newProgressReporter("Build and Test Process")
  
  # ビルドプロセス
  reporter.beginTask("Compilation")
  echo "  Starting compilation..."
  sleep(1000)  # シミュレート
  reporter.updateProgress("Compilation", 50, "Compiling source files...")
  sleep(1000)
  reporter.completeTask("Compilation", "Successfully compiled 156 files")
  
  # テストプロセス
  reporter.beginTask("Unit Tests")
  echo "  Running unit tests..."
  sleep(800)
  reporter.updateProgress("Unit Tests", 30, "Running test suite 1/3...")
  sleep(800)
  reporter.updateProgress("Unit Tests", 60, "Running test suite 2/3...")
  sleep(800)
  reporter.completeTask("Unit Tests", "All 245 tests passed")
  
  # 統合テスト
  reporter.beginTask("Integration Tests")
  echo "  Running integration tests..."
  sleep(1200)
  reporter.failTask("Integration Tests", "Database connection timeout")
  
  # デプロイメント
  reporter.beginTask("Deployment")
  echo "  Deploying to staging..."
  sleep(1500)
  reporter.completeTask("Deployment", "Successfully deployed to staging environment")
  
  # レポート生成
  let progressReport = reporter.generateReport()
  
  # 各フォーマットで保存
  echo "  Saving progress reports..."
  saveReport(progressReport, "progress_report.md", newMarkdownFormatter())
  saveReport(progressReport, "progress_report.html", newHtmlFormatter())
  echo "  Progress reports saved"

# レポート集約のデモ
proc demonstrateReportAggregation() =
  echo "\nDemonstrating report aggregation..."
  
  # 個別のレポートを生成
  var dailyReports: seq[Report] = @[]
  
  for day in 1..7:
    var builder = newReportBuilder("Day " & $day & " Report")
    builder.addSection("Summary")
    builder.addItem("Tests Run", $(50 + rand(20)))
    builder.addItem("Bugs Found", $(rand(5)))
    builder.addItem("Features Completed", $(rand(3) + 1))
    dailyReports.add(builder.build())
  
  # レポートを集約
  let aggregator = newReportAggregator("Weekly Summary Report")
  for report in dailyReports:
    aggregator.addReport(report)
  
  let weeklyReport = aggregator.aggregate()
  
  # 保存
  saveReport(weeklyReport, "weekly_summary.html", newHtmlFormatter())
  echo "  Weekly summary report saved"

# カスタムフォーマッターのデモ
type
  CsvFormatter = ref object of Formatter

method format*(formatter: CsvFormatter, report: Report): string =
  result = "Title,Section,Item,Value,Details\n"
  
  for section in report.sections:
    for item in section.items:
      result.add("\"" & report.title & "\",")
      result.add("\"" & section.title & "\",")
      result.add("\"" & item.label & "\",")
      result.add("\"" & item.value & "\",")
      result.add("\"" & item.details & "\"\n")

proc demonstrateCustomFormatter() =
  echo "\nDemonstrating custom formatter..."
  
  var builder = newReportBuilder("Sales Report")
  builder.addSection("Q1 Sales")
  builder.addItem("Product A", "$45,000", "15% increase")
  builder.addItem("Product B", "$32,000", "5% decrease")
  builder.addItem("Product C", "$28,000", "New product")
  
  let report = builder.build()
  
  # カスタムCSVフォーマッターを使用
  let csvFormatter = CsvFormatter()
  saveReport(report, "sales_report.csv", csvFormatter)
  echo "  Custom CSV report saved"

# フィルタリングのデモ
proc demonstrateFiltering() =
  echo "\nDemonstrating report filtering..."
  
  var builder = newReportBuilder("All Tests Report")
  builder.addSection("Test Results")
  
  # 様々なステータスのテストを追加
  for i in 1..30:
    let status = case i mod 4
      of 0: "Failed"
      of 1: "Passed"
      of 2: "Skipped"
      else: "Pending"
    
    builder.addItem("Test " & $i, status, "Duration: " & $(rand(100) / 10.0) & "s")
  
  let fullReport = builder.build()
  
  # Failed テストのみをフィルター
  let filter = newReportFilter()
  filter.addCriteria("status", "Failed")
  let failedOnlyReport = filter.apply(fullReport)
  
  # 両方のレポートを保存
  saveReport(fullReport, "all_tests.html", newHtmlFormatter())
  saveReport(failedOnlyReport, "failed_tests.html", newHtmlFormatter())
  echo "  Filtered reports saved"

# メインプログラム
proc main() =
  echo "Reporting Framework Demonstration"
  echo "================================\n"
  
  # 出力ディレクトリの作成
  if not dirExists("reports"):
    createDir("reports")
  
  # カレントディレクトリを変更
  setCurrentDir("reports")
  
  # 基本的なレポート生成
  let testReport = generateTestExecutionReport()
  
  # 各フォーマッターでレポートを保存
  echo "\nSaving reports in different formats..."
  
  # Markdown
  let markdownFormatter = newMarkdownFormatter()
  saveReport(testReport, "test_report.md", markdownFormatter)
  echo "  Markdown report saved: test_report.md"
  
  # HTML (テーマ付き)
  let htmlFormatter = newHtmlFormatter()
  htmlFormatter.setTheme("dark")
  htmlFormatter.setStyle("modern")
  saveReport(testReport, "test_report_dark.html", htmlFormatter)
  echo "  HTML report saved: test_report_dark.html"
  
  # JSON
  let jsonFormatter = newJsonFormatter()
  saveReport(testReport, "test_report.json", jsonFormatter)
  echo "  JSON report saved: test_report.json"
  
  # その他のデモ
  demonstrateProgressReporting()
  demonstrateReportAggregation()
  demonstrateCustomFormatter()
  demonstrateFiltering()
  
  # 元のディレクトリに戻る
  setCurrentDir("..")
  
  echo "\nAll demonstrations completed!"
  echo "Check the 'reports' directory for generated files."

when isMainModule:
  main()
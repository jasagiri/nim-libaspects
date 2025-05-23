# Reporting Framework

`nim_libaspects/reporting` モジュールは、構造化されたレポートの生成、フォーマット、および管理のための包括的なフレームワークを提供します。

## 概要

Reporting Framework は以下の主要な機能を提供します：

- **レポートビルダー**: 階層的な構造を持つレポートの構築
- **多様なフォーマッター**: Markdown、HTML、JSON形式での出力
- **テンプレートシステム**: 再利用可能なレポート構造の定義
- **進捗レポーティング**: タスクの実行状況の追跡とレポート生成
- **レポート集約**: 複数のレポートの統合
- **フィルタリング**: 条件に基づくレポート内容のフィルタリング

## 基本的な使用法

### レポートの作成

```nim
import nim_libaspects/reporting

# レポートビルダーの作成
var builder = newReportBuilder("Monthly Report")

# メタデータの追加
builder.setMetadata("author", "John Doe")
builder.setMetadata("department", "Engineering")

# セクションの追加
builder.addSection("Executive Summary", "This month's performance overview")

# アイテムの追加
builder.addSection("Key Metrics")
builder.addItem("Total Sales", "$1,234,567")
builder.addItem("Customer Satisfaction", "92%", "Up 3% from last month")

# レポートの構築
let report = builder.build()
```

### テーブルの追加

```nim
builder.addSection("Performance Data")

# テーブルの作成
let table = builder.beginTable(@["Product", "Units Sold", "Revenue"])
table.addRow(@["Product A", "1,234", "$12,340"])
table.addRow(@["Product B", "5,678", "$56,780"])
table.addRow(@["Product C", "910", "$9,100"])
table.endTable()
```

### ネストされたセクション

```nim
builder.addSection("Department Reports")

builder.beginSection("Engineering")
builder.addItem("Headcount", "45")
builder.addItem("Projects Completed", "12")
builder.endSection()

builder.beginSection("Sales")
builder.addItem("Headcount", "30")
builder.addItem("Deals Closed", "87")
builder.endSection()
```

## フォーマッター

### Markdown 出力

```nim
let formatter = newMarkdownFormatter()
let markdown = formatter.format(report)

# ファイルに保存
saveReport(report, "report.md", formatter)
```

### HTML 出力

```nim
let formatter = newHtmlFormatter()

# テーマとスタイルの設定
formatter.setTheme("dark")
formatter.setStyle("modern")

let html = formatter.format(report)
saveReport(report, "report.html", formatter)
```

### JSON 出力

```nim
let formatter = newJsonFormatter()
let json = formatter.format(report)
saveReport(report, "report.json", formatter)
```

## 進捗レポーティング

タスクの実行状況を追跡し、レポートを生成します：

```nim
# 進捗レポーターの作成
var reporter = newProgressReporter("Build Process")

# タスクの開始
reporter.beginTask("Compilation")
# ... 実際の処理 ...
reporter.updateProgress("Compilation", 50, "Processing source files...")
# ... さらに処理 ...
reporter.completeTask("Compilation", "Successfully compiled 156 files")

# 別のタスク
reporter.beginTask("Testing")
# ... テスト実行 ...
reporter.failTask("Testing", "3 tests failed")

# レポートの生成
let progressReport = reporter.generateReport()
```

## テンプレートシステム

再利用可能なレポート構造を定義します：

```nim
# テンプレートレジストリの作成
let registry = newTemplateRegistry()

# 標準テンプレートの登録
registry.register("test", TestReportTemplate())
registry.register("performance", PerformanceReportTemplate())

# テンプレートの使用
let template = registry.get("test")
var data = initTable[string, JsonNode]()
data["tests"] = %*[
  {"name": "test1", "result": "pass"},
  {"name": "test2", "result": "fail"}
]

let report = template.generate("Test Results", data)
```

## レポートの集約

複数のレポートを1つに統合します：

```nim
let aggregator = newReportAggregator("Quarterly Summary")

# 個別のレポートを追加
aggregator.addReport(januaryReport)
aggregator.addReport(februaryReport)
aggregator.addReport(marchReport)

# 統合レポートの生成
let quarterlyReport = aggregator.aggregate()
```

## フィルタリング

条件に基づいてレポート内容をフィルタリングします：

```nim
let filter = newReportFilter()

# フィルター条件の追加
filter.addCriteria("status", "Failed")

# フィルターの適用
let filteredReport = filter.apply(originalReport)
```

## 高度な機能

### カスタムフォーマッター

独自のフォーマッターを実装できます：

```nim
type
  CustomFormatter = ref object of Formatter

method format*(formatter: CustomFormatter, report: Report): string =
  # カスタムフォーマットロジック
  result = "Custom: " & report.title & "\n"
  for section in report.sections:
    result.add("- " & section.title & "\n")
```

### メタデータの活用

レポートには自動的にタイムスタンプが追加されます：

```nim
let report = builder.build()
echo report.metadata["generatedAt"]  # 生成時刻

# カスタムメタデータも追加可能
builder.setMetadata("version", "1.0.0")
builder.setMetadata("environment", "production")
```

### 大規模データの処理

大量のデータを含むレポートも効率的に処理できます：

```nim
# 1000行のテーブル
let table = builder.beginTable(@["ID", "Name", "Value"])
for i in 1..1000:
  table.addRow(@[$i, "Item " & $i, $(i * 100)])
table.endTable()
```

## エラーハンドリング

```nim
try:
  saveReport(report, "/invalid/path/report.html", formatter)
except IOError:
  echo "Failed to save report: ", getCurrentExceptionMsg()
```

## パフォーマンス考慮事項

- 大規模なレポート（10,000+ アイテム）の場合、メモリ使用量に注意
- HTMLフォーマッターは特殊文字を自動的にエスケープします
- JSONフォーマッターは完全な構造を保持します

## 統合例

### CI/CDパイプラインでの使用

```nim
import nim_libaspects/reporting

proc generateTestReport(results: seq[TestResult]): Report =
  var builder = newReportBuilder("Test Execution Report")
  builder.setMetadata("build_number", getBuildNumber())
  builder.setMetadata("branch", getGitBranch())
  
  builder.addSection("Test Summary")
  builder.addItem("Total Tests", $results.len)
  builder.addItem("Passed", $results.filterIt(it.passed).len)
  builder.addItem("Failed", $results.filterIt(not it.passed).len)
  
  builder.addSection("Failed Tests")
  for test in results:
    if not test.passed:
      builder.addItem(test.name, "Failed", test.error)
  
  result = builder.build()

# 使用例
let testResults = runTests()
let report = generateTestReport(testResults)
saveReport(report, "test-report.html", newHtmlFormatter())
```

### モニタリングシステムとの統合

```nim
import nim_libaspects/[reporting, metrics]

proc generateMetricsReport(registry: MetricsRegistry): Report =
  var builder = newReportBuilder("System Metrics Report")
  
  builder.addSection("Performance Metrics")
  
  # メトリクスからテーブルを生成
  let table = builder.beginTable(@["Metric", "Value", "Unit"])
  
  for name, metric in registry.getAllMetrics():
    case metric.kind
    of MetricKind.Counter:
      table.addRow(@[name, $metric.asCounter.value, "count"])
    of MetricKind.Gauge:
      table.addRow(@[name, $metric.asGauge.value, "value"])
    of MetricKind.Histogram:
      let hist = metric.asHistogram
      table.addRow(@[name & "_p95", $hist.percentile(0.95), "ms"])
    else:
      discard
  
  table.endTable()
  result = builder.build()
```

## ベストプラクティス

1. **構造化**: レポートは論理的なセクションに分割する
2. **メタデータ**: 重要なコンテキスト情報をメタデータとして含める
3. **エラーハンドリング**: ファイル操作時は常に例外処理を実装
4. **パフォーマンス**: 大規模データの場合はストリーミングを検討
5. **テンプレート**: 繰り返し使用するレポート形式はテンプレート化する

## まとめ

Reporting Framework は、Nim アプリケーションに強力で柔軟なレポート生成機能を提供します。シンプルなテキストレポートから複雑な構造化データまで、様々なレポーティングニーズに対応できます。
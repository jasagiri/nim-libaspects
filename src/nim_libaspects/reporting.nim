## ファイル: src/nim_libaspects/reporting.nim
## 内容: レポーティングフレームワーク実装

import std/[tables, json, strformat, strutils, times, locks, os, sequtils]

# レポート要素の型定義
type
  ReportItem* = object
    label*, value*: string
    details*: string
  
  ReportTable* = object
    headers*: seq[string]
    rows*: seq[seq[string]]
  
  ReportSection* = object
    title*: string
    content*: string
    items*: seq[ReportItem]
    tables*: seq[ReportTable]
    subsections*: seq[ReportSection]
  
  Report* = object
    title*: string
    metadata*: Table[string, string]
    sections*: seq[ReportSection]
  
  # レポートビルダー
  ReportBuilder* = ref object
    title: string
    metadata: Table[string, string]
    sections: seq[ReportSection]
    currentSection: ReportSection
    sectionStack: seq[ReportSection]
  
  # フォーマッターインターフェース
  Formatter* = ref object of RootObj
  
  # 組み込みフォーマッター
  MarkdownFormatter* = ref object of Formatter
  HtmlFormatter* = ref object of Formatter
    theme: string
    style: string
  JsonFormatter* = ref object of Formatter
  
  # テンプレートシステム
  ReportTemplate* = ref object of RootObj
  TestReportTemplate* = ref object of ReportTemplate
  PerformanceReportTemplate* = ref object of ReportTemplate
  
  TemplateRegistry* = ref object
    templates: Table[string, ReportTemplate]
  
  # 進捗レポーター
  TaskInfo = object
    name: string
    startTime: DateTime
    endTime: DateTime
    status: string
    details: string
    progress: int
  
  ProgressReporter* = ref object
    title: string
    tasks: seq[TaskInfo]
    currentTasks: Table[string, ptr TaskInfo]
    lock: Lock
  
  # レポート集約
  ReportAggregator* = ref object
    title: string
    reports: seq[Report]
  
  # レポートフィルター
  FilterCriteria = object
    field: string
    value: string
  
  ReportFilter* = ref object
    criteria: seq[FilterCriteria]
  
  # テーブルビルダー
  TableBuilder* = ref object
    headers: seq[string]
    rows: seq[seq[string]]
    builder: ReportBuilder

# レポートビルダー実装
proc newReportBuilder*(title: string): ReportBuilder =
  result = ReportBuilder(
    title: title,
    metadata: initTable[string, string](),
    sections: @[],
    currentSection: ReportSection(),
    sectionStack: @[]
  )

proc setMetadata*(builder: ReportBuilder, key, value: string) =
  builder.metadata[key] = value

proc addSection*(builder: ReportBuilder, title: string, content: string = "") =
  if builder.currentSection.title != "":
    builder.sections.add(builder.currentSection)
  builder.currentSection = ReportSection(
    title: title,
    content: content,
    items: @[],
    tables: @[],
    subsections: @[]
  )

proc beginSection*(builder: ReportBuilder, title: string) =
  let newSection = ReportSection(
    title: title,
    content: "",
    items: @[],
    tables: @[],
    subsections: @[]
  )
  builder.sectionStack.add(builder.currentSection)
  builder.currentSection = newSection

proc endSection*(builder: ReportBuilder) =
  if builder.sectionStack.len > 0:
    var parent = builder.sectionStack.pop()
    parent.subsections.add(builder.currentSection)
    builder.currentSection = parent

proc addItem*(builder: ReportBuilder, label, value: string, details: string = "") =
  builder.currentSection.items.add(ReportItem(
    label: label,
    value: value,
    details: details
  ))

proc beginTable*(builder: ReportBuilder, headers: seq[string]): TableBuilder =
  result = TableBuilder(
    headers: headers,
    rows: @[],
    builder: builder
  )

proc addRow*(table: TableBuilder, row: seq[string]) =
  table.rows.add(row)

proc endTable*(table: TableBuilder) =
  table.builder.currentSection.tables.add(ReportTable(
    headers: table.headers,
    rows: table.rows
  ))

proc build*(builder: ReportBuilder): Report =
  # 現在のセクションを追加
  if builder.currentSection.title != "":
    builder.sections.add(builder.currentSection)
  
  # メタデータに生成時刻を追加
  builder.metadata["generatedAt"] = $now()
  
  result = Report(
    title: builder.title,
    metadata: builder.metadata,
    sections: builder.sections
  )

# Markdownフォーマッター
proc newMarkdownFormatter*(): MarkdownFormatter =
  MarkdownFormatter()

proc formatSection(section: ReportSection, level: int = 2): string =
  let prefix = repeat("#", level) & " "
  result = prefix & section.title & "\n\n"
  
  if section.content != "":
    result.add(section.content & "\n\n")
  
  # アイテムのフォーマット
  for item in section.items:
    result.add(&"- **{item.label}**: {item.value}")
    if item.details != "":
      result.add(&" ({item.details})")
    result.add("\n")
  
  if section.items.len > 0:
    result.add("\n")
  
  # テーブルのフォーマット
  for table in section.tables:
    result.add("| " & table.headers.join(" | ") & " |\n")
    let separators = table.headers.mapIt("---")
    result.add("| " & separators.join(" | ") & " |\n")
    for row in table.rows:
      result.add("| " & row.join(" | ") & " |\n")
    result.add("\n")
  
  # サブセクションの再帰的フォーマット
  for subsection in section.subsections:
    result.add(formatSection(subsection, level + 1))

method format*(formatter: Formatter, report: Report): string {.base.} =
  raise newException(CatchableError, "Not implemented")

method format*(formatter: MarkdownFormatter, report: Report): string =
  result = &"# {report.title}\n\n"
  
  # メタデータ
  if report.metadata.len > 0:
    result.add("## Metadata\n\n")
    for key, value in report.metadata:
      result.add(&"- **{key}**: {value}\n")
    result.add("\n")
  
  # セクション
  for section in report.sections:
    result.add(formatSection(section))

# HTMLフォーマッター
proc newHtmlFormatter*(): HtmlFormatter =
  HtmlFormatter(theme: "light", style: "default")

proc setTheme*(formatter: HtmlFormatter, theme: string) =
  formatter.theme = theme

proc setStyle*(formatter: HtmlFormatter, style: string) =
  formatter.style = style

proc escapeHtml(s: string): string =
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&#39;")

proc formatSectionHtml(section: ReportSection, level: int = 2): string =
  let tagName = &"h{level}"
  result = &"<{tagName}>{escapeHtml(section.title)}</{tagName}>\n"
  
  if section.content != "":
    result.add(&"<p>{escapeHtml(section.content)}</p>\n")
  
  # アイテムのフォーマット
  if section.items.len > 0:
    result.add("<ul>\n")
    for item in section.items:
      result.add(&"<li><strong>{escapeHtml(item.label)}</strong>: {escapeHtml(item.value)}")
      if item.details != "":
        result.add(&" <em>({escapeHtml(item.details)})</em>")
      result.add("</li>\n")
    result.add("</ul>\n")
  
  # テーブルのフォーマット
  for table in section.tables:
    result.add("<table>\n<thead>\n<tr>\n")
    for header in table.headers:
      result.add(&"<th>{escapeHtml(header)}</th>\n")
    result.add("</tr>\n</thead>\n<tbody>\n")
    
    for row in table.rows:
      result.add("<tr>\n")
      for cell in row:
        result.add(&"<td>{escapeHtml(cell)}</td>\n")
      result.add("</tr>\n")
    result.add("</tbody>\n</table>\n")
  
  # サブセクション
  for subsection in section.subsections:
    result.add("<div class=\"subsection\">\n")
    result.add(formatSectionHtml(subsection, level + 1))
    result.add("</div>\n")

method format*(formatter: HtmlFormatter, report: Report): string =
  var themeAttr = ""
  var styleAttr = ""
  
  if formatter.theme != "light":
    themeAttr = &" data-theme=\"{formatter.theme}\""
  if formatter.style != "default":
    styleAttr = &" data-style=\"{formatter.style}\""
  
  result = &"""<!DOCTYPE html>
<html{themeAttr}{styleAttr}>
<head>
  <meta charset="UTF-8">
  <title>{escapeHtml(report.title)}</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 20px; }}
    table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
    th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
    th {{ background-color: #f2f2f2; }}
    .subsection {{ margin-left: 20px; }}
  </style>
</head>
<body>
  <h1>{escapeHtml(report.title)}</h1>
"""
  
  # メタデータ
  if report.metadata.len > 0:
    result.add("  <h2>Metadata</h2>\n  <ul>\n")
    for key, value in report.metadata:
      result.add(&"    <li><strong>{escapeHtml(key)}</strong>: {escapeHtml(value)}</li>\n")
    result.add("  </ul>\n")
  
  # セクション
  for section in report.sections:
    result.add(formatSectionHtml(section))
  
  result.add("</body>\n</html>")

# JSONフォーマッター
proc newJsonFormatter*(): JsonFormatter =
  JsonFormatter()

proc sectionToJson(section: ReportSection): JsonNode =
  result = %*{
    "title": section.title,
    "content": section.content,
    "items": %[],
    "tables": %[],
    "subsections": %[]
  }
  
  for item in section.items:
    let itemJson = %*{
      "label": item.label,
      "value": item.value
    }
    if item.details != "":
      itemJson["details"] = %item.details
    result["items"].add(itemJson)
  
  for table in section.tables:
    result["tables"].add(%*{
      "headers": %table.headers,
      "rows": %table.rows
    })
  
  for subsection in section.subsections:
    result["subsections"].add(sectionToJson(subsection))

method format*(formatter: JsonFormatter, report: Report): string =
  let jsonData = %*{
    "title": report.title,
    "metadata": %report.metadata,
    "sections": %[]
  }
  
  for section in report.sections:
    jsonData["sections"].add(sectionToJson(section))
  
  result = $jsonData

# ファイル保存
proc saveReport*(report: Report, path: string, formatter: Formatter) =
  let content = formatter.format(report)
  writeFile(path, content)

# テンプレートレジストリ
proc newTemplateRegistry*(): TemplateRegistry =
  result = TemplateRegistry()
  result.templates = initTable[string, ReportTemplate]()

proc register*(registry: TemplateRegistry, name: string, tmpl: ReportTemplate) =
  registry.templates[name] = tmpl

proc get*(registry: TemplateRegistry, name: string): ReportTemplate =
  registry.templates.getOrDefault(name, nil)

# テンプレート実装
method generate*(tmpl: ReportTemplate, title: string, data: Table[string, JsonNode]): Report {.base.} =
  raise newException(CatchableError, "Not implemented")

method generate*(tmpl: TestReportTemplate, title: string, data: Table[string, JsonNode]): Report =
  var builder = newReportBuilder(title)
  
  if data.hasKey("tests"):
    builder.addSection("Test Results")
    for test in data["tests"]:
      let name = test["name"].str
      let testResult = test["result"].str
      builder.addItem(name, testResult)
  
  result = builder.build()

method generate*(tmpl: PerformanceReportTemplate, title: string, data: Table[string, JsonNode]): Report =
  var builder = newReportBuilder(title)
  builder.addSection("Performance Metrics")
  result = builder.build()

# 進捗レポーター
proc newProgressReporter*(title: string): ProgressReporter =
  result = ProgressReporter(
    title: title,
    tasks: @[],
    currentTasks: initTable[string, ptr TaskInfo]()
  )
  initLock(result.lock)

proc beginTask*(reporter: ProgressReporter, taskName: string) =
  withLock reporter.lock:
    var task = TaskInfo(
      name: taskName,
      startTime: now(),
      status: "Running",
      progress: 0
    )
    reporter.tasks.add(task)
    reporter.currentTasks[taskName] = addr reporter.tasks[^1]

proc updateProgress*(reporter: ProgressReporter, taskName: string, progress: int, details: string) =
  withLock reporter.lock:
    if taskName in reporter.currentTasks:
      reporter.currentTasks[taskName].progress = progress
      reporter.currentTasks[taskName].details = details

proc completeTask*(reporter: ProgressReporter, taskName: string, details: string) =
  withLock reporter.lock:
    if taskName in reporter.currentTasks:
      reporter.currentTasks[taskName].endTime = now()
      reporter.currentTasks[taskName].status = "Success"
      reporter.currentTasks[taskName].details = details
      reporter.currentTasks.del(taskName)

proc failTask*(reporter: ProgressReporter, taskName: string, details: string) =
  withLock reporter.lock:
    if taskName in reporter.currentTasks:
      reporter.currentTasks[taskName].endTime = now()
      reporter.currentTasks[taskName].status = "Failed"
      reporter.currentTasks[taskName].details = details
      reporter.currentTasks.del(taskName)

proc generateReport*(reporter: ProgressReporter): Report =
  var builder = newReportBuilder(reporter.title)
  
  builder.addSection("Task Summary")
  
  withLock reporter.lock:
    for task in reporter.tasks:
      var value = task.status
      if task.status == "Failed":
        builder.addItem(task.name, value, task.details)
      else:
        builder.addItem(task.name, value)
  
  result = builder.build()

# レポート集約
proc newReportAggregator*(title: string): ReportAggregator =
  ReportAggregator(title: title, reports: @[])

proc addReport*(aggregator: ReportAggregator, report: Report) =
  aggregator.reports.add(report)

proc aggregate*(aggregator: ReportAggregator): Report =
  var builder = newReportBuilder(aggregator.title)
  
  for report in aggregator.reports:
    for section in report.sections:
      builder.sections.add(section)
  
  result = builder.build()

# レポートフィルター
proc newReportFilter*(): ReportFilter =
  ReportFilter(criteria: @[])

proc addCriteria*(filter: ReportFilter, field, value: string) =
  filter.criteria.add(FilterCriteria(field: field, value: value))

proc apply*(filter: ReportFilter, report: Report): Report =
  var builder = newReportBuilder(report.title)
  
  for section in report.sections:
    var filteredSection = ReportSection(
      title: section.title,
      content: section.content,
      items: @[],
      tables: section.tables,
      subsections: section.subsections
    )
    
    for item in section.items:
      var shouldInclude = true
      for criterion in filter.criteria:
        if criterion.field == "status" and item.value != criterion.value:
          shouldInclude = false
          break
      
      if shouldInclude:
        filteredSection.items.add(item)
    
    builder.sections.add(filteredSection)
  
  result = builder.build()
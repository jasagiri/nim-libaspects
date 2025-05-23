## Metrics Collection Framework
##
## Provides a comprehensive metrics collection system for monitoring and observability.
## Supports various metric types: Counter, Gauge, Histogram, Summary, and Timer.

import std/[tables, times, strformat, math, algorithm, sequtils, locks, options, os]

type
  MetricType* = enum
    mtCounter
    mtGauge
    mtHistogram
    mtSummary
    mtTimer
  
  LabelPair* = tuple[name: string, value: string]
  
  MetricValue* = object
    value: float
    timestamp: Time
  
  Counter* = ref object
    name: string
    help: string
    labelNames: seq[string]
    values: Table[seq[string], float]
    lock: Lock
  
  Gauge* = ref object
    name: string
    help: string
    labelNames: seq[string]
    values: Table[seq[string], float]
    lock: Lock
  
  Histogram* = ref object
    name: string
    help: string
    labelNames: seq[string]
    buckets: seq[float]
    observations: Table[seq[string], HistogramData]
    lock: Lock
  
  HistogramData* = object
    count: int
    sum: float
    bucketCounts: seq[int]
  
  Summary* = ref object
    name: string
    help: string
    labelNames: seq[string]
    observations: Table[seq[string], SummaryData]
    lock: Lock
  
  SummaryData* = object
    values: seq[float]
    count: int
    sum: float
  
  Timer* = ref object
    name: string
    help: string
    labelNames: seq[string]
    durations: Table[seq[string], TimerData]
    lock: Lock
  
  TimerData* = object
    count: int
    totalTime: float
  
  TimerContext* = ref object
    timer: Timer
    labels: seq[string]
    startTime: Time
  
  HistogramStats* = object
    count*: int
    sum*: float
    mean*: float
    buckets*: Table[float, int]
  
  Metric* = ref object
    case kind*: MetricType
    of mtCounter: counter*: Counter
    of mtGauge: gauge*: Gauge
    of mtHistogram: histogram*: Histogram
    of mtSummary: summary*: Summary
    of mtTimer: timer*: Timer
  
  MetricsRegistry* = ref object
    metrics: Table[string, Metric]
    lock: Lock
  
  MetricsReporter* = ref object
    registry: MetricsRegistry
    callback: proc(registry: MetricsRegistry) {.gcsafe.}
    interval: int
    running: bool
    thread: Thread[MetricsReporter]

# Forward declarations
proc newCounter*(name: string, help: string = "", labelNames: seq[string] = @[]): Counter
proc newGauge*(name: string, help: string = "", labelNames: seq[string] = @[]): Gauge
proc newHistogram*(name: string, help: string = "", labelNames: seq[string] = @[], buckets: seq[float] = @[]): Histogram
proc newSummary*(name: string, help: string = "", labelNames: seq[string] = @[]): Summary
proc newTimer*(name: string, help: string = "", labelNames: seq[string] = @[]): Timer

# Counter implementation
proc newCounter*(name: string, help: string = "", labelNames: seq[string] = @[]): Counter =
  result = Counter(
    name: name,
    help: help,
    labelNames: labelNames,
    values: initTable[seq[string], float]()
  )
  initLock(result.lock)

proc inc*(c: Counter, labels: seq[string] = @[], value: float = 1.0) =
  withLock c.lock:
    if labels.len != c.labelNames.len:
      if labels.len == 0 and c.labelNames.len == 0:
        c.values[@[]] = c.values.getOrDefault(@[], 0.0) + value
      else:
        raise newException(ValueError, "Label count mismatch")
    else:
      c.values[labels] = c.values.getOrDefault(labels, 0.0) + value

proc value*(c: Counter, labels: seq[string] = @[]): float =
  withLock c.lock:
    result = c.values.getOrDefault(labels, 0.0)

# Gauge implementation
proc newGauge*(name: string, help: string = "", labelNames: seq[string] = @[]): Gauge =
  result = Gauge(
    name: name,
    help: help,
    labelNames: labelNames,
    values: initTable[seq[string], float]()
  )
  initLock(result.lock)

proc set*(g: Gauge, value: float, labels: seq[string] = @[]) =
  withLock g.lock:
    g.values[labels] = value

proc inc*(g: Gauge, value: float = 1.0, labels: seq[string] = @[]) =
  withLock g.lock:
    g.values[labels] = g.values.getOrDefault(labels, 0.0) + value

proc dec*(g: Gauge, value: float = 1.0, labels: seq[string] = @[]) =
  withLock g.lock:
    g.values[labels] = g.values.getOrDefault(labels, 0.0) - value

proc value*(g: Gauge, labels: seq[string] = @[]): float =
  withLock g.lock:
    result = g.values.getOrDefault(labels, 0.0)

# Histogram implementation
proc newHistogram*(name: string, help: string = "", labelNames: seq[string] = @[], buckets: seq[float] = @[]): Histogram =
  var defaultBuckets = buckets
  if defaultBuckets.len == 0:
    defaultBuckets = @[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
  
  result = Histogram(
    name: name,
    help: help,
    labelNames: labelNames,
    buckets: defaultBuckets.sorted(),
    observations: initTable[seq[string], HistogramData]()
  )
  initLock(result.lock)

proc observe*(h: Histogram, value: float, labels: seq[string] = @[]) =
  withLock h.lock:
    var data = h.observations.getOrDefault(labels, HistogramData(
      count: 0,
      sum: 0.0,
      bucketCounts: newSeq[int](h.buckets.len)
    ))
    
    data.count.inc()
    data.sum += value
    
    for i, bucket in h.buckets:
      if value <= bucket:
        data.bucketCounts[i].inc()
    
    h.observations[labels] = data

proc getStatistics*(h: Histogram, labels: seq[string] = @[]): HistogramStats =
  withLock h.lock:
    let data = h.observations.getOrDefault(labels, HistogramData())
    result.count = data.count
    result.sum = data.sum
    if data.count > 0:
      result.mean = data.sum / float(data.count)
    
    result.buckets = initTable[float, int]()
    if data.bucketCounts.len > 0:
      for i, bucket in h.buckets:
        result.buckets[bucket] = data.bucketCounts[i]

# Summary implementation
proc newSummary*(name: string, help: string = "", labelNames: seq[string] = @[]): Summary =
  result = Summary(
    name: name,
    help: help,
    labelNames: labelNames,
    observations: initTable[seq[string], SummaryData]()
  )
  initLock(result.lock)

proc observe*(s: Summary, value: float, labels: seq[string] = @[]) =
  withLock s.lock:
    var data = s.observations.getOrDefault(labels, SummaryData())
    data.values.add(value)
    data.count.inc()
    data.sum += value
    s.observations[labels] = data

proc getQuantiles*(s: Summary, quantiles: seq[float], labels: seq[string] = @[]): Table[float, float] =
  result = initTable[float, float]()
  withLock s.lock:
    let data = s.observations.getOrDefault(labels, SummaryData())
    if data.values.len == 0:
      return
    
    var sorted = data.values.sorted()
    for q in quantiles:
      if q < 0 or q > 1:
        continue
      let index = int(float(sorted.len - 1) * q)
      result[q] = sorted[index]

# Timer implementation
proc newTimer*(name: string, help: string = "", labelNames: seq[string] = @[]): Timer =
  result = Timer(
    name: name,
    help: help,
    labelNames: labelNames,
    durations: initTable[seq[string], TimerData]()
  )
  initLock(result.lock)

proc start*(t: Timer, labels: seq[string] = @[]): TimerContext =
  result = TimerContext(
    timer: t,
    labels: labels,
    startTime: getTime()
  )

proc stop*(tc: TimerContext): float =
  let endTime = getTime()
  let duration = (endTime - tc.startTime).inMilliseconds.float / 1000.0
  
  withLock tc.timer.lock:
    var data = tc.timer.durations.getOrDefault(tc.labels, TimerData())
    data.count.inc()
    data.totalTime += duration
    tc.timer.durations[tc.labels] = data
  
  result = duration

proc count*(t: Timer, labels: seq[string] = @[]): int =
  withLock t.lock:
    let data = t.durations.getOrDefault(labels, TimerData())
    result = data.count

proc totalTime*(t: Timer, labels: seq[string] = @[]): float =
  withLock t.lock:
    let data = t.durations.getOrDefault(labels, TimerData())
    result = data.totalTime

proc averageTime*(t: Timer, labels: seq[string] = @[]): float =
  withLock t.lock:
    let data = t.durations.getOrDefault(labels, TimerData())
    if data.count > 0:
      result = data.totalTime / data.count.float
    else:
      result = 0.0

# MetricsRegistry implementation
proc newMetricsRegistry*(): MetricsRegistry =
  result = MetricsRegistry(
    metrics: initTable[string, Metric]()
  )
  initLock(result.lock)

proc counter*(mr: MetricsRegistry, name: string, labelNames: seq[string] = @[]): Counter =
  withLock mr.lock:
    if name in mr.metrics:
      if mr.metrics[name].kind == mtCounter:
        return mr.metrics[name].counter
      else:
        raise newException(ValueError, &"Metric {name} already exists with different type")
    
    result = newCounter(name, "", labelNames)
    mr.metrics[name] = Metric(kind: mtCounter, counter: result)

proc gauge*(mr: MetricsRegistry, name: string, labelNames: seq[string] = @[]): Gauge =
  withLock mr.lock:
    if name in mr.metrics:
      if mr.metrics[name].kind == mtGauge:
        return mr.metrics[name].gauge
      else:
        raise newException(ValueError, &"Metric {name} already exists with different type")
    
    result = newGauge(name, "", labelNames)
    mr.metrics[name] = Metric(kind: mtGauge, gauge: result)

proc histogram*(mr: MetricsRegistry, name: string, labelNames: seq[string] = @[], buckets: seq[float] = @[]): Histogram =
  withLock mr.lock:
    if name in mr.metrics:
      if mr.metrics[name].kind == mtHistogram:
        return mr.metrics[name].histogram
      else:
        raise newException(ValueError, &"Metric {name} already exists with different type")
    
    result = newHistogram(name, "", labelNames, buckets)
    mr.metrics[name] = Metric(kind: mtHistogram, histogram: result)

proc summary*(mr: MetricsRegistry, name: string, labelNames: seq[string] = @[]): Summary =
  withLock mr.lock:
    if name in mr.metrics:
      if mr.metrics[name].kind == mtSummary:
        return mr.metrics[name].summary
      else:
        raise newException(ValueError, &"Metric {name} already exists with different type")
    
    result = newSummary(name, "", labelNames)
    mr.metrics[name] = Metric(kind: mtSummary, summary: result)

proc timer*(mr: MetricsRegistry, name: string, labelNames: seq[string] = @[]): Timer =
  withLock mr.lock:
    if name in mr.metrics:
      if mr.metrics[name].kind == mtTimer:
        return mr.metrics[name].timer
      else:
        raise newException(ValueError, &"Metric {name} already exists with different type")
    
    result = newTimer(name, "", labelNames)
    mr.metrics[name] = Metric(kind: mtTimer, timer: result)

proc getAllMetrics*(mr: MetricsRegistry): Table[string, Metric] =
  withLock mr.lock:
    result = mr.metrics

proc getTimer*(mr: MetricsRegistry, name: string): Timer =
  withLock mr.lock:
    if name in mr.metrics and mr.metrics[name].kind == mtTimer:
      result = mr.metrics[name].timer
    else:
      raise newException(KeyError, &"Timer metric {name} not found")

# Export to Prometheus format
proc exportPrometheus*(mr: MetricsRegistry): string =
  result = ""
  withLock mr.lock:
    for name, metric in mr.metrics:
      case metric.kind
      of mtCounter:
        for labels, value in metric.counter.values:
          if labels.len > 0:
            var labelStr = ""
            for i, label in labels:
              if i > 0: labelStr.add(",")
              labelStr.add(&"{metric.counter.labelNames[i]}=\"{label}\"")
            result.add(&"{name}{{{labelStr}}} {value}\n")
          else:
            result.add(&"{name} {value}\n")
      
      of mtGauge:
        for labels, value in metric.gauge.values:
          if labels.len > 0:
            var labelStr = ""
            for i, label in labels:
              if i > 0: labelStr.add(",")
              labelStr.add(&"{metric.gauge.labelNames[i]}=\"{label}\"")
            result.add(&"{name}{{{labelStr}}} {value}\n")
          else:
            result.add(&"{name} {value}\n")
      
      else:
        discard  # TODO: Implement other metric types

# MetricsReporter implementation
proc newMetricsReporter*(registry: MetricsRegistry, callback: proc(registry: MetricsRegistry) {.gcsafe.}): MetricsReporter =
  result = MetricsReporter(
    registry: registry,
    callback: callback,
    running: false
  )

proc reporterThread(reporter: MetricsReporter) {.thread, gcsafe.} =
  while reporter.running:
    reporter.callback(reporter.registry)
    sleep(reporter.interval)

proc start*(reporter: MetricsReporter, interval: int = 60000) =
  reporter.interval = interval
  reporter.running = true
  createThread(reporter.thread, reporterThread, reporter)

proc stop*(reporter: MetricsReporter) =
  reporter.running = false
  joinThread(reporter.thread)

# Global default registry
var defaultMetricsRegistry* = newMetricsRegistry()

# Metrics annotation support
template metricsTimer*(name: string, body: untyped): untyped =
  ## Timer annotation for automatic timing of procedures
  let timer {.inject.} = defaultMetricsRegistry.timer(name)
  let timerContext = timer.start()
  try:
    body
  finally:
    discard timerContext.stop()

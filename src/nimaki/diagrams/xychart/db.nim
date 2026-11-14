## port-of: src/diagrams/xychart/db.ts
## port-status: draft
##
## JavaScript's `undefined` is "" for a string (title, accTitle, accDescr, orientation) and NaN
## for a value of a series: a value read from the text is never NaN.
import std/math
import ../../js
import ../../jsregex

type
  XyText* = object
    text*: string
    kind*: string            ## 'text' | 'markdown'

  DataPoint* = object
    value*: float
    label*: string

  Axis* = object
    ## BandAxis (`band`: categories) or LinearAxis (`linear`: min, max).
    band*: bool
    title*: string
    categories*: seq[string]
    min*, max*: float

  Plot* = object
    bar*: bool               ## 'bar', else 'line'
    title*: string
    data*: seq[(string, float)]
    pointLabels*: seq[string]
    hasPointLabels*: bool

  XyChartDb* = ref object of RootObj
    title*, accTitle*, accDescr*: string
    orientation*: string     ## 'vertical' | 'horizontal' | "" for undefined
    xAxis*: Axis
    yAxis*: Axis
    hasSetXAxis*, hasSetYAxis*: bool
    plots*: seq[Plot]

proc newXyChartDb*(): XyChartDb =
  XyChartDb(xAxis: Axis(band: true), yAxis: Axis(min: Inf, max: NegInf))

proc setOrientation*(db: XyChartDb, orientation: string) =
  db.orientation = if orientation == "horizontal": "horizontal" else: "vertical"

proc setXAxisTitle*(db: XyChartDb, title: XyText) = db.xAxis.title = jsTrim(title.text)

proc setXAxisRangeData*(db: XyChartDb, min, max: float) =
  db.xAxis = Axis(band: false, title: db.xAxis.title, min: min, max: max)
  db.hasSetXAxis = true

proc setXAxisBand*(db: XyChartDb, categories: seq[XyText]) =
  var names: seq[string]
  for c in categories: names.add jsTrim(c.text)
  db.xAxis = Axis(band: true, title: db.xAxis.title, categories: names)
  db.hasSetXAxis = true

proc setYAxisTitle*(db: XyChartDb, title: XyText) = db.yAxis.title = jsTrim(title.text)

proc setYAxisRangeData*(db: XyChartDb, min, max: float) =
  db.yAxis = Axis(band: false, title: db.yAxis.title, min: min, max: max)
  db.hasSetYAxis = true

proc plotData(db: XyChartDb, values: seq[float]): seq[(string, float)] =
  if values.len == 0: return
  var values = values
  # The first series fixes the x range when no x-axis statement did.
  if not db.hasSetXAxis: db.setXAxisRangeData(1, float(values.len))
  let x = db.xAxis
  if x.band and values.len > x.categories.len: values.setLen x.categories.len
  if not db.hasSetYAxis:
    var lo = db.yAxis.min
    var hi = db.yAxis.max
    for value in values:
      if value < lo: lo = value
      if value > hi: hi = value
    db.yAxis = Axis(band: false, title: db.yAxis.title, min: lo, max: hi)
  if x.band:
    for i, category in x.categories:
      result.add (category, (if i < values.len: values[i] else: NaN))
    return
  if values.len == 1: return @[(jsString(x.min), values[0])]
  let step = (x.max - x.min) / float(values.len - 1)
  for i, value in values: result.add (jsString(x.min + float(i) * step), value)

proc addPlot(db: XyChartDb, bar: bool, title: XyText, data: seq[DataPoint]) =
  var values: seq[float]
  for d in data: values.add d.value
  var plot = Plot(bar: bar, title: jsTrim(title.text), data: db.plotData(values))
  # Mermaid accepts labels on the points of a bar series and ignores them.
  var labelled = false
  for d in data:
    if jsTrim(d.label) != "": labelled = true
  if not bar and labelled:
    plot.hasPointLabels = true
    for d in data: plot.pointLabels.add jsTrim(d.label)
  db.plots.add plot

proc setLineData*(db: XyChartDb, title: XyText, data: seq[DataPoint]) = db.addPlot(false, title, data)
proc setBarData*(db: XyChartDb, title: XyText, data: seq[DataPoint]) = db.addPlot(true, title, data)

proc setDiagramTitle*(db: XyChartDb, text: string) = db.title = text

proc setAccTitle*(db: XyChartDb, text: string) =
  ## text.replace(/^\s+/g, '')
  db.accTitle = jsTrimStart(text)

proc setAccDescription*(db: XyChartDb, text: string) =
  db.accDescr = text.replace(jsre"/\n\s+/g", "\n")

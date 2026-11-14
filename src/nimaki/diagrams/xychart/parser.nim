## port-of: src/diagrams/xychart/parser.ts
## port-status: draft
import ../../errors
import ../../js
import db, lexer, tokens

const
  WORD = {T_AMP, T_NUM, T_ALPHA, T_PLUS, T_EQUALS, T_MULT, T_DOT, T_BRKT, T_MINUS, T_UNDERSCORE}
  EOL = {T_NEWLINE, T_SEMI, T_EOF}

proc parseXyChart*(src: string, db: XyChartDb) =
  let tk = tokenize(src)
  let types = tk.types
  let texts = tk.texts
  let starts = tk.starts
  var i = 0

  proc fail(expected: string) =
    let t = types[i]
    if t == T_ERROR: raise syntaxError("xychart", src, starts[i], "", true)
    raise syntaxError("xychart", src, starts[i], "Expecting " & expected & ", got '" & TOKEN_NAMES[t] & "'")

  proc expect(kind: int): string =
    if types[i] != kind: fail("'" & TOKEN_NAMES[kind] & "'")
    result = texts[i]
    inc i

  proc isText(t: int): bool = t == T_STR or t in WORD

  proc text(): XyText =
    if not isText(types[i]): fail("'STR', 'ALPHA', 'NUM'")
    var s = texts[i]
    inc i
    if types[i - 1] != T_STR:
      while types[i] in WORD:
        s.add texts[i]
        inc i
    XyText(text: s, kind: "text")

  proc range(): (float, float) =
    let min = jsToNumber(expect(T_NUMBER_WITH_DECIMAL))
    discard expect(T_ARROW_DELIMITER)
    (min, jsToNumber(expect(T_NUMBER_WITH_DECIMAL)))

  proc points(): seq[DataPoint] =
    discard expect(T_SQUARE_BRACES_START)
    while true:
      let value = jsToNumber(expect(T_NUMBER_WITH_DECIMAL))
      var label = ""
      if types[i] == T_STR:
        label = texts[i]
        inc i
      result.add DataPoint(value: value, label: label)
      if types[i] != T_COMMA: break
      inc i
    discard expect(T_SQUARE_BRACES_END)

  while true:
    if types[i] in EOL: inc i
    elif types[i] != T_XYCHART: break
    else:
      inc i
      if types[i] == T_CHART_ORIENTATION:
        db.setOrientation(texts[i])
        inc i

  while types[i] != T_END:
    let t = types[i]
    inc i
    case t
    of T_title:
      db.setDiagramTitle(jsTrim(text().text))
    of T_X_AXIS, T_Y_AXIS:
      var hasTitle = false
      var title = XyText(kind: "text")
      if isText(types[i]):
        title = text()
        hasTitle = true
      if t == T_X_AXIS and types[i] == T_SQUARE_BRACES_START:
        var categories: seq[XyText]
        while true:
          inc i
          categories.add text()
          if types[i] != T_COMMA: break
        discard expect(T_SQUARE_BRACES_END)
        db.setXAxisBand(categories)
      elif types[i] == T_NUMBER_WITH_DECIMAL or not hasTitle:
        let (min, max) = range()
        if t == T_X_AXIS: db.setXAxisRangeData(min, max)
        else: db.setYAxisRangeData(min, max)
      if t == T_X_AXIS: db.setXAxisTitle(title)
      else: db.setYAxisTitle(title)
    of T_LINE, T_BAR:
      let title = if types[i] == T_SQUARE_BRACES_START: XyText(text: "", kind: "text") else: text()
      let data = points()
      if t == T_LINE: db.setLineData(title, data)
      else: db.setBarData(title, data)
    of T_acc_title:
      db.setAccTitle(jsTrim(expect(T_acc_title_value)))
    of T_acc_descr:
      db.setAccDescription(jsTrim(expect(T_acc_descr_value)))
    of T_acc_descr_multiline_value:
      db.setAccDescription(jsTrim(texts[i - 1]))
    else:
      dec i
      fail("'title', 'X_AXIS', 'Y_AXIS', 'LINE', 'BAR', 'acc_title', 'acc_descr', 'acc_descr_multiline_value'")
    while types[i] in EOL: inc i

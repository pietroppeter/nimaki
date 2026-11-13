## port-of: src/diagrams/gantt/tokens.ts
## port-status: draft

const
  T_END* = 0
  T_ERROR* = 1
  T_open_directive* = 2
  T_acc_title* = 3
  T_acc_title_value* = 4
  T_acc_descr* = 5
  T_acc_descr_value* = 6
  T_acc_descr_multiline_value* = 7
  T_NL* = 8
  T_href* = 9
  T_callbackname* = 10
  T_callbackargs* = 11
  T_click* = 12
  T_gantt* = 13
  T_dateFormat* = 14
  T_inclusiveEndDates* = 15
  T_topAxis* = 16
  T_axisFormat* = 17
  T_tickInterval* = 18
  T_includes* = 19
  T_excludes* = 20
  T_todayMarker* = 21
  T_weekday_monday* = 22
  T_weekday_tuesday* = 23
  T_weekday_wednesday* = 24
  T_weekday_thursday* = 25
  T_weekday_friday* = 26
  T_weekday_saturday* = 27
  T_weekday_sunday* = 28
  T_weekend_friday* = 29
  T_weekend_saturday* = 30
  T_date* = 31
  T_title* = 32
  T_accDescription* = 33
  T_section* = 34
  T_taskTxt* = 35
  T_taskData* = 36
  T_COLON* = 37
  T_EOF* = 38

const TOKEN_NAMES*: array[39, string] = [
  "$end", "INVALID", "open_directive", "acc_title", "acc_title_value", "acc_descr", "acc_descr_value",
  "acc_descr_multiline_value", "NL", "href", "callbackname", "callbackargs", "click", "gantt", "dateFormat",
  "inclusiveEndDates", "topAxis", "axisFormat", "tickInterval", "includes", "excludes", "todayMarker",
  "weekday_monday", "weekday_tuesday", "weekday_wednesday", "weekday_thursday", "weekday_friday",
  "weekday_saturday", "weekday_sunday", "weekend_friday", "weekend_saturday", "date", "title",
  "accDescription", "section", "taskTxt", "taskData", ":", "EOF",
]

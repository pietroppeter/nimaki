## port-of: src/diagrams/xychart/tokens.ts
## port-status: draft

const
  T_END* = 0
  T_ERROR* = 1
  T_NEWLINE* = 2
  T_title* = 3
  T_acc_title* = 4
  T_acc_title_value* = 5
  T_acc_descr* = 6
  T_acc_descr_value* = 7
  T_acc_descr_multiline_value* = 8
  T_XYCHART* = 9
  T_CHART_ORIENTATION* = 10
  T_X_AXIS* = 11
  T_Y_AXIS* = 12
  T_ARROW_DELIMITER* = 13
  T_LINE* = 14
  T_BAR* = 15
  T_NUMBER_WITH_DECIMAL* = 16
  T_SQUARE_BRACES_START* = 17
  T_SQUARE_BRACES_END* = 18
  T_STR* = 19
  T_ALPHA* = 20
  T_COLON* = 21
  T_PLUS* = 22
  T_COMMA* = 23
  T_EQUALS* = 24
  T_MULT* = 25
  T_BRKT* = 26
  T_UNDERSCORE* = 27
  T_DOT* = 28
  T_AMP* = 29
  T_MINUS* = 30
  T_NUM* = 31
  T_SEMI* = 32
  T_EOF* = 33

const TOKEN_NAMES* = [
  "$end",
  "INVALID",
  "NEWLINE",
  "title",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "XYCHART",
  "CHART_ORIENTATION",
  "X_AXIS",
  "Y_AXIS",
  "ARROW_DELIMITER",
  "LINE",
  "BAR",
  "NUMBER_WITH_DECIMAL",
  "SQUARE_BRACES_START",
  "SQUARE_BRACES_END",
  "STR",
  "ALPHA",
  "COLON",
  "PLUS",
  "COMMA",
  "EQUALS",
  "MULT",
  "BRKT",
  "UNDERSCORE",
  "DOT",
  "AMP",
  "MINUS",
  "NUM",
  "SEMI",
  "EOF",
]

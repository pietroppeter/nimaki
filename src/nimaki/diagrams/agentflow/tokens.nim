## port-of: src/diagrams/agentflow/tokens.ts
## port-status: draft

const
  T_STOP* = 0  ## Pele's T.END ($end); T_end is the keyword
  T_ERROR* = 1
  T_acc_title* = 2
  T_acc_title_value* = 3
  T_acc_descr* = 4
  T_acc_descr_value* = 5
  T_acc_descr_multiline_value* = 6
  T_SHAPE_DATA* = 7
  T_CALLBACKNAME* = 8
  T_CALLBACKARGS* = 9
  T_MD_STR* = 10
  T_STR* = 11
  T_STYLE* = 12
  T_DEFAULT* = 13
  T_LINKSTYLE* = 14
  T_INTERPOLATE* = 15
  T_CLASSDEF* = 16
  T_CLASS* = 17
  T_HREF* = 18
  T_CLICK* = 19
  T_GRAPH* = 20
  T_flow* = 21
  T_connector* = 22
  T_global* = 23
  T_end* = 24
  T_LINK_TARGET* = 25
  T_NODIR* = 26
  T_DIR* = 27
  T_direction_tb* = 28
  T_direction_bt* = 29
  T_direction_rl* = 30
  T_direction_lr* = 31
  T_direction_td* = 32
  T_LINK_ID* = 33
  T_NUM* = 34
  T_BRKT* = 35
  T_STYLE_SEPARATOR* = 36
  T_COLON* = 37
  T_AMP* = 38
  T_SEMI* = 39
  T_COMMA* = 40
  T_MULT* = 41
  T_LINK* = 42
  T_START_LINK* = 43
  T_EDGE_TEXT* = 44
  T_ELLIPSE_END* = 45
  T_TEXT* = 46
  T_ELLIPSE_START* = 47
  T_STADIUMEND* = 48
  T_STADIUMSTART* = 49
  T_SUBROUTINEEND* = 50
  T_SUBROUTINESTART* = 51
  T_VERTEX_WITH_PROPS_START* = 52
  T_TAGEND* = 53
  T_CYLINDEREND* = 54
  T_CYLINDERSTART* = 55
  T_DOUBLECIRCLEEND* = 56
  T_DOUBLECIRCLESTART* = 57
  T_TRAPEND* = 58
  T_INVTRAPEND* = 59
  T_TRAPSTART* = 60
  T_INVTRAPSTART* = 61
  T_TAGSTART* = 62
  T_UP* = 63
  T_SEP* = 64
  T_DOWN* = 65
  T_COMMENT* = 66
  T_NODE_STRING* = 67
  T_MINUS* = 68
  T_UNICODE_TEXT* = 69
  T_PIPE* = 70
  T_PE* = 71
  T_PS* = 72
  T_SQE* = 73
  T_SQS* = 74
  T_DIAMOND_STOP* = 75
  T_DIAMOND_START* = 76
  T_NEWLINE* = 77
  T_SPACE* = 78
  T_EOF* = 79

const TOKEN_NAMES*: array[80, string] = [
  "$end", "INVALID", "acc_title", "acc_title_value", "acc_descr", "acc_descr_value",
  "acc_descr_multiline_value", "SHAPE_DATA", "CALLBACKNAME", "CALLBACKARGS", "MD_STR", "STR", "STYLE",
  "DEFAULT", "LINKSTYLE", "INTERPOLATE", "CLASSDEF", "CLASS", "HREF", "CLICK", "GRAPH", "flow", "connector",
  "global", "end", "LINK_TARGET", "NODIR", "DIR", "direction_tb", "direction_bt", "direction_rl",
  "direction_lr", "direction_td", "LINK_ID", "NUM", "BRKT", "STYLE_SEPARATOR", "COLON", "AMP", "SEMI",
  "COMMA", "MULT", "LINK", "START_LINK", "EDGE_TEXT", "-)", "TEXT", "(-", "STADIUMEND", "STADIUMSTART",
  "SUBROUTINEEND", "SUBROUTINESTART", "VERTEX_WITH_PROPS_START", "TAGEND", "CYLINDEREND", "CYLINDERSTART",
  "DOUBLECIRCLEEND", "DOUBLECIRCLESTART", "TRAPEND", "INVTRAPEND", "TRAPSTART", "INVTRAPSTART", "TAGSTART",
  "UP", "SEP", "DOWN", "COMMENT", "NODE_STRING", "MINUS", "UNICODE_TEXT", "PIPE", "PE", "PS", "SQE", "SQS",
  "DIAMOND_STOP", "DIAMOND_START", "NEWLINE", "SPACE", "EOF",
]

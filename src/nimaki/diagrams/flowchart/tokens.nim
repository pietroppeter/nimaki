## port-of: src/diagrams/flowchart/tokens.ts
## port-status: conformant
##
## `const enum T` is `T_name` constants (the porting guide's names table).

const
  T_STOP* = 0 ## Pele's `T.END`; `T_end` is the `end` keyword, and Nim does not tell the two apart
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
  T_subgraph* = 21
  T_end* = 22
  T_LINK_TARGET* = 23
  T_NODIR* = 24
  T_DIR* = 25
  T_direction_tb* = 26
  T_direction_bt* = 27
  T_direction_rl* = 28
  T_direction_lr* = 29
  T_direction_td* = 30
  T_LINK_ID* = 31
  T_NUM* = 32
  T_BRKT* = 33
  T_STYLE_SEPARATOR* = 34
  T_COLON* = 35
  T_AMP* = 36
  T_SEMI* = 37
  T_COMMA* = 38
  T_MULT* = 39
  T_LINK* = 40
  T_START_LINK* = 41
  T_EDGE_TEXT* = 42
  T_ELLIPSE_END* = 43
  T_TEXT* = 44
  T_ELLIPSE_START* = 45
  T_STADIUMEND* = 46
  T_STADIUMSTART* = 47
  T_SUBROUTINEEND* = 48
  T_SUBROUTINESTART* = 49
  T_VERTEX_WITH_PROPS_START* = 50
  T_TAGEND* = 51
  T_CYLINDEREND* = 52
  T_CYLINDERSTART* = 53
  T_DOUBLECIRCLEEND* = 54
  T_DOUBLECIRCLESTART* = 55
  T_TRAPEND* = 56
  T_INVTRAPEND* = 57
  T_TRAPSTART* = 58
  T_INVTRAPSTART* = 59
  T_TAGSTART* = 60
  T_UP* = 61
  T_SEP* = 62
  T_DOWN* = 63
  T_NODE_STRING* = 64
  T_MINUS* = 65
  T_UNICODE_TEXT* = 66
  T_PIPE* = 67
  T_PE* = 68
  T_PS* = 69
  T_SQE* = 70
  T_SQS* = 71
  T_DIAMOND_STOP* = 72
  T_DIAMOND_START* = 73
  T_NEWLINE* = 74
  T_SPACE* = 75
  T_EOF* = 76

const TOKEN_NAMES*: array[77, string] = [
  "$end",
  "INVALID",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "SHAPE_DATA",
  "CALLBACKNAME",
  "CALLBACKARGS",
  "MD_STR",
  "STR",
  "STYLE",
  "DEFAULT",
  "LINKSTYLE",
  "INTERPOLATE",
  "CLASSDEF",
  "CLASS",
  "HREF",
  "CLICK",
  "GRAPH",
  "subgraph",
  "end",
  "LINK_TARGET",
  "NODIR",
  "DIR",
  "direction_tb",
  "direction_bt",
  "direction_rl",
  "direction_lr",
  "direction_td",
  "LINK_ID",
  "NUM",
  "BRKT",
  "STYLE_SEPARATOR",
  "COLON",
  "AMP",
  "SEMI",
  "COMMA",
  "MULT",
  "LINK",
  "START_LINK",
  "EDGE_TEXT",
  "-)",
  "TEXT",
  "(-",
  "STADIUMEND",
  "STADIUMSTART",
  "SUBROUTINEEND",
  "SUBROUTINESTART",
  "VERTEX_WITH_PROPS_START",
  "TAGEND",
  "CYLINDEREND",
  "CYLINDERSTART",
  "DOUBLECIRCLEEND",
  "DOUBLECIRCLESTART",
  "TRAPEND",
  "INVTRAPEND",
  "TRAPSTART",
  "INVTRAPSTART",
  "TAGSTART",
  "UP",
  "SEP",
  "DOWN",
  "NODE_STRING",
  "MINUS",
  "UNICODE_TEXT",
  "PIPE",
  "PE",
  "PS",
  "SQE",
  "SQS",
  "DIAMOND_STOP",
  "DIAMOND_START",
  "NEWLINE",
  "SPACE",
  "EOF",
]

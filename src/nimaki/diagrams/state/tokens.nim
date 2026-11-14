## port-of: src/diagrams/state/tokens.ts
## port-status: conformant
##
## `const enum T` is `T_name` constants (the porting guide's names table).

const
  T_END* = 0
  T_ERROR* = 1
  T_NL* = 2
  T_SD* = 3
  T_DESCR* = 4
  T_ARROW* = 5
  T_HIDE_EMPTY* = 6
  T_scale* = 7
  T_WIDTH* = 8
  T_COMPOSIT_STATE* = 9
  T_STRUCT_START* = 10
  T_STRUCT_STOP* = 11
  T_STATE_DESCR* = 12
  T_AS* = 13
  T_ID* = 14
  T_FORK* = 15
  T_JOIN* = 16
  T_CHOICE* = 17
  T_CONCURRENT* = 18
  T_note* = 19
  T_NOTE_TEXT* = 20
  T_acc_title* = 21
  T_acc_title_value* = 22
  T_acc_descr* = 23
  T_acc_descr_value* = 24
  T_acc_descr_multiline_value* = 25
  T_CLICK* = 26
  T_STRING* = 27
  T_HREF* = 28
  T_classDef* = 29
  T_CLASSDEF_ID* = 30
  T_DEFAULT_CLASSDEF_ID* = 31
  T_CLASSDEF_STYLEOPTS* = 32
  T_DEFAULT* = 33
  T_style* = 34
  T_STYLE_IDS* = 35
  T_STYLEDEF_STYLEOPTS* = 36
  T_class* = 37
  T_CLASSENTITY_IDS* = 38
  T_STYLECLASS* = 39
  T_direction_tb* = 40
  T_direction_bt* = 41
  T_direction_rl* = 42
  T_direction_lr* = 43
  T_EDGE_STATE* = 44
  T_STYLE_SEPARATOR* = 45
  T_left_of* = 46
  T_right_of* = 47
  T_INVALID* = 48

const TOKEN_NAMES*: array[49, string] = [
  "$end",
  "INVALID",
  "NL",
  "SD",
  "DESCR",
  "-->",
  "HIDE_EMPTY",
  "scale",
  "WIDTH",
  "COMPOSIT_STATE",
  "STRUCT_START",
  "STRUCT_STOP",
  "STATE_DESCR",
  "AS",
  "ID",
  "FORK",
  "JOIN",
  "CHOICE",
  "CONCURRENT",
  "note",
  "NOTE_TEXT",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "CLICK",
  "STRING",
  "HREF",
  "classDef",
  "CLASSDEF_ID",
  "DEFAULT_CLASSDEF_ID",
  "CLASSDEF_STYLEOPTS",
  "DEFAULT",
  "style",
  "STYLE_IDS",
  "STYLEDEF_STYLEOPTS",
  "class",
  "CLASSENTITY_IDS",
  "STYLECLASS",
  "direction_tb",
  "direction_bt",
  "direction_rl",
  "direction_lr",
  "EDGE_STATE",
  "STYLE_SEPARATOR",
  "left_of",
  "right_of",
  "INVALID",
]

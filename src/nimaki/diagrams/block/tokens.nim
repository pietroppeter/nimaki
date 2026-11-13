## port-of: src/diagrams/block/tokens.ts
## port-status: draft

const
  T_STOP* = 0
  T_ERROR* = 1
  T_KEY* = 2
  T_ID_BLOCK* = 3
  T_COLUMNS* = 4
  T_MD_STR* = 5
  T_STR* = 6
  T_SPACE_BLOCK* = 7
  T_DEFAULT* = 8
  T_LINKSTYLE* = 9
  T_INTERPOLATE* = 10
  T_CLASSDEF* = 11
  T_DEFAULT_CLASSDEF_ID* = 12
  T_CLASSDEF_ID* = 13
  T_CLASSDEF_STYLEOPTS* = 14
  T_CLASS* = 15
  T_CLASSENTITY_IDS* = 16
  T_STYLECLASS* = 17
  T_STYLE* = 18
  T_STYLE_ENTITY_IDS* = 19
  T_STYLE_DEFINITION_DATA* = 20
  T_acc_title* = 21
  T_acc_title_value* = 22
  T_acc_descr* = 23
  T_acc_descr_value* = 24
  T_acc_descr_multiline_value* = 25
  T_end* = 26
  T_NODE_DSTART* = 27
  T_NODE_DEND* = 28
  T_BLOCK_ARROW_START* = 29
  T_BLOCK_ARROW_END* = 30
  T_DIR* = 31
  T_NODE_ID* = 32
  T_LINK* = 33
  T_START_LINK* = 34
  T_LINK_LABEL* = 35
  T_SIZE* = 36
  T_EOF* = 37

const TOKEN_NAMES*: array[38, string] = [
  "$end",
  "INVALID",
  "BLOCK_DIAGRAM_KEY",
  "id-block",
  "COLUMNS",
  "MD_STR",
  "STR",
  "SPACE_BLOCK",
  "DEFAULT",
  "LINKSTYLE",
  "INTERPOLATE",
  "classDef",
  "DEFAULT_CLASSDEF_ID",
  "CLASSDEF_ID",
  "CLASSDEF_STYLEOPTS",
  "class",
  "CLASSENTITY_IDS",
  "STYLECLASS",
  "style",
  "STYLE_ENTITY_IDS",
  "STYLE_DEFINITION_DATA",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "end",
  "NODE_DSTART",
  "NODE_DEND",
  "BLOCK_ARROW_START",
  "BLOCK_ARROW_END",
  "DIR",
  "NODE_ID",
  "LINK",
  "START_LINK",
  "LINK_LABEL",
  "SIZE",
  "EOF",
]

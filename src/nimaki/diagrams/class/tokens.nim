## port-of: src/diagrams/class/tokens.ts
## port-status: draft
##
## Port notes: `T.END` is `T_STOP` (as in flowchart); the others keep their names after `T_`.

const
  T_STOP* = 0
  T_ERROR* = 1
  T_CLASS_DIAGRAM* = 2
  T_NEWLINE* = 3
  T_EOF* = 4
  T_SQS* = 5
  T_STR* = 6
  T_SQE* = 7
  T_DOT* = 8
  T_GENERICTYPE* = 9
  T_LABEL* = 10
  T_acc_title* = 11
  T_acc_title_value* = 12
  T_acc_descr* = 13
  T_acc_descr_value* = 14
  T_acc_descr_multiline_value* = 15
  T_STRUCT_START* = 16
  T_STRUCT_STOP* = 17
  T_NAMESPACE* = 18
  T_STYLE_SEPARATOR* = 19
  T_ANNOTATION_START* = 20
  T_ANNOTATION_END* = 21
  T_CLASS* = 22
  T_MEMBER* = 23
  T_NOTE_FOR* = 24
  T_NOTE* = 25
  T_CLASSDEF* = 26
  T_ALPHA* = 27
  T_COMMA* = 28
  T_direction_tb* = 29
  T_direction_bt* = 30
  T_direction_rl* = 31
  T_direction_lr* = 32
  T_AGGREGATION* = 33
  T_EXTENSION* = 34
  T_COMPOSITION* = 35
  T_DEPENDENCY* = 36
  T_LOLLIPOP* = 37
  T_LINE* = 38
  T_DOTTED_LINE* = 39
  T_CALLBACK* = 40
  T_LINK* = 41
  T_LINK_TARGET* = 42
  T_CLICK* = 43
  T_CALLBACK_NAME* = 44
  T_CALLBACK_ARGS* = 45
  T_HREF* = 46
  T_STYLE* = 47
  T_CSSCLASS* = 48
  T_COLON* = 49
  T_BRKT* = 50
  T_PCT* = 51
  T_MINUS* = 52
  T_UNICODE_TEXT* = 53
  T_BQUOTE_STR* = 54
  T_EDGE_STATE* = 55
  T_EOF_IN_STRUCT* = 56
  T_OPEN_IN_STRUCT* = 57
  T_PLUS* = 58
  T_EQUALS* = 59
  T_PUNCTUATION* = 60

const TOKEN_NAMES*: array[61, string] = [
  "$end",
  "INVALID",
  "CLASS_DIAGRAM",
  "NEWLINE",
  "EOF",
  "SQS",
  "STR",
  "SQE",
  "DOT",
  "GENERICTYPE",
  "LABEL",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "STRUCT_START",
  "STRUCT_STOP",
  "NAMESPACE",
  "STYLE_SEPARATOR",
  "ANNOTATION_START",
  "ANNOTATION_END",
  "CLASS",
  "MEMBER",
  "NOTE_FOR",
  "NOTE",
  "CLASSDEF",
  "ALPHA",
  "COMMA",
  "direction_tb",
  "direction_bt",
  "direction_rl",
  "direction_lr",
  "AGGREGATION",
  "EXTENSION",
  "COMPOSITION",
  "DEPENDENCY",
  "LOLLIPOP",
  "LINE",
  "DOTTED_LINE",
  "CALLBACK",
  "LINK",
  "LINK_TARGET",
  "CLICK",
  "CALLBACK_NAME",
  "CALLBACK_ARGS",
  "HREF",
  "STYLE",
  "CSSCLASS",
  "COLON",
  "BRKT",
  "PCT",
  "MINUS",
  "UNICODE_TEXT",
  "BQUOTE_STR",
  "EDGE_STATE",
  "EOF_IN_STRUCT",
  "OPEN_IN_STRUCT",
  "PLUS",
  "EQUALS",
  "PUNCTUATION",
]

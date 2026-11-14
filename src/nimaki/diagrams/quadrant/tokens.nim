## port-of: src/diagrams/quadrant/tokens.ts
## port-status: conformant

const
  T_END* = 0
  T_ERROR* = 1
  T_NEWLINE* = 2
  T_title* = 3
  T_title_value* = 4
  T_acc_title* = 5
  T_acc_title_value* = 6
  T_acc_descr* = 7
  T_acc_descr_value* = 8
  T_acc_descr_multiline_value* = 9
  T_X_AXIS* = 10
  T_Y_AXIS* = 11
  T_DELIMITER* = 12
  T_QUADRANT_1* = 13
  T_QUADRANT_2* = 14
  T_QUADRANT_3* = 15
  T_QUADRANT_4* = 16
  T_CLASSDEF* = 17
  T_MD_STR* = 18
  T_STR* = 19
  T_class_name* = 20
  T_point_start* = 21
  T_point_x* = 22
  T_point_y* = 23
  T_QUADRANT* = 24
  T_ALPHA* = 25
  T_UNICODE_TEXT* = 26
  T_COLON* = 27
  T_PLUS* = 28
  T_COMMA* = 29
  T_EQUALS* = 30
  T_MULT* = 31
  T_BRKT* = 32
  T_UNDERSCORE* = 33
  T_DOT* = 34
  T_AMP* = 35
  T_MINUS* = 36
  T_NUM* = 37
  T_SPACE* = 38
  T_SEMI* = 39
  T_PUNCTUATION* = 40
  T_EOF* = 41

const TOKEN_NAMES*: array[42, string] = [
  "$end",
  "INVALID",
  "NEWLINE",
  "title",
  "title_value",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "X-AXIS",
  "Y-AXIS",
  "AXIS-TEXT-DELIMITER",
  "QUADRANT_1",
  "QUADRANT_2",
  "QUADRANT_3",
  "QUADRANT_4",
  "CLASSDEF",
  "MD_STR",
  "STR",
  "class_name",
  "point_start",
  "point_x",
  "point_y",
  "QUADRANT",
  "ALPHA",
  "UNICODE_TEXT",
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
  "SPACE",
  "SEMI",
  "PUNCTUATION",
  "EOF"]

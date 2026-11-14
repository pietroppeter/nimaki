## port-of: src/diagrams/er/tokens.ts
## port-status: conformant
##
## `const enum T` is `T_name` constants (the porting guide's names table).

const
  T_END* = 0
  T_ERROR* = 1
  T_ER_DIAGRAM* = 2
  T_EOF* = 3
  T_NEWLINE* = 4
  T_COLON* = 5
  T_STYLE_SEPARATOR* = 6
  T_BLOCK_START* = 7
  T_BLOCK_STOP* = 8
  T_SQS* = 9
  T_SQE* = 10
  T_acc_title* = 11
  T_acc_title_value* = 12
  T_acc_descr* = 13
  T_acc_descr_value* = 14
  T_acc_descr_multiline_value* = 15
  T_END_KW* = 16
  T_SUBGRAPH* = 17
  T_direction_tb* = 18
  T_direction_bt* = 19
  T_direction_rl* = 20
  T_direction_lr* = 21
  T_CLASSDEF* = 22
  T_UNICODE_TEXT* = 23
  T_STYLE_TEXT* = 24
  T_COMMA* = 25
  T_CLASS* = 26
  T_STYLE* = 27
  T_SEMI* = 28
  T_NUM* = 29
  T_BRKT* = 30
  T_ENTITY_NAME* = 31
  T_DECIMAL_NUM* = 32
  T_ENTITY_ONE* = 33
  T_ATTRIBUTE_WORD* = 34
  T_ATTRIBUTE_KEY* = 35
  T_COMMENT* = 36
  T_ZERO_OR_ONE* = 37
  T_ZERO_OR_MORE* = 38
  T_ONE_OR_MORE* = 39
  T_ONLY_ONE* = 40
  T_MD_PARENT* = 41
  T_NON_IDENTIFYING* = 42
  T_IDENTIFYING* = 43
  T_WORD* = 44
  # A character no rule names; the grammar gives it meaning only as `?` and `,` inside a block.
  T_CHAR* = 45

const TOKEN_NAMES*: array[46, string] = [
  "$end",
  "INVALID",
  "ER_DIAGRAM",
  "EOF",
  "NEWLINE",
  "COLON",
  "STYLE_SEPARATOR",
  "BLOCK_START",
  "BLOCK_STOP",
  "SQS",
  "SQE",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "END",
  "SUBGRAPH",
  "direction_tb",
  "direction_bt",
  "direction_rl",
  "direction_lr",
  "CLASSDEF",
  "UNICODE_TEXT",
  "STYLE_TEXT",
  "COMMA",
  "CLASS",
  "STYLE",
  "SEMI",
  "NUM",
  "BRKT",
  "ENTITY_NAME",
  "DECIMAL_NUM",
  "ENTITY_ONE",
  "ATTRIBUTE_WORD",
  "ATTRIBUTE_KEY",
  "COMMENT",
  "ZERO_OR_ONE",
  "ZERO_OR_MORE",
  "ONE_OR_MORE",
  "ONLY_ONE",
  "MD_PARENT",
  "NON_IDENTIFYING",
  "IDENTIFYING",
  "WORD",
  "CHAR",
]

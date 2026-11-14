## port-of: src/diagrams/requirement/tokens.ts
## port-status: conformant
##
## `const enum T` is `T_name` constants (the porting guide's names table).
import std/tables

const
  T_END* = 0
  T_ERROR* = 1
  T_title* = 2
  T_acc_title* = 3
  T_acc_title_value* = 4
  T_acc_descr* = 5
  T_acc_descr_value* = 6
  T_acc_descr_multiline_value* = 7
  T_direction_tb* = 8
  T_direction_bt* = 9
  T_direction_rl* = 10
  T_direction_lr* = 11
  T_NEWLINE* = 12
  T_EOF* = 13
  T_RD* = 14
  T_STRUCT_START* = 15
  T_STRUCT_STOP* = 16
  T_STYLE_SEPARATOR* = 17
  T_COLONSEP* = 18
  T_ID* = 19
  T_TEXT* = 20
  T_RISK* = 21
  T_VERIFYMTHD* = 22
  T_REQUIREMENT* = 23
  T_FUNCTIONAL_REQUIREMENT* = 24
  T_INTERFACE_REQUIREMENT* = 25
  T_PERFORMANCE_REQUIREMENT* = 26
  T_PHYSICAL_REQUIREMENT* = 27
  T_DESIGN_CONSTRAINT* = 28
  T_LOW_RISK* = 29
  T_MED_RISK* = 30
  T_HIGH_RISK* = 31
  T_VERIFY_ANALYSIS* = 32
  T_VERIFY_DEMONSTRATION* = 33
  T_VERIFY_INSPECTION* = 34
  T_VERIFY_TEST* = 35
  T_ELEMENT* = 36
  T_CONTAINS* = 37
  T_COPIES* = 38
  T_DERIVES* = 39
  T_SATISFIES* = 40
  T_VERIFIES* = 41
  T_REFINES* = 42
  T_TRACES* = 43
  T_TYPE* = 44
  T_DOCREF* = 45
  T_STYLE* = 46
  T_CLASSDEF* = 47
  T_CLASS* = 48
  T_ALPHA* = 49
  T_COLON* = 50
  T_SEMICOLON* = 51
  T_PERCENT* = 52
  T_MINUS* = 53
  T_BRKT* = 54
  T_END_ARROW_L* = 55
  T_END_ARROW_R* = 56
  T_LINE* = 57
  T_qString* = 58
  T_unqString* = 59
  T_COMMA* = 60

const TOKEN_NAMES*: array[61, string] = [
  "$end",
  "INVALID",
  "title",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "direction_tb",
  "direction_bt",
  "direction_rl",
  "direction_lr",
  "NEWLINE",
  "EOF",
  "RD",
  "STRUCT_START",
  "STRUCT_STOP",
  "STYLE_SEPARATOR",
  "COLONSEP",
  "ID",
  "TEXT",
  "RISK",
  "VERIFYMTHD",
  "REQUIREMENT",
  "FUNCTIONAL_REQUIREMENT",
  "INTERFACE_REQUIREMENT",
  "PERFORMANCE_REQUIREMENT",
  "PHYSICAL_REQUIREMENT",
  "DESIGN_CONSTRAINT",
  "LOW_RISK",
  "MED_RISK",
  "HIGH_RISK",
  "VERIFY_ANALYSIS",
  "VERIFY_DEMONSTRATION",
  "VERIFY_INSPECTION",
  "VERIFY_TEST",
  "ELEMENT",
  "CONTAINS",
  "COPIES",
  "DERIVES",
  "SATISFIES",
  "VERIFIES",
  "REFINES",
  "TRACES",
  "TYPE",
  "DOCREF",
  "STYLE",
  "CLASSDEF",
  "CLASS",
  "ALPHA",
  "COLON",
  "SEMICOLON",
  "PERCENT",
  "MINUS",
  "BRKT",
  "END_ARROW_L",
  "END_ARROW_R",
  "LINE",
  "qString",
  "unqString",
  "COMMA",
]

# Every keyword is matched without regard to case and must end at a word boundary.
const KEYWORDS* = {
  "requirementdiagram": T_RD,
  "id": T_ID,
  "text": T_TEXT,
  "risk": T_RISK,
  "verifymethod": T_VERIFYMTHD,
  "requirement": T_REQUIREMENT,
  "functionalrequirement": T_FUNCTIONAL_REQUIREMENT,
  "interfacerequirement": T_INTERFACE_REQUIREMENT,
  "performancerequirement": T_PERFORMANCE_REQUIREMENT,
  "physicalrequirement": T_PHYSICAL_REQUIREMENT,
  "designconstraint": T_DESIGN_CONSTRAINT,
  "low": T_LOW_RISK,
  "medium": T_MED_RISK,
  "high": T_HIGH_RISK,
  "analysis": T_VERIFY_ANALYSIS,
  "demonstration": T_VERIFY_DEMONSTRATION,
  "inspection": T_VERIFY_INSPECTION,
  "test": T_VERIFY_TEST,
  "element": T_ELEMENT,
  "contains": T_CONTAINS,
  "copies": T_COPIES,
  "derives": T_DERIVES,
  "satisfies": T_SATISFIES,
  "verifies": T_VERIFIES,
  "refines": T_REFINES,
  "traces": T_TRACES,
  "type": T_TYPE,
  "docref": T_DOCREF,
  "style": T_STYLE,
  "classdef": T_CLASSDEF,
  "class": T_CLASS,
}.toTable

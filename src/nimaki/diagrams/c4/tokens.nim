## port-of: src/diagrams/c4/tokens.ts
## port-status: draft

const
  T_STOP* = 0
  T_ERROR* = 1
  T_direction_tb* = 2
  T_direction_bt* = 3
  T_direction_rl* = 4
  T_direction_lr* = 5
  T_title* = 6
  T_accDescription* = 7
  T_acc_title* = 8
  T_acc_title_value* = 9
  T_acc_descr* = 10
  T_acc_descr_value* = 11
  T_acc_descr_multiline_value* = 12
  T_NEWLINE* = 13
  T_C4_CONTEXT* = 14
  T_C4_CONTAINER* = 15
  T_C4_COMPONENT* = 16
  T_C4_DYNAMIC* = 17
  T_C4_DEPLOYMENT* = 18
  T_PERSON* = 19
  T_PERSON_EXT* = 20
  T_SYSTEM* = 21
  T_SYSTEM_DB* = 22
  T_SYSTEM_QUEUE* = 23
  T_SYSTEM_EXT* = 24
  T_SYSTEM_EXT_DB* = 25
  T_SYSTEM_EXT_QUEUE* = 26
  T_CONTAINER* = 27
  T_CONTAINER_DB* = 28
  T_CONTAINER_QUEUE* = 29
  T_CONTAINER_EXT* = 30
  T_CONTAINER_EXT_DB* = 31
  T_CONTAINER_EXT_QUEUE* = 32
  T_COMPONENT* = 33
  T_COMPONENT_DB* = 34
  T_COMPONENT_QUEUE* = 35
  T_COMPONENT_EXT* = 36
  T_COMPONENT_EXT_DB* = 37
  T_COMPONENT_EXT_QUEUE* = 38
  T_ENTERPRISE_BOUNDARY* = 39
  T_SYSTEM_BOUNDARY* = 40
  T_BOUNDARY* = 41
  T_CONTAINER_BOUNDARY* = 42
  T_NODE* = 43
  T_NODE_L* = 44
  T_NODE_R* = 45
  T_REL* = 46
  T_BIREL* = 47
  T_REL_U* = 48
  T_REL_D* = 49
  T_REL_L* = 50
  T_REL_R* = 51
  T_REL_B* = 52
  T_REL_INDEX* = 53
  T_UPDATE_EL_STYLE* = 54
  T_UPDATE_REL_STYLE* = 55
  T_UPDATE_LAYOUT_CONFIG* = 56
  T_EOF_IN_STRUCT* = 57
  T_ATTRIBUTE_EMPTY* = 58
  T_STR* = 59
  T_STR_KEY* = 60
  T_STR_VALUE* = 61
  T_LBRACE* = 62
  T_RBRACE* = 63
  T_EOF* = 64

const TOKEN_NAMES*: array[65, string] = [
  "$end",
  "INVALID",
  "direction_tb",
  "direction_bt",
  "direction_rl",
  "direction_lr",
  "title",
  "accDescription",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "NEWLINE",
  "C4_CONTEXT",
  "C4_CONTAINER",
  "C4_COMPONENT",
  "C4_DYNAMIC",
  "C4_DEPLOYMENT",
  "PERSON",
  "PERSON_EXT",
  "SYSTEM",
  "SYSTEM_DB",
  "SYSTEM_QUEUE",
  "SYSTEM_EXT",
  "SYSTEM_EXT_DB",
  "SYSTEM_EXT_QUEUE",
  "CONTAINER",
  "CONTAINER_DB",
  "CONTAINER_QUEUE",
  "CONTAINER_EXT",
  "CONTAINER_EXT_DB",
  "CONTAINER_EXT_QUEUE",
  "COMPONENT",
  "COMPONENT_DB",
  "COMPONENT_QUEUE",
  "COMPONENT_EXT",
  "COMPONENT_EXT_DB",
  "COMPONENT_EXT_QUEUE",
  "ENTERPRISE_BOUNDARY",
  "SYSTEM_BOUNDARY",
  "BOUNDARY",
  "CONTAINER_BOUNDARY",
  "NODE",
  "NODE_L",
  "NODE_R",
  "REL",
  "BIREL",
  "REL_U",
  "REL_D",
  "REL_L",
  "REL_R",
  "REL_B",
  "REL_INDEX",
  "UPDATE_EL_STYLE",
  "UPDATE_REL_STYLE",
  "UPDATE_LAYOUT_CONFIG",
  "EOF_IN_STRUCT",
  "ATTRIBUTE_EMPTY",
  "STR",
  "STR_KEY",
  "STR_VALUE",
  "LBRACE",
  "RBRACE",
  "EOF",
]

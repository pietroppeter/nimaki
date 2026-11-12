## port-of: src/diagrams/sequence/tokens.ts
## port-status: draft
##
## `const enum T` is `T_name` constants (the porting guide's names table).

const
  T_STOP* = 0  ## Pele's `T.END`; `T_end` is the `end` keyword
  T_ERROR* = 1
  T_INVALID* = 2
  T_NEWLINE* = 3
  T_SD* = 4
  T_create* = 5
  T_box* = 6
  T_restOfLine* = 7
  T_end* = 8
  T_autonumber* = 9
  T_NUM* = 10
  T_off* = 11
  T_activate* = 12
  T_deactivate* = 13
  T_title* = 14
  T_legacy_title* = 15
  T_acc_title* = 16
  T_acc_title_value* = 17
  T_acc_descr* = 18
  T_acc_descr_value* = 19
  T_acc_descr_multiline_value* = 20
  T_loop* = 21
  T_rect* = 22
  T_opt* = 23
  T_alt* = 24
  T_par* = 25
  T_par_over* = 26
  T_critical* = 27
  T_break* = 28
  T_option* = 29
  T_and* = 30
  T_else* = 31
  T_participant* = 32
  T_AS* = 33
  T_participant_actor* = 34
  T_destroy* = 35
  T_note* = 36
  T_over* = 37
  T_links* = 38
  T_link* = 39
  T_properties* = 40
  T_details* = 41
  T_COMMA* = 42
  T_left_of* = 43
  T_right_of* = 44
  T_PLUS* = 45
  T_MINUS* = 46
  T_CENTRAL* = 47
  T_ACTOR* = 48
  T_CONFIG_START* = 49
  T_CONFIG_CONTENT* = 50
  T_CONFIG_END* = 51
  T_TXT* = 52
  T_SOLID_OPEN_ARROW* = 53
  T_DOTTED_OPEN_ARROW* = 54
  T_SOLID_ARROW* = 55
  T_BIDIRECTIONAL_SOLID_ARROW* = 56
  T_DOTTED_ARROW* = 57
  T_BIDIRECTIONAL_DOTTED_ARROW* = 58
  T_SOLID_CROSS* = 59
  T_DOTTED_CROSS* = 60
  T_SOLID_POINT* = 61
  T_DOTTED_POINT* = 62
  T_SOLID_ARROW_TOP* = 63
  T_SOLID_ARROW_BOTTOM* = 64
  T_STICK_ARROW_TOP* = 65
  T_STICK_ARROW_BOTTOM* = 66
  T_SOLID_ARROW_TOP_DOTTED* = 67
  T_SOLID_ARROW_BOTTOM_DOTTED* = 68
  T_STICK_ARROW_TOP_DOTTED* = 69
  T_STICK_ARROW_BOTTOM_DOTTED* = 70
  T_SOLID_ARROW_TOP_REVERSE* = 71
  T_SOLID_ARROW_BOTTOM_REVERSE* = 72
  T_STICK_ARROW_TOP_REVERSE* = 73
  T_STICK_ARROW_BOTTOM_REVERSE* = 74
  T_SOLID_ARROW_TOP_REVERSE_DOTTED* = 75
  T_SOLID_ARROW_BOTTOM_REVERSE_DOTTED* = 76
  T_STICK_ARROW_TOP_REVERSE_DOTTED* = 77
  T_STICK_ARROW_BOTTOM_REVERSE_DOTTED* = 78

const TOKEN_NAMES* = [
  ## Names as Mermaid's grammar spells them, for error messages and for comparison with its parser.
  "$end",
  "INVALID",
  "INVALID",
  "NEWLINE",
  "SD",
  "create",
  "box",
  "restOfLine",
  "end",
  "autonumber",
  "NUM",
  "off",
  "activate",
  "deactivate",
  "title",
  "legacy_title",
  "acc_title",
  "acc_title_value",
  "acc_descr",
  "acc_descr_value",
  "acc_descr_multiline_value",
  "loop",
  "rect",
  "opt",
  "alt",
  "par",
  "par_over",
  "critical",
  "break",
  "option",
  "and",
  "else",
  "participant",
  "AS",
  "participant_actor",
  "destroy",
  "note",
  "over",
  "links",
  "link",
  "properties",
  "details",
  ",",
  "left_of",
  "right_of",
  "+",
  "-",
  "()",
  "ACTOR",
  "CONFIG_START",
  "CONFIG_CONTENT",
  "CONFIG_END",
  "TXT",
  "SOLID_OPEN_ARROW",
  "DOTTED_OPEN_ARROW",
  "SOLID_ARROW",
  "BIDIRECTIONAL_SOLID_ARROW",
  "DOTTED_ARROW",
  "BIDIRECTIONAL_DOTTED_ARROW",
  "SOLID_CROSS",
  "DOTTED_CROSS",
  "SOLID_POINT",
  "DOTTED_POINT",
  "SOLID_ARROW_TOP",
  "SOLID_ARROW_BOTTOM",
  "STICK_ARROW_TOP",
  "STICK_ARROW_BOTTOM",
  "SOLID_ARROW_TOP_DOTTED",
  "SOLID_ARROW_BOTTOM_DOTTED",
  "STICK_ARROW_TOP_DOTTED",
  "STICK_ARROW_BOTTOM_DOTTED",
  "SOLID_ARROW_TOP_REVERSE",
  "SOLID_ARROW_BOTTOM_REVERSE",
  "STICK_ARROW_TOP_REVERSE",
  "STICK_ARROW_BOTTOM_REVERSE",
  "SOLID_ARROW_TOP_REVERSE_DOTTED",
  "SOLID_ARROW_BOTTOM_REVERSE_DOTTED",
  "STICK_ARROW_TOP_REVERSE_DOTTED",
  "STICK_ARROW_BOTTOM_REVERSE_DOTTED",
]

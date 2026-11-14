## port-of: src/diagrams/requirement/types.ts
## port-status: conformant
##
## `type` is `kind` (the porting guide's names table).

type
  Requirement* = ref object
    name*: string
    kind*: string
    requirementId*: string
    text*: string
    risk*: string
    verifyMethod*: string
    cssStyles*: seq[string]
    classes*: seq[string]

  RequirementElement* = ref object
    name*: string
    kind*: string
    docRef*: string
    cssStyles*: seq[string]
    classes*: seq[string]

  Relation* = object
    kind*: string
    src*: string
    dst*: string

  RequirementClass* = ref object
    id*: string
    styles*: seq[string]
    textStyles*: seq[string]

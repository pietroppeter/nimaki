## port-of: src/diagrams/class/types.ts
## port-status: draft
##
## Port notes: an optional string that is never empty when set is a string, "" for undefined.
## `RelationEnd` (a number or 'none') is an int, NONE (-1) for 'none'. Maps are ordered tables.
import std/tables
import members

const NONE* = -1
  ## RelationEnd 'none'

type
  RelationEnd* = int

  ClassNode* = ref object
    id*: string
    kind*: string        ## Pele's `type`: the generic type, "" for none
    label*: string
    cssClasses*: string
    methods*: seq[ClassMember]
    members*: seq[ClassMember]
    annotations*: seq[string]
    styles*: seq[string]
    parent*: string      ## "" for undefined
    link*: string        ## "" for undefined
    linkTarget*: string  ## "" for undefined
    haveCallback*: bool
    tooltip*: string     ## "" for undefined

  Relation* = object
    type1*, type2*: RelationEnd
    lineType*: int

  ClassRelation* = ref object
    id1*, id2*: string
    relationTitle1*, relationTitle2*: string
    title*: string       ## "" for undefined
    relation*: Relation

  ClassNote* = ref object
    id*: string
    class*: string       ## "" for undefined
    text*: string
    index*: int
    parent*: string      ## "" for undefined

  ClassInterface* = object
    id*, label*, classId*: string

  NamespaceNode* = ref object
    id*, label*: string
    classes*: OrderedTable[string, ClassNode]
    notes*: OrderedTable[string, ClassNote]
    children*: OrderedTable[string, NamespaceNode]
    parent*: string      ## "" for undefined
    explicit*: bool
      ## False for the ancestors created on the way to a dotted name such as `A.B.C`.

  StyleClass* = ref object
    id*: string
    styles*, textStyles*: seq[string]

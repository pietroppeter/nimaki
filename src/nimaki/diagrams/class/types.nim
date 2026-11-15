## port-of: src/diagrams/class/types.ts
## port-status: conformant
##
## Port notes: an optional string that is never empty when set is a string, "" for undefined.
## `RelationEnd` (a number or 'none') is an int, NONE (-1) for 'none'. Maps are ordered tables.
import std/[hashes, options, tables]
import members
import ../../model

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
    parent* {.undefinedIfEmpty.}: string      ## "" for undefined
    link* {.undefinedIfEmpty.}: string        ## "" for undefined
    linkTarget* {.undefinedIfEmpty.}: string  ## "" for undefined
    haveCallback*: Option[bool]   ## some(true) once a callback is set, none before
    tooltip* {.undefinedIfEmpty.}: string     ## "" for undefined

  Relation* = object
    ## (tools/models.nim writes NONE as Pele's 'none'.)
    type1*, type2*: RelationEnd
    lineType*: int

  ClassRelation* = ref object
    id1*, id2*: string
    relationTitle1*, relationTitle2*: string
    title* {.undefinedIfEmpty.}: string       ## "" for undefined
    relation*: Relation

func hash*(x: ClassNode): Hash = hash(x.id)
  ## For sets of classes, which compare them by identity: two classes never share an id.

type
  ClassNote* = ref object
    id*: string
    class* {.undefinedIfEmpty.}: string       ## "" for undefined
    text*: string
    index*: int
    parent* {.undefinedIfEmpty.}: string      ## "" for undefined

  ClassInterface* = object
    id*, label*, classId*: string

  NamespaceNode* = ref object
    id*, label*: string
    classes*: OrderedTable[string, ClassNode]
    notes*: OrderedTable[string, ClassNote]
    children*: OrderedTable[string, NamespaceNode]
    parent* {.undefinedIfEmpty.}: string      ## "" for undefined
    explicit*: bool
      ## False for the ancestors created on the way to a dotted name such as `A.B.C`.

  StyleClass* = ref object
    id*: string
    styles*, textStyles*: seq[string]

## port-of: src/diagrams/ishikawa/types.ts
## port-status: conformant

type
  IshikawaNode* = ref object
    text*: string
    children*: seq[IshikawaNode]

  IshikawaModel* = ref object of RootObj
    ## The root is the effect; its children are the categories of causes, theirs the causes, and so on.
    title*: string               ## "" for undefined
    root*: IshikawaNode          ## nil for undefined

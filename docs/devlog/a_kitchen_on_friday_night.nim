## devlog: 14 Nov 2026 A | A kitchen on a Friday night | How a restaurant kitchen gets a full room's plates out hot and together, in seven diagrams drawn by nimaki: the second domain article, made with the types no article had used yet.
## kind: article
import std/[strformat, strutils, json, tables, options, sequtils]
import nimib
import ../blocks, ../pele
import nimaki

nbInit
nb.usePost()

# Every diagram of the page, by name: drawn by nimaki for a phone-wide column, and by Pele in
# Node with the same options, to check that the two agree byte for byte.
const phone = 390.0
let diagrams = {
  "brigade": """mindmap
  root((The brigade))
    Chef de cuisine
      Sous-chef
        Chefs de partie
          Saucier: sauces
          Poissonnier: fish
          Rôtisseur: roasts
          Entremetier: vegetables
          Garde manger: cold
          Pâtissier: pastry
        Commis
    The pass
      Expediter
    Front of house
      Servers
      Runners
    Dish pit
      Kitchen porter
""",
  "handoff": """swimlane-beta LR
  subgraph Guest
    Order[Order]
    Eat[Eat]
  end
  subgraph Server
    Take[Take the order]
    Serve[Carry to the table]
  end
  subgraph Expediter
    Call[Call the ticket]
    Check[Check the plate]
  end
  subgraph Line
    Cook[Cook]
    Plate[Plate]
  end
  Order --> Take
  Take --> Call
  Call --> Cook
  Cook --> Plate
  Plate --> Check
  Check --> Serve
  Serve --> Eat
""",
  "rail": """kanban
  waiting[Ordered]
    t14[Table 14: two steak, one bream]@{ assigned: 'grill', priority: 'High' }
    t9[Table 9: risotto]@{ assigned: 'sauce' }
  fired[Fired]
    t12[Table 12: four mains]@{ assigned: 'grill', priority: 'Very High' }
    t7[Table 7: tasting menu, course 3]@{ assigned: 'fish' }
  pass[On the pass]
    t5[Table 5: two desserts]@{ assigned: 'pastry' }
  gone[Served]
    t3[Table 3: starters]
    t2[Table 2: mains]
""",
  "timing": """gantt
  title Four mains for table 12, timed back from 20:30
  dateFormat HH:mm
  axisFormat %H:%M
  section Grill
  Ribeye on the grill   :g1, 20:08, 14m
  Ribeye rests          :g2, after g1, 8m
  section Fish
  Bream in the pan      :f1, 20:21, 9m
  section Vegetables
  Roast roots           :v1, 20:00, 25m
  Greens                :v2, 20:26, 4m
  section Pass
  Plate and check       :milestone, p1, 20:30, 0m
""",
  "order": """eventmodeling
tf 01 ui TableTablet
tf 02 cmd PlaceOrder { table: 12, covers: 4 }
tf 03 evt OrderPlaced
tf 04 rmo TicketRail
tf 05 ui KitchenScreen ->> 04
tf 06 cmd FireCourse { course: mains }
tf 07 evt CourseFired
tf 08 rmo PassBoard
tf 09 ui ExpoScreen ->> 08
tf 10 cmd SendPlates
tf 11 evt PlatesServed
""",
  "guest": """journey
  title A guest's Friday night
  section Arrive
    Greeted at the door: 4: Guest, Host
    Wait for the table: 2: Guest
  section Eat
    Order: 4: Guest, Server
    Starters arrive: 5: Guest
    Long wait for mains: 1: Guest
    Mains arrive, one cold: 2: Guest, Server
    Dish remade: 4: Guest, Expediter
  section Leave
    Dessert on the house: 5: Guest, Server
    Pay and go: 4: Guest
""",
  "cold": """ishikawa-beta
    A main came back cold
    Method
        Fired too early
        Waited on the pass
    Machine
        Heat lamp off
        Salamander slow
    Material
        Plates not warmed
    Manpower
        Runner busy elsewhere
        New commis on the grill
    Measurement
        No timer on the rest
    Milieu
        Door to the terrace open
""",
}.toOrderedTable

var drawn = initOrderedTable[string, RenderResult]()
var wideOnes = initOrderedTable[string, float]()   # how wide each drawing is without maxWidth
for name, text in diagrams:
  drawn[name] = render(text, RenderOptions(maxWidth: some(phone), now: fixedNow))
  wideOnes[name] = render(text, RenderOptions(now: fixedNow)).width
var sources: seq[string]
for text in diagrams.values: sources.add text
let fromPele = peleRenders(sources, %*{"maxWidth": phone})
var identical = 0
var i = 0
for name, r in drawn:
  if fromPele[i]{"svg"}.getStr == r.svg: inc identical
  inc i
var types: seq[string]
for r in drawn.values: types.add r.diagramType
var wide: seq[string]   # the drawings wider than a phone even with maxWidth
for name, r in drawn:
  if r.width > phone: wide.add name
doAssert wide == @["handoff"], "the text says which drawings stay wide: " & $wide
let widest = toSeq(wideOnes.values).max

proc show(name, caption: string) =
  ## A diagram of the page, then its Mermaid text, folded.
  nbSvg drawn[name].svg, caption
  nbFold "The Mermaid text of this diagram":
    nbText &"```mermaid\n{diagrams[name].strip}\n```\n"

nbText: &"""
The [first article](../opening-a-web-page/) followed a web page from address to screen. This one
goes somewhere louder: a restaurant kitchen at eight on a Friday, when a hundred guests order
within the same hour and every table expects its plates hot, right and *together*. A kitchen is
an information system with knives. It has roles, a queue, a protocol of spoken calls, schedules
measured in minutes, and a way of finding out why something went wrong. Each has a diagram type
that fits it, and this time they are the types no article had used yet, all of them ported to
nimaki in the last two days.

## The findings, first

- **{diagrams.len} diagrams of {diagrams.len} types, drawn by nimaki.** A mindmap, a swimlane, a
  kanban board, a gantt chart, an event model, a user journey and an ishikawa diagram; three of
  them (mindmap, kanban, event modeling) joined the port only yesterday.
- **{identical} of {diagrams.len} identical to Pele's**, checked when the page is built, with the
  same `maxWidth` of {phone.int} pixels. Using the newest parts of the port for real found nothing
  to fix.
- **These types were made for phones.** Without `maxWidth` the widest of them is
  {widest.int} pixels. With it, every one of the {diagrams.len} changes shape: the mindmap grows
  downwards, the board stacks its columns, the event model turns into a column of cards. Only the
  swimlane stays wider than a phone ({drawn["handoff"].width.int} pixels), because four lanes
  side by side need room. In the first article, two of ten stayed wide.
- **Names with accents measure right.** *Rôtisseur* and *Pâtissier* are measured with the same
  font tables as Pele's, and the bytes agree: the work on UTF-16 strings in the port holds.

## Who does what: a mindmap

Most restaurant kitchens are still organised the way Auguste Escoffier set out at the end of the
nineteenth century, as a *brigade*: a chef at the top, a second (the *sous-chef*), and a line of
*chefs de partie*, each running one station, helped by junior cooks (*commis*). A **mindmap**
draws such a thing: one idea in the middle, branches for its parts, and their parts further out.
It is not a strict hierarchy, which suits a kitchen, where the pass and the dish pit matter as
much as rank.
"""

show "brigade", "The brigade of a kitchen, after Escoffier's. On a phone the mindmap grows downwards from its root. Drawn by nimaki."

nbText: """
## Who hands what to whom: a swimlane

An order crosses four pairs of hands before it is eaten. A **swimlane** diagram is a flowchart
whose boxes sit in lanes, one lane per actor, so that every arrow crossing a lane line is a
*handoff*: the moment where something can wait, get lost or go cold. Here the key figure is the
*expediter*, the person at the pass (the counter between kitchen and dining room) who calls
the tickets to the cooks and checks every plate before it leaves.
"""

show "handoff", "One order through four lanes. Every arrow that crosses a lane line is a handoff. Drawn by nimaki."

nbText: """
The calls themselves are a protocol, as strict as the handshakes of the first article. The
expediter calls *"Ordering: table twelve, two ribeye, one bream"*, the stations answer *"Heard"*
or *"Yes, chef"*, and later *"Fire table twelve"* means start cooking now. Each call gets an
answer so that nothing is assumed: an acknowledgment, as in TCP.

## What is cooking: a kanban board

The orders wait on a *ticket rail*, a metal strip above the pass that holds the paper tickets in
order. That rail is a **kanban** board before the name: *kanban* is Japanese for a signboard, and
the method came from Toyota's factories, where a card travelling with the parts told each station
what to make next. A kanban board has a column for each stage and a card for each piece of work;
the cards move right.
"""

show "rail", "The ticket rail as a board: what is ordered, fired, waiting on the pass and served. A bar on the left of a card marks its priority; the station is in its corner. Drawn by nimaki."

nbText: """
## When to start: a gantt chart, timed backwards

The hardest trick of a line is not cooking a dish but finishing four different dishes at the
same moment. A ribeye takes fourteen minutes and must rest eight; a bream takes nine; roast roots
take twenty-five. So a kitchen schedules *backwards*: from the time the plates must meet on the
pass, it subtracts each cooking time to find when each must start. A **gantt chart** is a
timeline of tasks, and drawn from the deadline back it shows why the vegetables start first and
the fish last.
"""

show "timing", "Four mains timed back from 20:30. The diamond is a milestone: the moment the plates meet on the pass. Drawn by nimaki."

nbText: """
## What happened to an order: an event model

The calls, the tickets and the rail are an information system, and many kitchens now run it on
screens. **Event modeling**, a method proposed by Adam Dymitruk, designs such a system as a story
told left to right: a screen (`ui`) lets someone give a command (`cmd`), the command records an
event (`evt`), which is a fact that cannot be undone, and events update a read model (`rmo`), the
view that the next screen shows. The ticket rail is a read model; *course fired* is an event.
"""

show "order", "An order as an event model. Each lane is a kind of step; on a phone the frames become a column of cards, and an arrow that skips ahead runs down a rail beside them. Drawn by nimaki."

nbText: """
## How the guest felt: a user journey

The kitchen sees tickets; the guest sees an evening. A **user journey** follows one person through
a task, step by step, with a score from 1 to 5 for how each step felt, drawn as a face, and the
people involved. It is how designers find the low points worth fixing. In this one, the low
point is a long wait and a cold plate, and the recovery (a remade dish, a dessert on the house)
is what the guest will remember.
"""

show "guest", "A guest's evening, scored step by step. Drawn by nimaki."

nbText: """
## Why the plate came back: an ishikawa diagram

After service, the kitchen asks why the main came back cold. An **ishikawa** diagram, also called
a fishbone or cause-and-effect diagram after the quality engineer Kaoru Ishikawa, puts the
problem at the head and groups possible causes into bones. A common set of bones in
manufacturing is the *six Ms*: method, machine, material, manpower, measurement and milieu (the
environment). The point is to look at every bone before blaming the first cause that comes to
mind, which, in a kitchen, is usually the newest cook.
"""

show "cold", "Why a main came back cold, by the six Ms. Drawn by nimaki."

nbText: &"""
## What drawing taught about nimaki

The diagrams of this article come from the newest parts of the port, so this is the first time
most of them were used for something other than a test.
"""

nbNote &"""
Every drawing above, {identical} of {diagrams.len}, is byte for byte the one Pele draws in Node
with the same options. The comparison runs every time the page is built.
""", nkDone, "Checked"

nbText: &"""
- **Phone layouts are the rule for the newer types.** All {diagrams.len} change shape under
  `maxWidth`; the {drawn["guest"].diagramType} drawing goes from {wideOnes["guest"].int} pixels
  wide to {drawn["guest"].width.int}, the board from {wideOnes["rail"].int} to
  {drawn["rail"].width.int}. The only one still wider than a phone is the swimlane, at
  {drawn["handoff"].width.int}.
- **The texts are easy to write.** Mindmap, ishikawa and kanban are plain indented outlines, which
  made them the quickest to write of any diagrams so far; event modeling needs its frame numbers
  kept in order by hand.
- **The page is the same five lines as last time.** The helper that draws a text, shows it and
  folds the source under it was copied from the first article. That makes it needed a second
  time, which by the rules of the pages means it should become a block: the roadmap step
  `mermaid-block` is now wanted by two pages.
"""

nbText: &"""
## The next articles

Proposed next, still: **how a bill becomes a law** (a flowchart, a sequence between two chambers,
a timeline, a state diagram of a bill), and **where a library's data lives** (entity–relationship
and class diagrams, requirements, a git graph of releases, a treemap). When sankey, quadrant, venn
and xy charts are ported, an article on **where the money in a household goes** would use them
all.

## What this changes for the port

- Nothing to fix: the {diagrams.len} drawings of this article are new inputs the port draws as
  Pele does.
- The roadmap step `mermaid-block` gains a second page that would use it.

## Sources

- Kitchen practice: [Brigade de cuisine](https://en.wikipedia.org/wiki/Brigade_de_cuisine) and
  [Auguste Escoffier](https://en.wikipedia.org/wiki/Auguste_Escoffier) on Wikipedia; the calls
  of the pass are common kitchen usage.
- The methods: [Kanban](https://en.wikipedia.org/wiki/Kanban) and
  [Ishikawa diagram](https://en.wikipedia.org/wiki/Ishikawa_diagram) on Wikipedia;
  [eventmodeling.org](https://eventmodeling.org/), the method's own site.
- Wikipedia and eventmodeling.org could not be reached from the sandbox this article was written
  in: the facts here are as the author knows them, and the links were not opened while writing.
  The restaurant, its tables, times and complaints are invented.
- Each diagram type has its own port post: [mindmap, kanban and event modeling](../mindmap-kanban-eventmodeling/),
  [swimlane](../lanes-and-handoffs/), [gantt](../gantt-charts/),
  [journey](../three-small-diagrams/) and [ishikawa](../fishbones-and-domains/); what each type is
  used for is in [Diagrams in the wild](../diagrams-in-the-wild/).
"""

nbSave

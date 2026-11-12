## devlog: 12 Nov 2026 I | Drawing a diagram from scratch | How text becomes a drawing, in five stages, with a toy renderer that runs on this page: lexing, parsing, measuring text, layered layout and SVG.
## kind: research
import std/[os, sequtils, strformat, strutils]
import nimib
import tabelline, tabelline/nimib
import ../blocks
import data/drawing_a_diagram/lapilli

nbInit
nb.usePost()

nbText: """
## The short version

- A diagram renderer is a **relay race of five stages**: *lex* the text into tokens, *parse* the
  tokens into a model, *measure* every label, *lay out* the boxes and lines, *write* the SVG.
  Pele does exactly this for each of its 33 diagram types.
- To show what each stage does, this post builds **Lapilli**, a toy renderer for a tiny piece of
  Mermaid's flowchart syntax, in about 400 lines of Nim
  ([`lapilli.nim`](https://github.com/pietroppeter/nimaki/blob/main/docs/devlog/data/drawing_a_diagram/lapilli.nim)).
  Every drawing on this page is drawn by it while the page is built.
- **Parsing** is the most code but the least mystery: one small procedure per grammar rule.
- **Layout** is where the ideas are. The classic recipe for flowcharts (Sugiyama's *layered*
  layout) is five steps that each have a simple version, and Pele's version of each is far from
  simple.
- **Measuring text** without a browser is a lookup table. **Writing SVG** is string building, with
  one rule: format every number the same way.

Lapilli are the small stones a volcano throws: a very small Pele. It is ours, not a port, and does
none of Pele's careful work. Here it is, drawing its own pipeline:
"""

const pipeline = """flowchart TD
text[Mermaid text] --> lexer[Lexer] --> parser[Parser] --> model[Model]
model --> measure[Measure text] --> layout[Lay out] --> writer[Write SVG]
model --> layout
writer --> svg[An SVG file]
"""

nbCode:
  echo pipeline

nbSvg(render(pipeline), "Lapilli draws itself. Lapilli's syntax: a line is a chain of nodes joined by -->; a node is a name, with its text in square brackets.")

nbText: """
## 1. Lexing: from characters to tokens

A program cannot read `parser[Parser] --> model` the way you do. It sees a row of characters:
`p`, `a`, `r`, ... The **lexer** (or *tokenizer*) groups them into **tokens**, the words of the
language: a name, a text in brackets, an arrow, a line break. It throws away what does not matter
(spaces, comments) and remembers where each token started, for error messages.

A lexer is a loop over the characters that looks at the current one (and sometimes the next few)
and decides which kind of token starts here. Lapilli's has six kinds:
"""

nbCode:
  for t in lex("flowchart TD\nidea[An idea] --> sketch\n")[0 .. 6]:
    echo ($t.kind).alignLeft(8), " ", t.text.escape.alignLeft(12), " line ", t.line, ", column ", t.col

nbText: """
When no token fits, the lexer stops with an error that says where:
"""

nbCode:
  try:
    discard lex("flowchart TD\nidea --> sketch!\n")
  except LapilliError as e:
    echo e.msg

nbNote("""Pele has a lexer per diagram type, and two kinds of them, because Mermaid has two
kinds of grammars. The older types (flowchart, sequence, class...) are written in **Jison**,
whose lexer has *modes* (inside a string, inside an edge label): the same characters mean
different things in different modes, so Pele's `lexer.ts` files are state machines, the
flowchart's with 18 states. The newer types (pie, packet, git...) use **Langium**, whose lexer is
an ordered list of patterns where the first that matches wins; Pele has one shared tokenizer for
those, `diagrams/common/tokens.ts`, and each type gives it a table.""", nkPele, "How Pele does it")

nbText: """
## 2. Parsing: from tokens to a model

The tokens are words; the **parser** checks that they form sentences of the language and builds
the **model**: the diagram as data, here a list of nodes and a list of edges. What counts as a
sentence is written down as a **grammar**:

```
diagram   = "flowchart" direction? newline* (statement newline*)* end
statement = node ("-->" node)*
node      = name text?
```

Read `?` as *maybe*, `*` as *any number of times*, and quotes as *this exact token*. A
*statement* is a node, then any number of arrow-and-node pairs: `a --> b --> c` is one statement
with two edges.

The simplest way to turn a grammar into a parser is **recursive descent**: one procedure per
rule, each one consuming the tokens of its rule and calling the procedures of the rules inside it.
`statement` calls `node`, checks for `-->`, calls `node` again. That is the whole trick, and it is
how Pele's parsers are written too, by hand, one per diagram type. Here is the model of the
diagram above:
"""

nbCode:
  let model = parse(lex(pipeline))
  for i, n in model.nodes: echo i, " ", n.name.alignLeft(8), " ", n.label
  echo model.edges.mapIt($it.tail & "→" & $it.head).join("  ")

nbText: """
A node is remembered by its name the first time it appears, so `model` written three times is
one node. The edges point to nodes by number, in the order they were written; that order will
matter for the layout.

A parser also rejects what is not in the grammar, and a good one says what it expected:
"""

nbCode:
  try:
    discard parse(lex("flowchart TD\na --> --> b\n"))
  except LapilliError as e:
    echo e.msg

nbNote("""This is where most of Pele's code is: about 60% of the lines of its diagram types are
lexers, parsers and models. Not because parsing is hard, but because Mermaid's grammars are large
and full of special cases, and Pele reproduces them faithfully. The ported Mermaid specs
(`tests/compat/`) check that it accepts and rejects the same texts and builds the same model. For
nimaki, the parsers are the long, steady part of the port.""", nkPele, "How Pele does it")

nbText: """
## 3. Measuring: how big is a label?

Before placing a box, you need its size, and a box's size is its label's size plus some padding.
The height is easy (a line of text is about 1.5 times the font size). The width depends on every
letter: `iiii` is narrow, `WWWW` wide.

A browser knows the width of a text in a font, so Mermaid asks it: it puts the label in the page
and measures it. Without a browser, you need the widths yourself. Pele (and Lapilli, which
borrows its table) stores how wide each printable ASCII character is in Arial, in thousandths of
the font size, and adds them up:
"""

nbCode:
  for label in ["iiii", "WWWW", "Mermaid text", "Write SVG"]:
    let (w, h) = boxSize(label)
    echo label.alignLeft(14), textWidth(label).formatFloat(ffDecimal, 2).align(7), " px of text, box ",
      w.formatFloat(ffDecimal, 2), " × ", int(h)

nbText: """
The result is an estimate: the font that finally draws the text may be another. Pele uses a
canvas when it runs in a browser (exact for the fonts of that page), and this table otherwise.
For nimaki the table is what matters: the referee compares against Pele run in Node, where there
is no canvas, so both sides measure with the same table and get the same numbers.

## 4. Layout: where does everything go?

This is the heart of a diagram renderer. A flowchart has a direction (top to bottom here) and
arrows that should mostly follow it, so the classic method, **layered layout** (Sugiyama, Tagawa
and Toda, 1981), puts the nodes on horizontal **ranks** and makes the arrows go from one rank down
to the next. It has five steps.

### 4a. Break the cycles

Ranks only make sense if every arrow can point down, and a cycle (a → b → c → a) cannot. So the
first step turns some arrows round, just for the layout. A depth-first search does it: walk from
each node along its arrows; an arrow back to a node still on the current path closes a cycle.
"""

const cycle = """flowchart TD
write[Write a post] --> review[Pietro reviews] --> fix[Fix the post]
fix --> write
review --> merge[Merge]
"""

nbCode:
  let cyc = parse(lex(cycle))
  let rev = breakCycles(cyc)
  for e, edge in cyc.edges:
    echo cyc.nodes[edge.tail].name, " --> ", cyc.nodes[edge.head].name, (if rev[e]: "   turned round" else: "")

nbSvg(render(cycle), "The arrow back to the top is drawn upward: for the layout it pointed down.")

nbText: """
### 4b. Give every node a rank

The simplest rule, **longest path**: a node goes one rank below the lowest node that points to
it. Repeat until nothing moves.
"""

nbCode:
  let ranks = assignRanks(model, breakCycles(model))
  for r in 0 .. max(ranks):
    echo "rank ", r, ": ", toSeq(0 ..< model.nodes.len).filterIt(ranks[it] == r).mapIt(model.nodes[it].name).join(", ")

nbText: """
`model --> layout` skips a rank: `layout` is two below `model`, because `measure` is in between.

### 4c. Cut long arrows into pieces

An arrow that skips ranks would cut through the nodes in between. So it gets a **dummy node** in
every rank it crosses: an invisible point the rest of the layout treats like a tiny node, and
the arrow becomes a chain through the dummies. After this step every piece of every arrow goes
from one rank to the next, which makes the next two steps simple.

### 4d. Order each rank to avoid crossings

Within a rank, the order of the nodes decides how many arrows cross. Finding the order with the
fewest crossings is a hard problem (no fast method is known for big graphs), so everyone uses a
good guess: the **barycenter** heuristic. Sweep down the ranks and put each node at the average
position of its neighbours in the rank above; then sweep up, using the rank below; keep the best
order seen. Here is a diagram whose nodes are declared first, in an unlucky order (a line with
just a node declares it):
"""

const tangled = """flowchart TD
lava[Lava]
ash[Ash]
steam[Steam]
soil[Soil]
rock[Rock]
island[Island]
lava --> island
lava --> rock
ash --> rock
steam --> soil
"""

nbCode:
  var lay = layout(parse(lex(tangled)), sweeps = 0)
  echo "crossings after each sweep: ", lay.orderRanks(4).mapIt($it).join(" → ")

nbSvg(render(tangled, sweeps = 0), "As declared: each rank in the order its nodes were written.")
nbSvg(render(tangled), "After the barycenter sweeps.")

nbText: """
### 4e. Give every node an x and a y

The y is the easy one: one rank after the other, each as tall as its tallest box, with a gap
between. The x has competing wishes: boxes in a rank must not overlap, an arrow looks best
straight, a node looks best centred over its neighbours. Lapilli packs each rank from the left and
then lets each node slide toward the average x of its neighbours, as far as the boxes beside it
allow, a few times over. It is crude, and you can see it in the drawings: things are not always
centred.

The method most real layouts use is **Brandes and Köpf** (2001): it builds four alignments
(nodes lined up with their upper-left, upper-right, lower-left or lower-right neighbours, chained
into vertical blocks), compacts each, and takes the average of the middle two. Long arrows come
out as straight vertical lines, and it runs in linear time.

### Pele's layouts

Pele's `layout/layered.ts` does these five steps (cycle breaking by depth-first search, longest
path then balancing for ranks, dummies, barycenter sweeps with a fast crossing count, Brandes and
Köpf for x) and then a great deal more, because the result has to look good, not just correct.
Its header lists eight aims, in order:
"""

nbText: """
1. Lines can be told apart: none touch, run along each other, or pass through a node or label.
2. Lines cross as little as the order of the nodes allows.
3. An edge takes the shortest and simplest way: straight if it can, else one curve.
4. An edge meets the middle of a side, unless the aims above need otherwise.
5. The drawing is balanced, and what is alike is drawn alike.
6. An edge leaves and reaches a node square to it; arrowheads point straight at the node.
7. Nodes keep the order they were written in, where nothing above says otherwise.
8. The drawing stays compact.

Each aim names the function that carries it out (`spread`, `assignTracks`, `reduceCrossings`,
`settle`, `snap`...). On top of the layered layout, Pele has two more:

- **Compound layout** (`layout/compound.ts`), for groups: Mermaid's subgraphs. It lays out the
  inside of each group as its own layered graph, then treats the group as one big box in the
  graph around it, from the innermost group out. Arrows that cross a group's border pass through
  **ports** on its side. Flowchart, state, class, ER, requirement, use case and agentflow
  diagrams all go through it.
- **Lane layout** (`layout/lanes.ts`), for swimlanes: every top-level group is a band along the
  flow, ranks are shared across lanes (so steps that happen at the same time sit level), and each
  node stays inside its lane.

The other 25 types do not need a graph layout at all: a pie is angles, a gantt chart is a time
axis, a sequence diagram is columns and rows. Their geometry is written for each of them.

## 5. Writing SVG

SVG is a text format for drawings: a `<rect>` with `x`, `y`, `width`, `height`; a `<text>` at a
point; a `<polyline>` through a list of points; and a `viewBox` that says which part of the plane
to show. Writing it is string building: no library, in Pele or here. Here is the start of the
pipeline drawing above:
"""

nbCode:
  let svgText = render(pipeline)
  for piece in svgText.split("><")[0 .. 7]: echo "<", piece, ">"

nbText: """
Two habits matter, and Pele has both:

- **Every number goes through one function** (`num`): at most two decimals, no trailing zeros, no
  `-0`. A drawing has thousands of numbers, and a byte for byte comparison needs each one written
  the same way. Pele's `num()` is the first function nimaki ports, and the post *How Pele is
  built* shows why Nim's rounding is not the same as JavaScript's.
- **No colour is written down.** Lapilli draws in `currentColor`, the colour of the text around
  the drawing, so it follows this page into night mode. Pele goes further: every fill and stroke
  is a CSS variable with a default, such as `var(--pele-surface,#f3f3f3)`, and a page restyles every
  diagram by setting `--pele-*` variables, without rendering again.

## What this changes for the port

- The stages give the port its seams. The coverage map splits every type into *parse*, *layout*
  and *render*, and a type can be ported and checked stage by stage: the model first (against the
  ported Mermaid specs), then the SVG (against Pele, byte for byte).
- The measurer and `num()` come first: every stage after parsing depends on them.
- The layered and compound layouts are the core of the second milestone. They are long
  (layered alone is over 2,000 lines) and change in almost every Pele release; their explainer
  will follow the eight aims one by one, with Lapilli growing a step at a time to show each.
- Lapilli stays a toy. Its job is to make the next posts readable, not to become nimaki.

## Sources

- Pele at the pin, MIT: `src/layout/layered.ts` (its header, the eight aims), `src/layout/compound.ts`,
  `src/layout/lanes.ts`, `src/text/measurer.ts` and `src/text/metrics.ts` (the Arial table Lapilli
  borrows, with its notice), `src/svg/builder.ts`, `src/diagrams/flowchart/lexer.ts`,
  `src/diagrams/common/tokens.ts`.
- K. Sugiyama, S. Tagawa, M. Toda, *Methods for Visual Understanding of Hierarchical System
  Structures*, IEEE Transactions on Systems, Man, and Cybernetics, 1981: the layered layout.
- U. Brandes, B. Köpf, *Fast and Simple Horizontal Coordinate Assignment*, Graph Drawing 2001:
  the x coordinates. Not read for this post beyond its abstract; the description follows Pele's
  comments and the common accounts of the method.
- Lapilli: `docs/devlog/data/drawing_a_diagram/lapilli.nim`, written for this post.
"""

nbSave

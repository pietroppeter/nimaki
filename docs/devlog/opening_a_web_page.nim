## devlog: 13 Nov 2026 J | What happens when you open a web page | The trip from a typed address to a page on the screen, in ten diagrams drawn by nimaki itself: the first of the articles that use the port to understand a domain, and what using it taught about the library.
## kind: article
import std/[strformat, strutils, json, tables, options]
import nimib
import ../blocks, ../pele
import nimaki

nbInit
nb.usePost()

# Every diagram of the page, by name: drawn by nimaki for a phone-wide column, and by Pele in
# Node with the same options, to check that the two agree byte for byte.
const phone = 390.0
let diagrams = {
  "url": """railroad-ebnf-beta
title "A web address, simplified from RFC 3986"
url = scheme, "://", host, [ ":", port ], path, [ "?", query ], [ "#", fragment ] ;
path = { "/", segment } ;
""",
  "dns-tree": """treeView-beta
├── . ## the root
│   ├── org ## a top-level domain
│   │   └── example.org ## a zone its owner runs
│   │       └── www.example.org
│   ├── io
│   │   └── github.io
│   │       └── pietroppeter.github.io ## this site
│   └── it
""",
  "dns-flow": """flowchart TD
  B[The browser wants pietroppeter.github.io] --> C{In the browser's cache?}
  C -->|yes| IP([An IP address])
  C -->|no| R[Ask the resolver]
  R --> RC{In the resolver's cache?}
  RC -->|yes| IP
  RC -->|no| Root[Ask a root server: who knows io?]
  Root --> TLD[Ask an io server: who knows github.io?]
  TLD --> Auth[Ask github.io's server: where is pietroppeter.github.io?]
  Auth --> IP
""",
  "tcp": """sequenceDiagram
  participant B as Browser
  participant S as Server
  B->>S: SYN, seq = x
  S->>B: SYN ACK, seq = y, ack = x + 1
  B->>S: ACK, ack = y + 1
  Note over B,S: One round trip: the connection is open
""",
  "tcp-header": """packet
title The TCP header, after RFC 9293
0-15: "Source port"
16-31: "Destination port"
32-63: "Sequence number"
64-95: "Acknowledgment number"
96-99: "Offset"
100-103: "Rsrvd"
104: "CWR"
105: "ECE"
106: "URG"
107: "ACK"
108: "PSH"
109: "RST"
110: "SYN"
111: "FIN"
112-127: "Window"
128-143: "Checksum"
144-159: "Urgent pointer"
""",
  "tcp-states": """stateDiagram-v2
  [*] --> CLOSED
  CLOSED --> SYN_SENT: send SYN
  SYN_SENT --> ESTABLISHED: get SYN ACK, send ACK
  ESTABLISHED --> FIN_WAIT_1: close, send FIN
  FIN_WAIT_1 --> FIN_WAIT_2: get ACK
  FIN_WAIT_2 --> TIME_WAIT: get FIN, send ACK
  TIME_WAIT --> CLOSED: wait twice the segment lifetime
  ESTABLISHED --> CLOSE_WAIT: get FIN, send ACK
  CLOSE_WAIT --> LAST_ACK: close, send FIN
  LAST_ACK --> CLOSED: get ACK
""",
  "tls": """sequenceDiagram
  participant B as Browser
  participant S as Server
  B->>S: ClientHello, key share
  S->>B: ServerHello, key share
  Note right of S: from here on, encrypted
  S->>B: EncryptedExtensions, Certificate, CertificateVerify, Finished
  B->>S: Finished
  B->>S: GET / HTTP/1.1, Host: pietroppeter.github.io
  S->>B: HTTP/1.1 200 OK, then the page
""",
  "waterfall": """gantt
  title One page, with round trips of 50 ms
  dateFormat x
  axisFormat %L ms
  section Find
  DNS lookup      :dns, 0, 50ms
  section Connect
  TCP handshake   :tcp, after dns, 50ms
  TLS handshake   :tls, after tcp, 50ms
  section Fetch
  HTML            :html, after tls, 60ms
  CSS and fonts   :css, after html, 50ms
  Images          :img, after html, 90ms
""",
  "path": """architecture-beta
  group home(cloud)[Home]
  group isp(cloud)[Provider]
  group cdn(cloud)[Edge]
  group origin(cloud)[The site]

  service browser(server)[Browser] in home
  service resolver(server)[Resolver] in isp
  service edge(server)[CDN] in cdn
  service app(server)[Web server] in origin
  service db(database)[Database] in origin

  resolver:R -- L:browser
  browser:R -- L:edge
  edge:R -- L:app
  app:B -- T:db
""",
  "history": """timeline
  title The protocols of a page load
  1981 : TCP, RFC 793
  1987 : DNS, RFC 1034 and 1035
  1996 : HTTP/1.0, RFC 1945
  1999 : TLS 1.0, RFC 2246
  2005 : URI syntax, RFC 3986
  2015 : HTTP/2, RFC 7540
  2018 : TLS 1.3, RFC 8446
  2022 : HTTP/3, RFC 9114 : TCP revised, RFC 9293
""",
}.toOrderedTable

# The same architecture in a first arrangement, kept to show a lesson of the article.
let crossing = """architecture-beta
  group home(cloud)[At home]
  group cdn(cloud)[Edge near you]
  service browser(server)[Browser] in home
  service edge(server)[CDN edge] in cdn
  browser:B -- T:edge
"""

var drawn = initOrderedTable[string, RenderResult]()
var types = initOrderedTable[string, int]()
for name, text in diagrams:
  drawn[name] = render(text, RenderOptions(maxWidth: some(phone), now: fixedNow))
  types.mgetOrPut(drawn[name].diagramType, 0).inc
var sources: seq[string]
for text in diagrams.values: sources.add text
let fromPele = peleRenders(sources, %*{"maxWidth": phone})
var identical = 0
var i = 0
for name, r in drawn:
  if fromPele[i]{"svg"}.getStr == r.svg: inc identical
  inc i
var wide: seq[string]   # the drawings wider than a phone even with maxWidth
var narrowed = 0        # the drawings that maxWidth changed
for name, text in diagrams:
  if drawn[name].width > phone: wide.add name
  if render(text, RenderOptions(now: fixedNow)).svg != drawn[name].svg: inc narrowed
doAssert wide == @["tcp-states", "path"], "the text says which drawings stay wide: " & $wide
let crossingSvg = render(crossing).svg
var unported = ""
try: discard render("mindmap\n  root\n    a branch\n")
except PeleError as e: unported = e.msg

proc show(name, caption: string) =
  ## A diagram of the page, then its Mermaid text, folded.
  nbSvg drawn[name].svg, caption
  nbFold "The Mermaid text of this diagram":
    nbText &"```mermaid\n{diagrams[name].strip}\n```\n"

nbText: &"""
Pietro asked for an article, every once in a while, that uses diagrams to understand a domain:
a way to use the port for real, and to learn what each kind of diagram is for. This is the first.
The domain is one every reader has just lived through: **opening this page**. Between typing an
address and reading these words, a browser found a server among billions of machines, opened a
connection to it, agreed on a secret with it in public, asked for a page and got it back, all in
a fraction of a second. Each step has a diagram type that fits it.

## The findings, first

- **{diagrams.len} diagrams of {types.len} types, all drawn by nimaki.** A railroad, a tree, a
  flowchart, sequences, a packet, a state machine, a gantt chart, an architecture and a timeline,
  drawn when this page was built, by the Nim port alone.
- **{identical} of {diagrams.len} identical to Pele's.** The page also asks Pele, run in Node, to
  draw the same texts with the same options, and compares the bytes. Using the port for real found
  nothing to fix.
- **One option makes a diagram fit a phone.** `maxWidth` tells the renderer how wide the column is.
  For {narrowed} of the {diagrams.len} diagrams it changes the drawing, not just its size: the
  railroad wraps, the timeline turns downwards, the packet breaks its rows in two, long messages
  wrap. {wide.len} drawings stay wider than a phone and are shrunk to fit instead: the state
  machine and the architecture, whose layouts have no narrow mode.
- **A domain fact the diagrams caught.** Mermaid's own example of a packet diagram is the TCP header
  of 1981, with six reserved bits. Today's header (RFC 9293) has four, and two flags for congestion
  that came in 2001. Drawing it right meant reading the standard, which is the point of these
  articles.
- **Lessons for the port** are at the end, under *What drawing taught about nimaki*: none is a bug,
  two are wishes for the pages.

## How this page draws

A diagram here starts as a few lines of Mermaid text. nimaki's `render` turns the text into SVG,
the drawing language of the web, and the page shows it. This is all the code a page needs:
"""

nbCode:
  let text = "flowchart LR\n  A[Type an address] --> B[Read the page]\n"
  let r = render(text, RenderOptions(maxWidth: some(390.0)))
  echo r.diagramType, ", ", r.width, " by ", r.height, " pixels, ", r.svg.len, " bytes of SVG"

nbSvg r.svg, "The whole article in one flowchart, drawn by the code above."

nbText: &"""
Every diagram below is drawn the same way, with `maxWidth` at {phone.int} pixels, so that it
reads on a phone. Its Mermaid text is folded under it, to copy and change.

## 1. An address

It starts with an address: `https://pietroppeter.github.io/nimaki/`. An address is text with a
grammar, written down in RFC 3986 (an RFC, *request for comments*, is how the internet's
standards are published). A grammar says which texts are well formed, and a **railroad diagram**
draws it as tracks: start at the dot on the left, follow any track a train could take, and every
box you pass is a piece of the address. A box with rounded ends is literal text, a square box is a
part defined elsewhere. A track that goes around a box makes it optional; a track that loops back
lets it repeat.
"""

show "url", "A web address as tracks, simplified: the standard also allows a user name before the host and addresses without `//`. Drawn by nimaki."

nbText: """
Reading the address of this page against it: the scheme is `https`, the host is
`pietroppeter.github.io`, there is no port (so the scheme's own, 443, is used), the path is
`/nimaki/`, and there is no query and no fragment. The browser now knows *whom* to ask, by name.
It needs a number.

## 2. A name becomes a number

Machines on the internet are reached by IP address, a number such as `185.199.108.153`. The
**Domain Name System** (DNS) turns names into numbers. Names are a tree, read from right to left:
`pietroppeter.github.io` is a child of `github.io`, a child of `io`, a child of the root, written
as a single dot. Each part of the tree is run by whoever owns it, which is why nobody has to keep
a list of every name in the world. A **tree view** draws that:
"""

show "dns-tree", "A corner of the names tree. Each name is run by whoever owns it: the root by thirteen named servers (with many copies each), `io` by its registry, `github.io` by GitHub. Drawn by nimaki."

nbText: """
To find a number, the browser asks a **resolver**, usually run by the internet provider. If the
resolver has not seen the name lately, it walks down the tree: the root does not know the
answer, but knows who runs `io`; they know who runs `github.io`; and that server knows the
answer. Every step is a question and an answer across the network, and every answer comes with
a time to live, so that the next visitor finds it in a cache. A **flowchart** is made for this:
boxes are steps, diamonds are questions, and the arrows say where each answer leads.
"""

show "dns-flow", "Finding a number for a name. Most lookups end at a cache; the walk down the tree is the slow path. Drawn by nimaki."

nbText: """
## 3. A connection

With a number, the browser opens a connection with **TCP**, the protocol that turns a network
which may drop, repeat or reorder packets into a reliable stream of bytes. It does that by
numbering every byte. The two sides first agree on where their numbers start, in a *handshake*
of three messages. A **sequence diagram** draws messages between parties: one lifeline for each,
time going down, an arrow for each message.
"""

show "tcp", "The three-way handshake. SYN, *synchronize*, carries a starting number; ACK, *acknowledge*, says the next number expected. Drawn by nimaki."

nbText: """
Every TCP message starts with a header, a few rows of fixed fields. A **packet diagram** draws
such a header as rows of 32 bits, numbered from 0, each field as wide as its bits. The single
bits in the fourth row are the *flags* the handshake used: SYN, ACK and, to close, FIN.
"""

show "tcp-header", "The TCP header without options, from RFC 9293 (2022). The four reserved bits and the flags CWR and ECE are where it differs from the header of 1981 that Mermaid's example draws. Drawn by nimaki."

nbText: """
A connection is a small machine of its own: in each state it waits for something, and what comes
moves it on. A **state diagram** draws states as boxes and the events that move between them as
arrows. Here is the browser's side, from opening to closing: whoever closes first waits in
`TIME_WAIT`, for twice the longest time a packet can wander the network, so that a late packet
of this connection cannot be read as part of the next.
"""

show "tcp-states", "The states of a TCP connection that the browser opens, after the state diagram of RFC 9293 (its server side, `LISTEN` and `SYN-RECEIVED`, is left out). Drawn by nimaki."

nbText: """
## 4. A secret, agreed in public

The `s` of `https` means that what follows is encrypted with **TLS**. The problem it solves is
old and lovely: two parties who have never met must agree on a secret key while anyone can read
everything they send. Each side sends a *key share*, half of a Diffie–Hellman exchange: from the
two shares both sides compute the same key, and someone who saw only the shares cannot. The
server then proves it is the real `pietroppeter.github.io` with a certificate, signed by an
authority the browser trusts. In TLS 1.3 all this takes one round trip, and the request for the
page can follow the browser's last handshake message at once:
"""

show "tls", "The TLS 1.3 handshake, then an HTTP request and its response, as a sequence diagram. Everything after ServerHello is encrypted. Drawn by nimaki."

nbText: """
The request itself is **HTTP**: a line saying what is wanted (`GET /nimaki/`), headers, and an
answer that starts with a status (`200 OK`) and carries the page. The browser reads the page,
finds the styles, fonts and images it names, and asks for those too, over the same connection.

## 5. Where the time goes

None of these steps is slow on its own; what costs is the **round trip**, the time for a message
to cross the network and an answer to come back, tens of milliseconds between continents. A
**gantt chart** puts tasks on a line of time, and the browser's developer tools draw page loads
this way, as a *waterfall*. The numbers below are made up but the shape is typical: three round
trips before the first byte of the page, which is why newer protocols work so hard to save them
(TLS 1.3 saved one over TLS 1.2; HTTP/3 runs over QUIC, which merges the TCP and TLS handshakes).
"""

show "waterfall", "A page load as a waterfall, with an invented round trip of 50 ms: find, connect, then fetch. Drawn by nimaki."

nbText: """
## 6. Who is on the path

The *server* is rarely one machine. A site like this one is served by a **content delivery
network** (CDN): copies of the pages on servers near every reader, the *edge*, which ask the
site's own servers only for what they do not have. An **architecture diagram** draws services
(each with an icon for what it is) inside the groups that run them, and the lines between them.
"""

show "path", "The parties of a page load, grouped by who runs them. Drawn by nimaki."

nbText: """
## 7. How old each piece is

Last, a **timeline** of the standards this page went through. The oldest piece, TCP, is older
than the web by a decade, and is still being revised; the address syntax, which looks the
simplest, got its final form only in 2005.
"""

show "history", "The standards of a page load and the year of their RFCs. The timeline turns downwards to fit a phone. Drawn by nimaki."

nbText: &"""
## What drawing taught about nimaki

Using the library to explain something, instead of to pass a test, showed a few things. None is a
bug of the port: the referee had already done its job.
"""

nbNote &"""
Every drawing above, {identical} of {diagrams.len}, is byte for byte the one Pele draws in Node with
the same options, including `maxWidth`. The comparison runs every time the page is built.
""", nkDone, "Checked"

nbText: &"""
- **`maxWidth` is the option a page needs.** Without it, the timeline is a row of eight
  columns {render(diagrams["history"], RenderOptions()).width.int} pixels wide, and the packet is
  {render(diagrams["tcp-header"], RenderOptions()).width.int}. With it, Pele's own narrow layouts
  take over. Two layouts have no narrow mode: the state diagram stays
  {drawn["tcp-states"].width.int} pixels wide at any `maxWidth` (the layered layout places its
  boxes and does not wrap them), and the architecture {drawn["path"].width.int} (its grid of
  services). Worth knowing for diagrammari, whose readers are on phones too.
- **An unported type fails loudly.** At the time of writing, asking for a mindmap gives
  *{unported}* That is the right behaviour, and the message is clear enough to show a user.
- **Gantt charts read the clock.** A gantt chart marks today, so a page that draws one must pass a
  fixed `now`, or a chart whose dates include today changes from one build to the next. This one
  passes the referee's fixed date anyway, though its times, counted in milliseconds from zero,
  fall on 1 January 1970, far from any today.
- **Edges cross group titles.** In a first arrangement of the architecture diagram, the browser
  sat above the CDN, and the line between them crossed the title of the lower group. Pele draws it
  the same way, so it is not for the port to change; the article avoids it by keeping that line
  horizontal.
"""

nbSvg crossingSvg, "A line entering a group from above crosses the group's title. Pele draws the same bytes."

nbNote """
Two wishes for the pages, recorded as notes on the roadmap rather than done here: a block that
draws Mermaid text with nimaki and shows the text folded under it (this page defines it in five
lines as `show`, and the port posts each write their own), and a check, in that block, that
Pele draws the same bytes, so every page with a diagram is also a small test.
""", nkQuestion, "For a later step"

nbText: &"""
## The next articles

Each article picks a domain where several diagram types are at home, preferring types not drawn
in an article yet. Proposed next, as the port reaches them:

- **How a bill becomes a law**: a flowchart of the procedure, a sequence between the two
  chambers, a gantt of a real calendar, a timeline of one bill.
- **A kitchen on a Friday night**: swimlanes of who hands what to whom, a user journey of a guest,
  an ishikawa diagram of why a dish came back, a kanban board once it is ported.
- **Where a library's data lives**: entity–relationship and class diagrams of a small catalogue,
  requirements, a git graph of its releases, a treemap of its code.

## What this changes for the port

- Nothing to fix: the {diagrams.len} drawings of this article are new inputs the port draws as
  Pele does.
- The roadmap gains a phase of recurring steps, with this article as its first and a step for
  the next ones; a post kind, *article*, marks them in the devlog.
- The wishes above (a Mermaid block for pages, checked against Pele) are noted on the roadmap.

## Sources

- The standards: [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) (URI syntax),
  [RFC 1034](https://www.rfc-editor.org/rfc/rfc1034) and
  [RFC 1035](https://www.rfc-editor.org/rfc/rfc1035) (DNS),
  [RFC 793](https://www.rfc-editor.org/rfc/rfc793) and
  [RFC 9293](https://www.rfc-editor.org/rfc/rfc9293) (TCP; its header and state diagram are
  section 3.1 and 3.3.2), [RFC 3168](https://www.rfc-editor.org/rfc/rfc3168) (the CWR and ECE
  flags, 2001), [RFC 8446](https://www.rfc-editor.org/rfc/rfc8446) (TLS 1.3, its full handshake
  in section 2), [RFC 1945](https://www.rfc-editor.org/rfc/rfc1945),
  [RFC 2246](https://www.rfc-editor.org/rfc/rfc2246),
  [RFC 7540](https://www.rfc-editor.org/rfc/rfc7540) and
  [RFC 9114](https://www.rfc-editor.org/rfc/rfc9114). The RFC Editor's site could not be reached
  from the sandbox this article was written in: the facts and dates here are from the RFCs as
  the author knows them, and the links were not opened while writing.
- Mermaid's packet example with the header of 1981 is the first packet case of Pele's corpus,
  `corpus/cases.json` in this repository.
- Each diagram type has its own port post: [railroad](../railroad-diagrams/),
  [tree view](../radar-treemap-treeview/), [flowchart](../layered-layout-and-flowchart/),
  [sequence](../lifelines-and-messages/), [packet](../three-small-diagrams/),
  [state](../states-and-regions/), [gantt](../gantt-charts/),
  [architecture](../maps-and-clouds/) and [timeline](../timeline/); what each type is used for in
  the world is in [Diagrams in the wild](../diagrams-in-the-wild/).
"""

nbSave

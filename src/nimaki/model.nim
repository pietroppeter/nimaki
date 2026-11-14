## The pragmas a model's type uses to say how it differs from Pele's. Not a port of a file of Pele.
##
## A diagram's model is Pele's (`parse(text)` returns it, and Pele's tests read it), field for
## field, so tools/models.nim writes it as Pele's JSON and tools/parsediff.nim compares the two.
## Where the port keeps something Pele's model does not have, the field says so:
##
## - `{.portOnly.}`: a field of the port's own (an index, a cache, a flag), which Pele's model
##   does not have. tools/models.nim leaves it out.
## - `{.spread.}`: an object whose fields Pele's model has as its own (`{ ...built, title }`).
##   tools/models.nim writes them in the model.

## - `{.undefinedIfEmpty.}`: a text that is "" where Pele's is undefined. tools/models.nim leaves
##   it out when it is "". (The model's own `title`, `accTitle` and `accDescr` are read so in
##   every type but usecase, without the pragma: elsewhere Pele leaves them undefined, never "".)

template portOnly*() {.pragma.}
template undefinedIfEmpty*() {.pragma.}
template spread*() {.pragma.}

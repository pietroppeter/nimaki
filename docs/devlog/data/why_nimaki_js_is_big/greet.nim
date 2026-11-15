type Point = object
  x, y: float

proc greet(name: string): string =
  result = "Hello, " & name & "!"

proc moved(p: Point, dx: float): Point =
  result = p
  result.x += dx

let a = Point(x: 1, y: 2)
let b = moved(a, 3)
echo greet("Pele"), " ", b.x

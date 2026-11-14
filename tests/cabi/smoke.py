"""The smoke test of nimaki's C ABI, from Python through ctypes (no package, no dependency).

    python3 tests/cabi/smoke.py build/cabi/libnimaki.so

tools/cabi.nim builds the library and runs this. It draws a pie, reads an error, then draws every
case of the corpus through the library and compares each answer with Pele's, run in Node by
tools/oracle.mjs, as tools/difftest.nim does. One `ERROR ...` line per problem, a summary last.
"""
import ctypes, json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
os.environ["TZ"] = "UTC"  # as the oracle runs; gantt reads the time zone
if hasattr(time, "tzset"):
    time.tzset()
NOW = 1767225600000.0  # 2026-01-01T00:00:00Z, tools/difftest.nim's fixedNow

lib = ctypes.CDLL(sys.argv[1] if len(sys.argv) > 1 else str(repo / "build" / "cabi" / "libnimaki.so"))
lib.nimaki_render.argtypes = [ctypes.c_char_p]
lib.nimaki_render.restype = ctypes.c_void_p  # a pointer, so that it can be given back
lib.nimaki_free.argtypes = [ctypes.c_void_p]
lib.nimaki_pele_version.restype = ctypes.c_char_p


def ask(request) -> dict:
    raw = request if isinstance(request, bytes) else json.dumps(request).encode()
    p = lib.nimaki_render(raw)
    try:
        return json.loads(ctypes.string_at(p).decode())
    finally:
        lib.nimaki_free(p)


def render(source: str, **options) -> dict:
    return ask({"source": source, "options": options})


errors = []
def check(ok, what):
    if not ok:
        errors.append(what)
        print("ERROR", what)


pin = dict(l.split("=", 1) for l in (repo / "reference" / "PIN").read_text().splitlines() if "=" in l and not l.startswith("#"))
check(lib.nimaki_pele_version().decode() == pin["TAG"], "nimaki_pele_version is not " + pin["TAG"])

# a pie
pie = 'pie title Pets\n  "Dogs" : 386\n  "Cats" : 85\n  "Rats" : 15\n'
a = render(pie)
check(a.get("ok") and a["type"] == "pie" and a["svg"].startswith("<svg") and a["width"] > 0, "the pie did not draw: " + str(a)[:200])

# errors come back as answers, with Pele's code and place
e = render("pie\n  \"Dogs\" 386\n")
check(not e["ok"] and e["code"] == "syntax" and e["line"] >= 1, "a syntax error: " + str(e)[:200])
check(ask(b"{not json")["code"] == "request", "a request that is not JSON")
check(ask({"options": {}})["code"] == "request", "a request with no source")

# threads take turns: the same answer from eight at once
with ThreadPoolExecutor(8) as pool:
    svgs = set(pool.map(lambda i: render(pie, idPrefix="t-")["svg"], range(64)))
check(len(svgs) == 1, f"threads drew {len(svgs)} different SVGs of one pie")

# every case of the corpus, through the library and through Pele in Node, with a few options
cases = []
for name in ["cases.json", "diagrammari.json"]:
    path = repo / "corpus" / name
    if path.exists():
        cases += json.loads(path.read_text())["cases"]
variants = [{"now": NOW}, {"now": NOW, "fontSize": 14, "padding": 4, "idPrefix": "x-", "maxWidth": 480, "responsive": False}]
inputs = [{"id": f'{c["id"]}#{i}', "source": c["source"], "options": o}
          for c in cases for i, o in enumerate(variants) if i == 0 or c["type"] == "pie"]
package = os.environ.get("PELE_PACKAGE", str(repo / "reference" / "npm" / "package"))
oracle = subprocess.run(["node", str(repo / "tools" / "oracle.mjs"), package], input="".join(json.dumps(c) + "\n" for c in inputs),
                        capture_output=True, text=True, env={**os.environ, "TZ": "UTC"}, check=True)
peles = {r["id"]: r for r in map(json.loads, oracle.stdout.splitlines())}
same = different = unsupported = 0
start = time.perf_counter()
for c in inputs:
    mine, pele = ask(c), peles[c["id"]]
    if not mine["ok"] and mine["code"] == "unsupported":
        unsupported += 1
    elif (mine["ok"], mine.get("svg"), mine.get("code"), mine.get("message")) == (pele["ok"], pele.get("svg"), pele.get("code"), pele.get("message")) \
            and (not mine["ok"] or (mine["width"], mine["height"], mine["type"]) == (pele["width"], pele["height"], pele["type"])):
        same += 1
    else:
        different += 1
        if different <= 10:
            print("ERROR", c["id"], "differs from Pele")
ms = (time.perf_counter() - start) * 1000 / len(inputs)
check(different == 0, f"{different} cases differ from Pele")

# how long a pie takes, request and answer included
start = time.perf_counter()
for _ in range(1000):
    render(pie)
pie_ms = (time.perf_counter() - start)

# the last run, for the pages (docs/data/cabi.json)
import platform
record = {"about": "Written by tests/cabi/smoke.py (nim r tools/cabi.nim): the last run of the C ABI's smoke test. Do not edit by hand.",
          "pele": pin["TAG"], "cases": len(inputs), "identical": same, "different": different, "unsupported": unsupported,
          "msPerCase": round(ms, 3), "msPerPie": round(pie_ms, 3), "bytes": os.path.getsize(lib._name),
          "platform": f"{platform.system()} {platform.machine()}", "python": platform.python_version(), "errors": len(errors)}
(repo / "docs" / "data" / "cabi.json").write_text(json.dumps(record, indent=2) + "\n")

print(f"cabi smoke: Pele {pin['TAG']}, {len(inputs)} cases through the C ABI: {same} identical, {different} different, "
      f"{unsupported} unsupported, {ms:.2f} ms a case; {len(errors)} errors")
sys.exit(1 if errors else 0)

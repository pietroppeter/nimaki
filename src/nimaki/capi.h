/* nimaki's C ABI: Pele, the Mermaid renderer, ported to Nim, as a shared library.
 * Built from src/nimaki/capi.nim (see there, and tools/cabi.nim). Every string is UTF-8 JSON.
 *
 *   char *answer = nimaki_render("{\"source\": \"pie\\n  \\\"a\\\": 1\"}");
 *   ... read answer: {"ok": true, "type": "pie", "svg": "<svg ...", ...}
 *   nimaki_free(answer);
 *
 * Safe to call from several threads: calls take turns. */
#ifndef NIMAKI_H
#define NIMAKI_H
#ifdef __cplusplus
extern "C" {
#endif

/* Draws one diagram. `request` is {"source": "<Mermaid text>", "options": {...}} with Pele's
 * render options by name. The answer is {"ok": true, "type", "mermaidType", "svg", "width",
 * "height", "links"} or {"ok": false, "type", "code", "message", "line", "column", "snippet"}.
 * Never NULL; the caller frees it with nimaki_free. */
char *nimaki_render(const char *request);

/* Frees an answer of nimaki_render. NULL is ignored. */
void nimaki_free(char *answer);

/* The Pele version this library draws as ("1.13.0"); static, not to be freed. */
const char *nimaki_pele_version(void);

#ifdef __cplusplus
}
#endif
#endif

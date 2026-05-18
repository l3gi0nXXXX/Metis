This project implements the Metis code agent application, which is written in the Cangjie programming language.

Use context7 query Cangjie Syntax by /websites/cangjie-lang_cn_1_0_0 /dyingchinese/cangjie-stdx libraryId.

## Introduction of Cangjie

Cangjie is a recently introduced programming language. We briefly describe
the syntax of Cangjie below.

### Function definition

Use `func` to define a function, input parameter and return value may have type
annotations. Some parameters may be named (indicated with `!` sign). E.g.

```cangjie
func foo(a: Int64, b!: Int 64 = 0)
```

### Function call

In function call, the positional parameters are passed in first,
*without specifying the parameters name*. The named parameters follow in any order,
where the parameter name must be specified. Parameter with default values need not be specified. E.g.

```cangjie
foo(3)
foo(3, b: 2)
```

### Variable declaration

Variable declarations use either `let` or `var`. Variables declared using `let`
are immutable (cannot be assigned after initialization). Variables declared
using `var` can be assigner again within the function.

### Number types

The primitive types for numbers include:

* Signed integers: `Int8`, `Int16`, `Int32`, `Int64`, `IntNative`
* Unsigned integers: `UInt8`, `UInt16`, `UInt32`, `UInt64`, `UIntNative`
* Floating points: `Float16`, `Float32`, `Float64`(Float literals must have
  a `.`, e.g. 4 should be written as 4.0 to be Float type.)

### Array and ArrayList

Arrays with fixed length are declared using `Array<T>`, where `T` is the type
of elements in the array. Arrays with dynamic length are declared with `ArrayList<T>`.
The use of `ArrayList` requires `import std.collection.*`.

### HashMap and HashSet

`HashMap` represents mapping from keys to values using a hash table. `HashSet` represents
a set of values. Hashable values include numbers and strings but not tuples, `Array` or `ArrayList`.
Use of `HashMap` and `HashSet` requires `import std.collection.*`.

### Sorting

Sorting on arrays requires `import std.sort.*`. The basic syntax is `sort(arr)`.

### Tuples

Tuple types are represented using `(T1, T2, ..., TN)`, where `T1` to `TN` can be any type.
Tuples are immutable. Tuple values are represented using the parenthesis syntax as well.
Elements of a tuple are accessed by array indexing with constant indices (e.g. `t[0]`, `t[1]`).

### If-then-else

In Cangjie, if-then=else expressions require parenthesis around the condition and
brackets around the if and else blocks. E.g.

```cangjie
if (x > 0) {
    y = 1
} else {
    y = 2
}
```

### Iteration

In Cangjie, `..` is used to represent a range, left-closed and right-open. For example, `1..n` represents
from 1 to n, excluding n. `1..=n` represents including n. `n..1 :-1` represents from n down to 1,
excluding 1, when n > 1. To iterate over the interval `[low, high)`, with step k, use:

```cangjie
for (i in low..high: k) {
    ...
}
```

Syntax for while-loops is the same as in other languages.

### Division

In Cangjie, `/` is used instead of `//` to indicate division, while the latter is used for comments.

### Option types

Option types are declared using `Option<T>`, with values either `None<T>` (Note: while no parenthesis)
or `Some<T>(x)`, where `x` has type `T`. The type `Option<T>` can also be abbreviated as `?T`.

### Strings and characters

The type for characters is called `Rune` in Cangjie. A `Rune` literal starts with the character `r`,
followed by a character enclosed in a pair of single or double quotes. For example:

```cangjie
let a: Rune = r'a'
let s: String = "hello"
```

Use `s.runes()` to return iterator of Runes (type `Iterator<Rune>`). Use `s.toRuneArray()` to
convert the string directly to `Array<Rune>`.

### Bool

The Boolean type has only two literals: `true` and `false`. Operators include `!`, `&&` and `||`.

### Print statements

Function call `print(s)` prints string `s` to the terminal. Function call `println(s)` prints
string `s` followed by newline to the terminal. It is possible to *interpolate* values within
print statements using syntax `\${}`. For example

```cangjie
let a = 1
println("a = \${a}")
```

### Regular expressions

Functionality for regular expressions (including matching, replacement, splitting, obtaining
group information) can be used after import `std.regex.*`. For more examples of using
regular expression in Cangjie, retrieve its documents.

### Datetime functionality

Functionality for working with datetime and duration can be used after importing `std.time.*`.

### Main function

Test code can be placed in the main function. The declaration of main function is *not* preceded
by the `func` keyword. For example:

```cangjie
main() {
    println("Hello")
}
```

### Pipe operator

The pipe operator is convenient for expressing operation on iterators, e.g. when in  combination
with functions such as `all`, `any`, `filter`, `map`, etc. For example,

```
println(0..10 |> map({x: Int64 => 2 * x}) |> all({x: Int64 => x % 2 == 0}))  //true
```

### NOTES

If you are unsure how to use Cangjie, you can search the document `cj-rag/data/cangjiedoc.jsonl`. Each line in this document is a json line containing of

- text: split text chunks of original Cangjie documents
- short: a short summary of the text
- example_code: some example code using elements documented by text

Note its a huge file, you should search the short summary for efficiency.

## Build the project

You can run `cjpm build -i` to build the project. If there are some errors, you should fix it.

## Cangjie full-test execution notes

When a change requires the project-wide verification command, run it from the repository root with
the Cangjie SDK and OpenSSL library path prepared:

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm clean && cjpm build -i && cjpm test
```

If plain `cjpm test` reports package-level `failed to run package (exit code = 9)` without failed
test cases, do not treat it as an application assertion failure immediately. First rerun the
reported package path directly, then compare with `cjpm test -j 1` or `cjpm test --parallel false`
to separate code failures from package-level test-runner resource pressure. In this project, a
random package-level exit 9 after `cjpm clean` was resolved by lowering the test process heap in
`[profile.test.env]` from `128MB` to `64MB`; `jobs` must not be added to `[profile.test]`, because
the Cangjie unittest runtime treats it as an unknown runtime option.

## Code Style

You must write readable code, e.g., adding clear and concise comments.

## Metis Telegram transport notes

When investigating or changing Telegram Bot API connectivity, keep the fix inside the existing
gateway/channel/session architecture. Telegram proxy details belong in the Telegram channel
transport layer, not in the main agent, session manager, CLI, control-ui, or unrelated IM adapters.

Telegram Bot API targets are HTTPS URLs such as `https://api.telegram.org/...`. When the configured
proxy is an HTTP proxy, for example `http://127.0.0.1:7897` or bare `127.0.0.1:7897`, the correct
native transport path is:

```text
Metis -> HTTP proxy -> CONNECT api.telegram.org:443 -> stdx TLS -> stdx HTTP request
```

Do not remove the small native HTTP CONNECT connector just because the final Telegram target is
HTTPS. The connector is required for HTTPS-through-HTTP-proxy routing; after it establishes the
tunnel, stdx should still handle TLS and HTTP request semantics.

If a user configures a proxy string like `https://127.0.0.1:7897`, do not assume that the local
proxy is truly an HTTPS proxy. Many local proxy tools expose an HTTP proxy on that port even when
users describe the outbound destination as HTTPS. Treat this as a configuration semantics issue:

- HTTP proxy and bare host:port should use HTTP CONNECT for Telegram HTTPS targets.
- True HTTPS proxy support would require TLS to the proxy first, then CONNECT inside that TLS
  connection.
- If true HTTPS proxy is not implemented, return a clear diagnostic instead of silently failing.

Telegram transport work must not fall back to `curl --config`. Tests for this area must not use
real Telegram network, real bot tokens, proxy credentials, or real user files under `~/.metis`.
Never log Telegram bot tokens, proxy passwords, or authorization headers.

For Telegram "no reply" reports, first check whether logs contain `Gateway.inbound: channel=telegram`.
If no inbound event exists, prioritize Telegram polling/transport/proxy/pairing diagnostics. If the
inbound event exists but no answer is sent, then investigate gateway reply, session, model, and
send-path behavior.

## Telegram/OpenClaw gap analysis discipline

For broad Telegram compatibility work against OpenClaw, do not claim that gaps are fully analyzed
or fully closed from file names, method names, or isolated examples. First create or update a single
source-backed capability matrix under `develop_steps`.

Analysis results must be persisted. A chat response is not a substitute for the `develop_steps`
artifact, even when the response contains a matrix. If the user asks for a gap comparison or says
"do not change code, only analyze", write the analysis document first or update the existing
Telegram gap document before giving the final summary.

The matrix must enumerate every user-visible Telegram capability being compared and include:

- OpenClaw source evidence with file paths and line references.
- Metis source evidence with file paths and line references.
- Status using only `aligned`, `partial`, `missing`, or `not-applicable`.
- The exact functional gap, if any.
- The implementation task needed to close the gap.
- Concrete acceptance items and tests.

Only after that matrix is complete should implementation begin. Do not repeatedly produce partial
gap summaries or say "no remaining gap" unless every `partial` and `missing` row has been resolved
or explicitly marked `not-applicable` with code-based justification.

## Control UI validation discipline

Control UI changes are browser-runtime changes, not only static build changes. For any work touching
`ui/`, `assets/control-ui/`, or Gateway Control UI static serving, validation must include a real
browser smoke test against the built assets or a live Gateway page.

At minimum, verify that:

- the built JavaScript has no raw TypeScript decorator syntax that the browser would reject;
- `customElements.get("metis-app")` is registered in the browser;
- the page renders visible Metis UI content instead of a blank document;
- there are no browser page errors or failed JavaScript/CSS asset requests;
- control token bootstrap writes to the same storage backend that the runtime reads;
- Gateway static asset filenames are stable, or the running Gateway process is restarted and checked.
- Metis branding assets remain Metis-owned. Do not copy OpenClaw public branding assets into
  `ui/public` or `assets/control-ui`. Verify favicon and touch-icon files do not contain
  OpenClaw-specific graphical markers such as `lobster-gradient`, `Left Claw`, `Right Claw`, or
  `pixel-lobster`.

Do not treat `npm run build`, Cangjie unit tests, or API endpoint checks alone as sufficient proof
that Control UI still opens correctly.

## User-facing command output contract

This is a hard rule: user-facing CLI, IM native command, and Control UI command outputs must not
print `toJsonString()` results directly by default. Raw JSON is allowed only for explicit
machine-output modes such as `--json`, command names whose purpose is raw export, protocol
responses, persisted files, logs, or internal tool/RPC payloads that are not displayed directly.

Default human-facing command output must pass structured payloads through `gatewayFormatCommandOutput`
/ `gatewayPrintCommandOutput` or an equivalent command-specific human renderer. New or changed
commands must include tests that prove default output does not expose raw JSON object keys such as
`"ok"`, `"result"`, `"image"`, `"schedule"`, or `"sessions"` to users.

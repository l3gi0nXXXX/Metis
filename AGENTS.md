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

package metis.core.agents.common

protected let CANGJIE_INTRO = """
Cangjie is a recently introduced programming language. We briefly describe
the syntax of Cangjie below.

## Project Structure and Package Management

### Standard Project Structure
When creating a Cangjie project with `cjpm init`, the standard structure is:
- `cjpm.toml` - Project configuration file (at project root)
- `src/` - Source code directory (this is where all .cj files should go)
- `src/main.cj` - Main entry point file (NOT in project root)

**IMPORTANT**: All Cangjie source files (.cj) should be placed in the `src/` directory,
NOT in the project root. The main entry file is `src/main.cj`, not `main.cj` in root.

### Package Declaration Rules

**MANDATORY**: Every Cangjie source file MUST start with a `package` declaration.

#### Package Declaration Syntax
```cangjie
package packageName                    // Root package (from cjpm.toml name)
package rootPackage.subPackage         // Sub-package
package rootPackage.sub1.sub2          // Nested sub-packages
```

#### Critical Package Rules:
1. **First Line Requirement**: Package declaration MUST be the first non-empty, non-comment line
2. **Root Package Name**: Use the `name` field from `cjpm.toml` as the root package name
3. **Path Correspondence**: Package name MUST reflect the file's directory path relative to `src/`
   - File at `src/main.cj` → `package cli` (where "cli" is from cjpm.toml)
   - File at `src/utils/colors.cj` → `package metis.utils`
   - File at `src/core/agents/code_agent.cj` → `package metis.core.agents`
4. **Directory Consistency**: All files in the same directory MUST have identical package declarations

### Package Management with CJPM
- `cjpm init` - Initialize a new Cangjie project (creates `cjpm.toml` and `src/main.cj`)
- `cjpm build` - Compile the project
- `cjpm run` - Compile and run the executable
- `cjpm test` - Run unit tests

**NOTE**: After `cjpm init`, the project already has the standard structure with `src/main.cj` containing proper package declaration and main function. Do NOT search for or query basic initialization patterns - they are automatically provided by cjpm init.

### Main Function and Program Entry
The main function serves as the program entry point and must be defined in `src/main.cj`:

```cangjie
// src/main.cj
main() {
    println("Hello, Cangjie!")
}
```

Note: The `main` function is defined WITHOUT the `func` keyword.

## Function definition

Use `func` to define a function, input parameter and return value may have type
annotations. Some parameters may be named (indicated with `!` sign). E.g.

```cangjie
func foo(a: Int64, b!: Int 64 = 0)
```

## Function call

In function call, the positional parameters are passed in first,
*without specifying the parameters name*. The named parameters follow in any order,
where the parameter name must be specified. Parameter with default values need not be specified. E.g.

```cangjie
foo(3)
foo(3, b: 2)
```

## Variable declaration

Variable declarations use either `let` or `var`. Variables declared using `let`
are immutable (cannot be assigned after initialization). Variables declared
using `var` can be assigner again within the function.

## Number types

The primitive types for numbers include:

* Signed integers: `Int8`, `Int16`, `Int32`, `Int64`, `IntNative`
* Unsigned integers: `UInt8`, `UInt16`, `UInt32`, `UInt64`, `UIntNative`
* Floating points: `Float16`, `Float32`, `Float64`(Float literals must have
  a `.`, e.g. 4 should be written as 4.0 to be Float type.)

## Array and ArrayList

Arrays with fixed length are declared using `Array<T>`, where `T` is the type
of elements in the array. Arrays with dynamic length are declared with `ArrayList<T>`.
The use of `ArrayList` requires `import std.collection.*`.

## HashMap and HashSet

`HashMap` represents mapping from keys to values using a hash table. `HashSet` represents
a set of values. Hashable values include numbers and strings but not tuples, `Array` or `ArrayList`.
Use of `HashMap` and `HashSet` requires `import std.collection.*`.

## Sorting

Sorting on arrays requires `import std.sort.*`. The basic syntax is `sort(arr)`.

## Tuples

Tuple types are represented using `(T1, T2, ..., TN)`, where `T1` to `TN` can be any type.
Tuples are immutable. Tuple values are represented using the parenthesis syntax as well.
Elements of a tuple are accessed by array indexing with constant indices (e.g. `t[0]`, `t[1]`).

## Enum (Enumeration)
Enum is a powerful feature in Cangjie for defining a type that can have one of several possible representations.
It's especially useful for modeling states, variants, or alternative data structures.

```cangjie
// A simple enum with basic cases
enum RGBColor {
    | Red | Green | Blue
}

enum TimeUnit {
    | Year(UInt64)
    | Month(UInt64)
}

// Creating Instances
let color = RGBColor.Blue
let time = TimeUnit.Year(2)

// --- Pattern Matching with `match` ---
// The `match` expression is the primary way to use enums.
// It MUST be exhaustive, covering all possible cases.

// Example 1: Matching and extracting data
let timeDescription = match (time) {
    case Year(n) => "The duration is \${n * 12} months" // Matches and binds `2` to `n`
    case Month(n) => "The duration is \${n} months"
}
// `timeDescription` will be "The duration is 24 months"

// Example 2: Using a wildcard `_` to ensure exhaustiveness
let colorName = match (color) {
    case Red => "It's Red"
    case Green => "It's Green"
    case _ => "It's some other color" // The `_` matches `Blue` or any future cases
}
```

## If-then-else

In Cangjie, if-then=else expressions require parenthesis around the condition and
brackets around the if and else blocks. E.g.

```cangjie
if (x > 0) {
    y = 1
} else {
    y = 2
}
```

## Iteration

In Cangjie, `..` is used to represent a range, left-closed and right-open. For example, `1..n` represents
from 1 to n, excluding n. `1..=n` represents including n. `n..1 :-1` represents from n down to 1,
excluding 1, when n > 1. To iterate over the interval `[low, high)`, with step k, use:

```cangjie
for (i in low..high: k) {
    ...
}
```

Syntax for while-loops is the same as in other languages.

## Division

In Cangjie, `/` is used instead of `//` to indicate division, while the latter is used for comments.

## Option types

Option types are declared using `Option<T>`, with values either `None<T>` (Note: while no parenthesis)
or `Some<T>(x)`, where `x` has type `T`. The type `Option<T>` can also be abbreviated as `?T`.

## Strings and characters

The type for characters is called `Rune` in Cangjie. A `Rune` literal starts with the character `r`,
followed by a character enclosed in a pair of single or double quotes. For example:

```cangjie
let a: Rune = r'a'
let s: String = "hello"
```

Use `s.runes()` to return iterator of Runes (type `Iterator<Rune>`). Use `s.toRuneArray()` to
convert the string directly to `Array<Rune>`.

## Bool

The Boolean type has only two literals: `true` and `false`. Operators include `!`, `&&` and `||`.

## Print statements

Function call `print(s)` prints string `s` to the terminal. Function call `println(s)` prints
string `s` followed by newline to the terminal. It is possible to *interpolate* values within
print statements using syntax `\${}`. For example

```cangjie
let a = 1
println("a = \${a}")
```

## Regular expressions

Functionality for regular expressions (including matching, replacement, splitting, obtaining
group information) can be used after import `std.regex.*`. For more examples of using
regular expression in Cangjie, retrieve its documents.

## Datetime functionality

Functionality for working with datetime and duration can be used after importing `std.time.*`.

## Main function

Test code can be placed in the main function. The declaration of main function is *not* preceded
by the `func` keyword. For example:

```cangjie
main() {
    println("Hello")
}
```

## Pipe operator

The pipe operator is convenient for expressing operation on iterators, e.g. when in  combination
with functions such as `all`, `any`, `filter`, `map`, etc. For example,

```
println(0..10 |> map({x: Int64 => 2 * x}) |> all({x: Int64 => x % 2 == 0}))  //true
```

## Cangjie Unit Test

- Cangjie has a built-in test framework: std.unittest, you can use it to test your code.
- use command `cjpm test --filter <test_name>` to run a specific test case.
- use `cjpm build -i --coverage` and then `cjcov` to generate coverage report.
"""

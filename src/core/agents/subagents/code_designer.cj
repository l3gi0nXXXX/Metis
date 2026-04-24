package metis.core.agents.subagents

import magic.dsl.*
import magic.prelude.*
import metis.core.model.CliModelManager

private let CANGJIE_BASICS = """
Basics of Cangjie Programming Language to write the Cangjie project architecture designs.

## Function definition

Use `func` to define a function, input parameter and return value should have type annotations.
Named parameters may be defined with (indicated with `!` sign), and named parameter can have optional default value. E.g.

```cangjie
func foo(a: Int64, b!: Int64 = 0): String
```

## Interface definition

Use `interface` to define an interface, interface type can contain method declarations.
E.g.,

```cangjie
interface I {
    func foo(a: Int64, b!: Int64 = 0): Unit
}
```

## Class definition

Use `class` to define a class type, class type can contain functions and it can implement interfaces.
E.g.,

```cangjie
class A {
    func foo(a: Int64, b!: Int64 = 0): Unit
}

class B < I1 & I2 { // It implements two interfaces I1 and I2
    func bar(a: Int64, b: String = 0): Unit
}
```

## Enum definition

Use `enum` to define ADT (Algebraic Data Type). E.g.,
```cangjie
enum Result<T, E> {
    Ok(T),
    Err(E),
}
```

## Primitive Types
* Signed integers: `Int8`, `Int16`, `Int32`, `Int64`, `IntNative`
* Unsigned integers: `UInt8`, `UInt16`, `UInt32`, `UInt64`, `UIntNative`
* Floating points: `Float16`, `Float32`, `Float64`(Float literals must have
  a `.`, e.g. 4 should be written as 4.0 to be Float type.)
* Boolean type: `Bool`
* Cangjie has no void type, but `Unit`
* Option<T> means an optional value, where T is generic.
   enum Option<T> {
     | Some(value)
     | None
   }

### Array and ArrayList

Arrays with fixed length are declared using `Array<T>`, where `T` is the type
of elements in the array. Arrays with dynamic length are declared with `ArrayList<T>`.

### HashMap and HashSet

`HashMap` represents mapping from keys to values using a hash table.
`HashSet` represents a set of values.
Hashable values include numbers and strings but not tuples, `Array` or `ArrayList`.

## Cangjie Project Structure
• **Package** = minimum compilation unit (can produce executable, static lib, or dynamic lib)
Typical layout:
```
project/
├── cjpm.toml          # config & deps
├── src/
│   ├── main.cj        # entry point
│   └── subpkg/*.cj    # sub-packages
├── target/            # build outputs
```
"""

private let DESIGNER_PROMPT = """
${CANGJIE_BASICS}

You are an expert software architect with deep experience in designing scalable, maintainable, and secure systems.
Your task is to generate a comprehensive architecture design document based on the user's functional and non-functional requirements.

Carefully analyze the provided requirements and produce a well-structured, clear, and technically precise architecture design that includes the following sections:

---

#### 1. **Overview**
- Summarize the system’s purpose, scope, and primary objectives.
- Identify key constraints: performance, security, compliance, deployment environment.
- Specify the architectural style (e.g., modular monolith, microservices, event-driven).

---

#### 2. **Project Structure**
- Generate the **project directory structure** strictly following the **Cangjie project layout conventions**.

```
project/
|- src/
  |- packageA/
    |- file_a.cj
    |- subpackageA/
       |- file_b.cj
       |- subsubpackageA/
          |- file_c.cj
  |- packageB
    |- file_d.cj
  |- packageC
    |- file_e.cj
|- cjpm.toml
```

- For each package or directory, state its **responsibility**

---

#### 3. **Key Components and Types**
- List and describe **core components** (e.g., `OrderProcessor`, `UserAuthenticator`), and defined them in Cangjie

- Example format:
  ```cangjie
  class User {
    let id: Int64
    let email: String
    let createdAt: DateTime

    func register(arg: String): Unit
  }
  ```

---

#### 4. **Important Workflows**
- Describe 2–3 critical functional workflows step by step (e.g., "User Login", "Place Order", "Process Payment").
- For each workflow:
  - Use numbered steps or sequence diagrams in text form.
  - Show interactions between components, services, and external systems.
  - Include error handling and edge cases where relevant.

---

#### 5. **Important APIs**
- Define **key APIs** as **Cangjie methods or functions**.
  Example format:
  ```cangjie
  func createOrder(input: CreateOrderInput): Result<Order, OrderError>
  ```
- Prefer clarity over completeness—focus on the most critical APIs.

---

### 📌 Output Guidelines:
- Use **clear, professional language**.
- Structure the document as markdown
- All **type definitions and method signatures** must use the **Cangjie syntax**
- Prioritize **compliance with Cangjie standards** over generic architectural patterns.

> ✅ Your goal is to produce a design that enables developers to begin implementation with confidence.
"""

@agent[
    model: CliModelManager.model,
    executor: "naive"
]
public class CodeDesigner {
    @prompt(
        "${DESIGNER_PROMPT}"
    )
}
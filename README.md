# A small classical natural-deduction prover in Common Lisp

This is a Common Lisp library with an SBCL script for constructing and printing Fitch-style natural-deduction proofs in classical propositional logic.  The intended use is pedagogical: a student writes a finite list of premises, separates the premises from the desired conclusion by a line of hyphens, and the program either prints a checked proof or reports that no proof was found within its bounded search.

The program is deliberately not a first-order predicate-calculus prover.  The language has propositional atoms, falsity, negation, conjunction, disjunction, implication, and biconditional.  There are no terms, variables, function symbols, quantifiers, equality, substitutions, or eigenvariable conditions.

## Running the prover

The script is meant to be run directly with SBCL:

```bash
sbcl --script prover.lisp problem.nd
```

The file `problem.nd` has the following form:

```text
P
P -> Q
-----
Q
```

The separator line must contain at least five hyphens.  Blank lines are ignored.  The part after the separator must contain exactly one nonblank formula line.

For the example above, the output has the form:

```text
  1. P                                      PR
  2. P → Q                                  PR
  3. Q                                      →E      2,1
```

The output is a linear Fitch-style proof.  The number at the left is the line number.  Indentation records subproof depth.  The rule name appears near the right margin, followed by cited line numbers when the rule has citations.

The script exits with status `0` for a checked proof, `1` for an input error or unsuccessful search, and `2` for incorrect command-line usage. It can be invoked from another working directory; the problem filename is relative to the caller's working directory.

## Library use and tests

Load `nd-prover.lisp` to use the library without running the command-line application or exiting Lisp:

```lisp
(load "nd-prover.lisp")
(let* ((premises (mapcar #'nd-prover:parse-formula '("P" "P -> Q")))
       (conclusion (nd-prover:parse-formula "Q"))
       (proof (nd-prover:prove premises conclusion)))
  (when proof (nd-prover:print-proof proof)))
```

`prove` returns a checked proof or `nil`. It accepts `:classical` and `:depth` keyword arguments; depth must be a nonnegative integer. `check-proof` checks a proof independently and optionally accepts `:premises`, `:conclusion`, and `:classical`. Supplying premises checks the exact premise list, including order and duplicates. Setting `:classical nil` rejects RAA. `main` takes a list of command-line argument strings and returns an exit status without terminating the Lisp process.

Run the regression and command-line integration suites from the repository root:

```bash
sbcl --script tests/run.lisp
python3 tests/test_cli.py
```

The Lisp suite covers parser round trips, invalid rule applications and subproof citations, checked proofs for every rule, all bundled examples, and truth-table validation of generated proofs. The Python suite uses only the standard library and checks the actual CLI, exit codes, input errors, and invocation from another directory.

## Formula syntax

The internal abstract syntax consists of the following constructors:

| Mathematical form | Lisp structure | Meaning |
|---|---|---|
| `⊥` | `bot` | falsity |
| `P` | `pred` | propositional atom |
| `¬A` | `neg` | negation |
| `A ∧ B` | `conj` | conjunction |
| `A ∨ B` | `disj` | disjunction |
| `A → B` | `impl` | implication |
| `A ↔ B` | `iff*` | biconditional |

The parser accepts both Unicode and ASCII variants.  For example, the following are equivalent:

```text
(P ∧ Q) → (R ∨ ¬S)
(P & Q) -> (R v ~S)
(P and Q) implies (R or not S)
```

The accepted connectives include:

| Connective | Accepted input |
|---|---|
| negation | `¬`, `~`, `not` |
| conjunction | `∧`, `&`, `^`, `and` |
| disjunction | `∨`, `|`, `v`, `or` |
| implication | `→`, `⇒`, `->`, `=>`, `imp`, `implies` |
| biconditional | `↔`, `<->`, `<=>`, `iff`, `equiv` |
| falsity | `⊥`, `bot`, `bottom`, `false` |

The parser uses the precedence convention

```text
¬  >  ∧  >  ∨  >  →  >  ↔
```

and implication is right-associative.  Thus `P -> Q -> R` is parsed as `P -> (Q -> R)`.

Conjunction, disjunction, and biconditional are left-associative. The printer preserves explicit right nesting with parentheses so that printed formulas parse back into the same formula tree. Atom names are case-insensitive (`P` and `p` denote the same atom); their original spelling is retained for display. Connective words are reserved, including `v` and `V`.

## The proof system

Mathematically, the prover searches for derivations of sequents of the form

```text
Γ ⊢ A,
```

where `Γ` is a finite set-like context of propositional formulas and `A` is the target formula.  The implemented proof system is classical natural deduction with the following primitive rules.

### Structural and assumption rules

Premises are emitted as `PR`.  Temporary hypotheses opened in subproofs are emitted as `AS`.  The rule `R` is reiteration: if a line is available from an enclosing scope, the same formula may be repeated inside a deeper subproof.  Reiteration is used only during proof linearization to ensure that discharged subproof endpoints really occur inside the discharged subproof.

### Conjunction

The conjunction rules are the usual introduction and eliminations:

```text
A    B
------ ∧I
A ∧ B
```

and

```text
A ∧ B          A ∧ B
----- ∧E1      ----- ∧E2
  A              B
```

### Implication

Implication elimination is modus ponens:

```text
A → B    A
--------- →E
    B
```

Implication introduction discharges a subproof:

```text
[A]
 ⋮
 B
----- →I
A → B
```

The proof checker requires the cited assumption and the cited endpoint to be the endpoints of a valid subproof.  A line from outside the subproof is not accepted as the endpoint of a discharged implication subproof unless it has first been reiterated inside the subproof.

### Negation and falsity

Negation introduction is proof by contradiction relative to a fixed assumption:

```text
[A]
 ⋮
 ⊥
----- ¬I
¬A
```

Negation elimination is contradiction from a formula and its negation:

```text
A    ¬A
------ ¬E
  ⊥
```

Explosion is written `⊥E`:

```text
⊥
-- ⊥E
A
```

### Disjunction

The disjunction introductions are:

```text
A             B
----- ∨I1     ----- ∨I2
A ∨ B         A ∨ B
```

Disjunction elimination has the usual two-branch form:

```text
A ∨ B
[A]     [B]
 ⋮       ⋮
C       C
----------- ∨E
     C
```

The printed rule cites five lines: the disjunction line, the left branch assumption, the left branch endpoint, the right branch assumption, and the right branch endpoint.

### Biconditional

The biconditional is treated by introduction from two implications:

```text
A → B    B → A
------------- ↔I
    A ↔ B
```

The eliminations produce the two associated implications:

```text
A ↔ B          A ↔ B
----- ↔E1      ----- ↔E2
A → B          B → A
```

The implementation then uses ordinary implication elimination to obtain either direction as needed.

### Classical reasoning

The prover is classical by default.  The classical rule is reductio ad absurdum:

```text
[¬A]
 ⋮
 ⊥
----- RAA
 A
```

The dynamic variable `*classical*` controls whether the search procedure may use RAA.  In the standalone script the default is true.

## Search strategy

The search procedure constructs proof terms before any lines are printed.  A proof term is a tree whose nodes are rule applications, for example `:imp-intro`, `:imp-elim`, `:or-elim`, `:not-elim`, and `:raa`.  The term language is intentionally close to the natural-deduction rules listed above.

The central function is `prove-term`.  It attempts to build a natural-deduction term for a target formula from a finite context.  The search is bounded by `*default-depth*`, which is currently `60`.  The bound is not part of the logic; the bound is a termination safeguard.

Before attempting the main backward proof search, the context is saturated under finite immediate eliminations.  The saturation procedure repeatedly adds formulas justified by the following local consequences:

```text
A ∧ B        gives A and B,
A ↔ B        gives A → B and B → A,
A → B, A     gives B,
A, ¬A        gives ⊥.
```

Each added formula carries its proof term.  Saturation is not an arbitrary theorem prover.  In particular, explosion from `⊥` is still goal-directed rather than used to add every possible formula to the context.

After saturation, the search tries the following proof patterns in order:

1. use the target if the target is already present in the saturated context;
2. use an existing bottom formula and apply explosion, when the target is not bottom;
3. use direct eliminations, such as implication elimination or negation elimination;
4. derive bottom when the target is bottom;
5. prove the target by first proving a conjunction of which the target is a component;
6. apply disjunction elimination to an available disjunction;
7. apply right-introduction rules for conjunction, implication, negation, biconditional, and disjunction;
8. derive bottom and then use explosion;
9. if classical reasoning is enabled, use RAA.

The search uses two hash tables.  `ACTIVE` records sequents already on the current recursive call stack, preventing cyclic descent.  `FAILED` records unsuccessful searches at a given remaining depth, preventing repeated exploration of the same failed branch. These are heuristic pruning mechanisms, not certificates of unprovability. Search keys contain the reasoning mode, the structural target formula, and a sorted structural signature of the current context; atom case, context order, and duplicate formulas do not affect the key.

The search is sound relative to the checker, because any proof term that reaches the printer is later linearized and checked.  The search is not presented as a complete decision procedure for classical propositional logic.  `No proof found` means that the bounded search did not find a proof; the statement may still be valid.

## Linearization into Fitch-style proofs

The search procedure returns a tree-shaped proof term.  The function `linearize-proof` turns this tree into a numbered Fitch-style proof.

A proof line stores five pieces of data:

```lisp
(number depth formula rule citations)
```

The `depth` field records the subproof depth.  Premises have depth `0`.  Entering a subproof increments the depth; leaving the subproof restores the previous depth.

The central invariant is:

> A line may cite an ordinary previous line only when the cited line is accessible from the citing line.  A line inside a closed subproof is not accessible from outside the subproof.

Discharged rules are handled by the helper `linearize-subproof`.  Given an assumption proof term and a body proof term, `linearize-subproof` opens a subproof, emits the assumption, linearizes the body under the extended environment, and returns the two endpoint line numbers.  If the body proof term reuses a formula available from an outer scope, `line-at-current-depth` inserts a reiteration line, so that the endpoint of the subproof is genuinely inside the subproof.

This point is mathematically important.  For example, a proof of `A -> B` may not cite an outer line `B` directly as the endpoint of the subproof `[A] ... B`.  The line `B` must occur inside the subproof, either by derivation or by reiteration.  The implementation enforces this by construction and checks it again afterward.

## Internal proof checking

After a proof is constructed, `prove` calls `check-proof` to verify every line, its premises, and its final conclusion before returning it. The checker is intentionally independent of the search procedure. When the goal is an earlier premise, the linearizer reiterates it at the end so the final line is the requested conclusion.

The checker verifies:

* citation counts;
* consecutive line numbers, nonnegative depths, and a final line at depth zero;
* premises confined to the initial top-level block and assumptions opening subproofs;
* ordinary line accessibility;
* formula shapes for all introduction and elimination rules;
* subproof endpoints for `→I`, `¬I`, `RAA`, and `∨E`;
* correct branch assumptions and branch conclusions for `∨E`;
* correct directions for `↔E1` and `↔E2`.

The checker reconstructs the stack of open assumptions for every line. An ordinary citation must point to an earlier line in the same or an enclosing scope; matching numeric depths alone is insufficient, since sibling branches have equal depths. For discharged rules, the assumption must open a direct child of the rule's scope, and the endpoint must be the final line of that subproof at the assumption's own depth. Disjunction elimination requires two separate, ordered branches.

Consequently, if the script exits successfully, the displayed derivation is a valid Fitch-style natural-deduction proof for the implemented rule system.

## Examples

### Modus ponens

Input:

```text
P
P -> Q
-----
Q
```

Output:

```text
  1. P                                      PR
  2. P → Q                                  PR
  3. Q                                      →E      2,1
```

### Implication introduction

Input:

```text
P -> Q
-----
P -> Q
```

One possible proof is just the premise.  If the implication must be derived from a temporary assumption in a larger example, the output has the shape:

```text
  1. P                                      AS
  2. Q                                      ...
  3. P → Q                                  →I      1,2
```

where line `3` is outside the subproof opened at line `1`.

### Disjunction elimination with contradiction in one branch

Input:

```text
P -> Q
R v T
(P & Q) -> (S & ~T)
--------------------
P -> R
```

The proof uses implication introduction.  Inside the subproof assuming `P`, the prover uses the disjunction `R ∨ T`.  The `R` branch is immediate.  The `T` branch derives `P ∧ Q`, then `S ∧ ¬T`, then `¬T`, contradicts the branch assumption `T`, and obtains `R` by explosion.  Disjunction elimination then gives `R`, and implication introduction discharges the initial assumption `P`.

### Classical proof by cases through RAA

Input:

```text
Z -> (C & ~N)
~Z -> (N & ~C)
-------------
N v C
```

The proof is classical.  Informally, either `Z` holds or `¬Z` holds in the classical proof search.  From `Z`, the first premise yields `C`; from `¬Z`, the second premise yields `N`.  In either case `N ∨ C` follows.  The implementation may realize this reasoning by RAA rather than by a separately primitive excluded-middle rule.

## Limitations

The program is intentionally small and pedagogical.  The main limitations are these.

First, the implemented logic is propositional.  The printed atoms may look like predicate symbols, but there is no first-order syntax and no quantifier reasoning.

Second, the search is bounded and heuristic.  Successful output is checked and sound for the implemented natural-deduction system.  Failure to find a proof is not a semantic refutation.

Third, the context is treated set-like during search.  Duplicate premises do not play a distinct role, which is appropriate for ordinary classical propositional natural deduction but not for resource-sensitive logics.

Fourth, the biconditional eliminations are represented as derivations of implications.  This keeps the checker small and explicit, but it can make printed proofs slightly more verbose than textbook proofs that treat biconditional elimination as a direct rule from `A ↔ B` and `A` to `B`.

## File organization

`prover.lisp` is the SBCL launcher. `nd-prover.lisp` contains the portable library, organized into the following sections.

```text
Formulas
Parser
Proof terms and search contexts
Linear Fitch-style proofs
Proof checker
Input and output
Command-line application (returns an exit status)
```

The intended trust boundary is the proof checker, not the search engine.  The search engine may be improved, reordered, or replaced, provided that the generated proof lines continue to pass `check-proof` before being printed.

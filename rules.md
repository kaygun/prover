| Abbr. | Human-Readable Name | Description |
| :--- | :--- | :--- |
| `PR` | Premise | Introduces a top‑level assumption from the problem statement. |
| `AS` | Assumption | Begins a nested subproof by assuming the given formula. |
| `R` | Reiteration | Copies an accessible formula from an outer scope into the current scope. |
| `X` (⊥E) | Bottom Elimination / Explosion | Derives any formula from a contradiction (`⊥`) in the current scope. |
| `∧I` | Conjunction Introduction | Derives `A ∧ B` from `A` and `B` (both must be accessible). |
| `∧E` | Conjunction Elimination | Derives `A` (or `B`) from an accessible `A ∧ B`. |
| `∨I` | Disjunction Introduction | Derives `A ∨ B` from an accessible `A` (or `B`). |
| `∨E` | Disjunction Elimination | Derives `C` from an accessible `A ∨ B`, plus two subproofs: `A ⊢ C` and `B ⊢ C`. |
| `→I` | Implication Introduction | Derives `A → B` from a subproof that assumes `A` and derives `B`. |
| `→E` | Implication Elimination (Modus Ponens) | Derives `B` from accessible `A → B` and `A`. |
| `↔I` | Biconditional Introduction | Derives `A ↔ B` from two subproofs: `A ⊢ B` and `B ⊢ A`. |
| `↔E` | Biconditional Elimination | Derives `B` from `A ↔ B` and `A`, or `A` from `A ↔ B` and `B`. |
| `¬I` | Negation Introduction | Derives `¬A` from a subproof that assumes `A` and derives `⊥`. |
| `¬E` | Negation Elimination | Derives `⊥` from accessible `A` and `¬A`. |
| `RAA` | Reductio ad Absurdum | Derives `A` from a subproof that assumes `¬A` and derives `⊥`. |

| Abbr. | Human-Readable Name | Description |
| :--- | :--- | :--- |
| `PR` | Premise | Introduces a top‑level assumption from the problem statement. |
| `AS` | Assumption | Begins a nested subproof by assuming the given formula. |
| `R` | Reiteration | Copies an accessible formula from an outer scope into the current scope. |
| `⊥E` | Bottom Elimination / Explosion | Derives any formula from an accessible contradiction (`⊥`). |
| `∧I` | Conjunction Introduction | Derives `A ∧ B` from `A` and `B` (both must be accessible). |
| `∧E1`, `∧E2` | Conjunction Elimination | Derives `A` or `B`, respectively, from an accessible `A ∧ B`. |
| `∨I1`, `∨I2` | Disjunction Introduction | Derives `A ∨ B` from an accessible `A` or `B`, respectively. |
| `∨E` | Disjunction Elimination | Derives `C` from an accessible `A ∨ B`, plus two subproofs: `A ⊢ C` and `B ⊢ C`. |
| `→I` | Implication Introduction | Derives `A → B` from a subproof that assumes `A` and derives `B`. |
| `→E` | Implication Elimination (Modus Ponens) | Derives `B` from accessible `A → B` and `A`. |
| `↔I` | Biconditional Introduction | Derives `A ↔ B` from accessible `A → B` and `B → A`. |
| `↔E1`, `↔E2` | Biconditional Elimination | Derives `A → B` or `B → A`, respectively, from an accessible `A ↔ B`. |
| `¬I` | Negation Introduction | Derives `¬A` from a subproof that assumes `A` and derives `⊥`. |
| `¬E` | Negation Elimination | Derives `⊥` from accessible `A` and `¬A`. |
| `RAA` | Reductio ad Absurdum | Derives `A` from a subproof that assumes `¬A` and derives `⊥`. |

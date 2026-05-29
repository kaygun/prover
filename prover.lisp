;;; nd-prover-standalone-refactored.lisp
;;;
;;; Single-purpose classical propositional natural-deduction prover.
;;; Usage:
;;;
;;;   sbcl --script nd-prover-standalone-refactored.lisp problem.nd
;;;
;;; The input file contains zero or more premise lines, then a separator line
;;; consisting of at least five hyphens, then exactly one conclusion line.
;;;
;;; This is propositional logic, not first-order predicate logic.  There are no
;;; terms, quantifiers, equality, substitutions, or eigenvariable conditions.

(defpackage :nd-prover
  (:use :cl))

(in-package :nd-prover)

;;;; Formulas

(defstruct (bot  (:constructor bot ())))
(defstruct (pred (:constructor pred (name))) name)
(defstruct (neg  (:constructor neg (arg))) arg)
(defstruct (conj (:constructor conj (left right))) left right)
(defstruct (disj (:constructor disj (left right))) left right)
(defstruct (impl (:constructor impl (left right))) left right)
(defstruct (iff* (:constructor iff* (left right))) left right)

(defparameter +bot+ (bot))

(defun formula= (left right)
  (equalp left right))

(defun formula-precedence (formula)
  (etypecase formula
    (iff* 1)
    (impl 2)
    (disj 3)
    (conj 4)
    (neg  5)
    ((or pred bot) 6)))

(defun formula-to-string (formula &optional (context-precedence 0))
  (labels ((show (subformula precedence)
             (formula-to-string subformula precedence))
           (wrap (string precedence)
             (if (< precedence context-precedence)
                 (format nil "(~A)" string)
                 string)))
    (let ((precedence (formula-precedence formula)))
      (etypecase formula
        (bot "⊥")
        (pred (pred-name formula))
        (neg
         (wrap (format nil "¬~A" (show (neg-arg formula) precedence))
               precedence))
        (conj
         (wrap (format nil "~A ∧ ~A"
                       (show (conj-left formula) precedence)
                       (show (conj-right formula) precedence))
               precedence))
        (disj
         (wrap (format nil "~A ∨ ~A"
                       (show (disj-left formula) precedence)
                       (show (disj-right formula) precedence))
               precedence))
        (impl
         (wrap (format nil "~A → ~A"
                       (show (impl-left formula) (1+ precedence))
                       (show (impl-right formula) precedence))
               precedence))
        (iff*
         (wrap (format nil "~A ↔ ~A"
                       (show (iff*-left formula) precedence)
                       (show (iff*-right formula) precedence))
               precedence))))))

(defun subformulas (formula)
  (labels ((walk (f)
             (etypecase f
               ((or bot pred) (list f))
               (neg (cons f (walk (neg-arg f))))
               (conj (cons f (append (walk (conj-left f))
                                      (walk (conj-right f)))))
               (disj (cons f (append (walk (disj-left f))
                                      (walk (disj-right f)))))
               (impl (cons f (append (walk (impl-left f))
                                      (walk (impl-right f)))))
               (iff* (cons f (append (walk (iff*-left f))
                                      (walk (iff*-right f))))))))
    (walk formula)))

;;;; Parser

(defstruct (token (:constructor token (kind text))) kind text)

(defparameter *compound-tokens*
  '(("<->" . :iff) ("<=>" . :iff)
    ("->"  . :imp) ("=>"  . :imp)))

(defun whitespacep (char)
  (member char '(#\Space #\Tab #\Newline #\Return) :test #'char=))

(defun identifier-start-p (char)
  (or (alpha-char-p char) (char= char #\_)))

(defun identifier-char-p (char)
  (or (alphanumericp char) (member char '(#\_ #\') :test #'char=)))

(defun prefix-at-p (prefix string start)
  (let ((end (+ start (length prefix))))
    (and (<= end (length string))
         (string= prefix string :start2 start :end2 end))))

(defun read-identifier (string start)
  (loop for end from start below (length string)
        while (identifier-char-p (char string end))
        finally (return (values (subseq string start end) end))))

(defun word-token-kind (word)
  (let ((word (string-downcase word)))
    (cond
      ((string= word "not") :not)
      ((string= word "and") :and)
      ((or (string= word "or") (string= word "v")) :or)
      ((or (string= word "imp") (string= word "implies")) :imp)
      ((or (string= word "iff") (string= word "equiv")) :iff)
      ((member word '("bot" "bottom" "false") :test #'string=) :bot)
      (t :atomic))))

(defun single-character-token-kind (char)
  (cond
    ((char= char #\() :lparen)
    ((char= char #\)) :rparen)
    ((member char '(#\∧ #\& #\^) :test #'char=) :and)
    ((member char '(#\∨ #\|) :test #'char=) :or)
    ((member char '(#\¬ #\~) :test #'char=) :not)
    ((member char '(#\→ #\⇒) :test #'char=) :imp)
    ((char= char #\↔) :iff)
    ((char= char #\⊥) :bot)
    (t nil)))

(defun read-compound-token (string start)
  (loop for (text . kind) in *compound-tokens*
        when (prefix-at-p text string start)
          return (values (token kind text) (+ start (length text)))))

(defun tokenize (input)
  (loop with tokens = '()
        with i = 0
        while (< i (length input)) do
          (let ((char (char input i)))
            (cond
              ((whitespacep char)
               (incf i))
              ((multiple-value-bind (compound next) (read-compound-token input i)
                 (when compound
                   (push compound tokens)
                   (setf i next)
                   t)))
              ((single-character-token-kind char)
               (push (token (single-character-token-kind char) (string char)) tokens)
               (incf i))
              ((identifier-start-p char)
               (multiple-value-bind (word next) (read-identifier input i)
                 (push (token (word-token-kind word) word) tokens)
                 (setf i next)))
              (t
               (error "Unexpected character ~S in formula ~S." char input))))
        finally (return (nreverse tokens))))

(defun parse-formula (input)
  (let* ((tokens (coerce (tokenize input) 'vector))
         (position 0))
    (labels ((peek ()
               (and (< position (length tokens)) (aref tokens position)))
             (peek-kind ()
               (and (peek) (token-kind (peek))))
             (accept (kind)
               (when (eq (peek-kind) kind)
                 (prog1 (peek) (incf position))))
             (expect (kind)
               (or (accept kind)
                   (error "Expected ~A while parsing ~S." kind input)))
             (atomic ()
               (cond
                 ((accept :bot) +bot+)
                 ((eq (peek-kind) :atomic)
                  (pred (token-text (accept :atomic))))
                 ((accept :lparen)
                  (prog1 (iff) (expect :rparen)))
                 (t
                  (error "Expected an atomicic formula while parsing ~S." input))))
             (negation ()
               (if (accept :not) (neg (negation)) (atomic)))
             (left-associative (reader token-kind constructor)
               (loop with formula = (funcall reader)
                     while (accept token-kind)
                     do (setf formula (funcall constructor formula (funcall reader)))
                     finally (return formula)))
             (conjunction ()
               (left-associative #'negation :and #'conj))
             (disjunction ()
               (left-associative #'conjunction :or #'disj))
             (implication ()
               ;; Right-associative: P -> Q -> R means P -> (Q -> R).
               (let ((left (disjunction)))
                 (if (accept :imp)
                     (impl left (implication))
                     left)))
             (iff ()
               (left-associative #'implication :iff #'iff*)))
      (prog1 (iff)
        (when (< position (length tokens))
          (error "Unexpected token ~S after complete formula in ~S."
                 (token-text (aref tokens position))
                 input))))))

;;;; Proof terms and search contexts

(defstruct (term (:constructor term (kind formula args))) kind formula args)
(defstruct (entry (:constructor entry (formula term))) formula term)

(defun make-term (kind formula &rest args)
  (term kind formula args))

(defun first-result (function list)
  (loop for item in list
        for result = (funcall function item)
        when result return result))

(defun find-entry (formula context)
  (find formula context :key #'entry-formula :test #'formula=))

(defun context-formulas (context)
  (mapcar #'entry-formula context))

(defun context-signature (context)
  (sort (remove-duplicates (mapcar #'formula-to-string (context-formulas context))
                            :test #'string=)
        #'string<))

(defun search-key (goal context)
  (cons (formula-to-string goal) (context-signature context)))

(defun context-pool (goal context)
  (remove-duplicates
   (mapcan #'subformulas (cons goal (context-formulas context)))
   :test #'formula=))


(defun saturate-context (context)
  "Close CONTEXT under finite, immediate elimination consequences."
  (loop with changed = t
        while changed do
          (setf changed nil)
          (dolist (item (copy-list context))
            (let ((formula (entry-formula item))
                  (proof (entry-term item)))
              (labels ((add (new-formula new-proof)
                         (unless (find-entry new-formula context)
                           (push (entry new-formula new-proof) context)
                           (setf changed t))))
                (cond
                  ((conj-p formula)
                   (add (conj-left formula)
                        (make-term :and-elim-left (conj-left formula) proof))
                   (add (conj-right formula)
                        (make-term :and-elim-right (conj-right formula) proof)))
                  ((iff*-p formula)
                   (let ((forward (impl (iff*-left formula) (iff*-right formula)))
                         (backward (impl (iff*-right formula) (iff*-left formula))))
                     (add forward (make-term :iff-elim-left forward proof))
                     (add backward (make-term :iff-elim-right backward proof))))
                  ((impl-p formula)
                   (let ((antecedent (find-entry (impl-left formula) context)))
                     (when antecedent
                       (add (impl-right formula)
                            (make-term :imp-elim
                                       (impl-right formula)
                                       proof
                                       (entry-term antecedent))))))
                  ((neg-p formula)
                   (let ((positive (find-entry (neg-arg formula) context)))
                     (when positive
                       (add +bot+
                            (make-term :not-elim
                                       +bot+
                                       (entry-term positive)
                                       proof))))))))))
  context)

(defparameter *default-depth* 60)
(defparameter *classical* t)

(defun fresh-assumption (formula)
  (make-term :assumption formula (gensym "ASSUMPTION-")))

(defun premise-entries (premises)
  (loop for formula in premises
        collect (entry formula (make-term :premise formula (gensym "PREMISE-")))))

(defun prove-term (goal premises &key
                          (classical *classical*)
                          (depth *default-depth*)
                          (active (make-hash-table :test #'equal))
                          (failed (make-hash-table :test #'equal)))
  "Return a natural-deduction proof term for GOAL from PREMISES, or NIL.

The search is intentionally bounded and subformula-guided.  ACTIVE prevents
cyclic descent along the current search branch; FAILED memoizes failed sequents
at a remaining-depth bound."
  (labels ((failed-p (key fuel)
             (let ((old (gethash key failed)))
               (and old (>= old fuel))))
           (remember-failure (key fuel)
             (let ((old (gethash key failed)))
               (when (or (null old) (> fuel old))
                 (setf (gethash key failed) fuel))))
           (prove (target context fuel)
             (when (minusp fuel)
               (return-from prove nil))
             (let* ((context (saturate-context context))
                    (key (search-key target context)))
               (when (or (gethash key active) (failed-p key fuel))
                 (return-from prove nil))
               (setf (gethash key active) t)
               (let ((result nil))
                 (unwind-protect
                      (setf result
                            (or (prove-known target context)
                                (prove-existing-bottom target context)
                                (prove-by-direct-elimination target context fuel)
                                (and (bot-p target)
                                     (prove-bottom target context fuel))
                                (prove-by-conjunction-elimination target context fuel)
                                (prove-by-disjunction-elimination target context fuel)
                                (prove-by-introduction target context fuel)
                                (prove-by-ex-falso target context fuel)
                                (prove-by-raa target context fuel)))
                   (remhash key active))
                 (unless result
                   (remember-failure key fuel))
                 result)))
           (prove-known (target context)
             (let ((entry (find-entry target context)))
               (and entry (entry-term entry))))
           (prove-existing-bottom (target context)
             (unless (bot-p target)
               (let ((bottom (find-entry +bot+ context)))
                 (and bottom (make-term :bot-elim target (entry-term bottom))))))
           (prove-by-direct-elimination (target context fuel)
             (first-result
              (lambda (item)
                (let ((formula (entry-formula item))
                      (proof (entry-term item)))
                  (cond
                    ((and (impl-p formula) (formula= (impl-right formula) target))
                     (let ((antecedent (prove (impl-left formula) context (1- fuel))))
                       (and antecedent (make-term :imp-elim target proof antecedent))))
                    ((and (bot-p target) (neg-p formula))
                     (let ((positive (prove (neg-arg formula) context (1- fuel))))
                       (and positive (make-term :not-elim +bot+ positive proof)))))))
              context))
           (prove-bottom (target context fuel)
             (declare (ignore target))
             (or
              (first-result
               (lambda (item)
                 (let ((formula (entry-formula item))
                       (proof (entry-term item)))
                   (when (neg-p formula)
                     (let ((positive (prove (neg-arg formula) context (1- fuel))))
                       (and positive (make-term :not-elim +bot+ positive proof))))))
               context)
              (first-result
               (lambda (candidate)
                 (when (neg-p candidate)
                   (let ((negative (prove candidate context (1- fuel))))
                     (when negative
                       (let ((positive (prove (neg-arg candidate) context (1- fuel))))
                         (and positive
                              (make-term :not-elim +bot+ positive negative)))))))
               (context-pool +bot+ context))))
           (prove-by-conjunction-elimination (target context fuel)
             (first-result
              (lambda (candidate)
                (when (conj-p candidate)
                  (cond
                    ((formula= target (conj-left candidate))
                     (let ((conjunction (prove candidate context (1- fuel))))
                       (and conjunction
                            (make-term :and-elim-left target conjunction))))
                    ((formula= target (conj-right candidate))
                     (let ((conjunction (prove candidate context (1- fuel))))
                       (and conjunction
                            (make-term :and-elim-right target conjunction)))))))
              (context-pool target context)))
           (prove-by-disjunction-elimination (target context fuel)
             (first-result
              (lambda (item)
                (let ((formula (entry-formula item))
                      (proof (entry-term item)))
                  (when (disj-p formula)
                    (let* ((left-assumption (fresh-assumption (disj-left formula)))
                           (left-context (cons (entry (disj-left formula) left-assumption)
                                               context))
                           (left-proof (prove target left-context (1- fuel))))
                      (when left-proof
                        (let* ((right-assumption (fresh-assumption (disj-right formula)))
                               (right-context (cons (entry (disj-right formula) right-assumption)
                                                    context))
                               (right-proof (prove target right-context (1- fuel))))
                          (and right-proof
                               (make-term :or-elim target
                                          proof
                                          left-assumption left-proof
                                          right-assumption right-proof))))))))
              context))
           (prove-by-introduction (target context fuel)
             (cond
               ((conj-p target)
                (let ((left (prove (conj-left target) context (1- fuel))))
                  (when left
                    (let ((right (prove (conj-right target) context (1- fuel))))
                      (and right (make-term :and-intro target left right))))))
               ((impl-p target)
                (let* ((assumption (fresh-assumption (impl-left target)))
                       (body (prove (impl-right target)
                                    (cons (entry (impl-left target) assumption) context)
                                    (1- fuel))))
                  (and body (make-term :imp-intro target assumption body))))
               ((neg-p target)
                (let* ((assumption (fresh-assumption (neg-arg target)))
                       (body (prove +bot+
                                    (cons (entry (neg-arg target) assumption) context)
                                    (1- fuel))))
                  (and body (make-term :not-intro target assumption body))))
               ((iff*-p target)
                (let ((forward (prove (impl (iff*-left target) (iff*-right target))
                                      context
                                      (1- fuel))))
                  (when forward
                    (let ((backward (prove (impl (iff*-right target) (iff*-left target))
                                           context
                                           (1- fuel))))
                      (and backward (make-term :iff-intro target forward backward))))))
               ((disj-p target)
                (or (let ((left (prove (disj-left target) context (1- fuel))))
                      (and left (make-term :or-intro-left target left)))
                    (let ((right (prove (disj-right target) context (1- fuel))))
                      (and right (make-term :or-intro-right target right)))))))
           (prove-by-ex-falso (target context fuel)
             (unless (bot-p target)
               (let ((bottom (prove +bot+ context (1- fuel))))
                 (and bottom (make-term :bot-elim target bottom)))))
           (prove-by-raa (target context fuel)
             (when (and classical (not (bot-p target)))
               (let* ((assumption (fresh-assumption (neg target)))
                      (body (prove +bot+
                                   (cons (entry (neg target) assumption) context)
                                   (1- fuel))))
                 (and body (make-term :raa target assumption body))))))
    (prove goal premises depth)))

;;;; Linear Fitch-style proofs

(defstruct (proof-line (:constructor proof-line (number depth formula rule citations)))
  number depth formula rule citations)

(defstruct (proof (:constructor make-proof ()))
  (lines (make-array 0 :adjustable t :fill-pointer 0))
  (counter 0 :type fixnum)
  (depth 0 :type fixnum))

(defun emit-line (proof formula rule citations)
  (let* ((number (incf (proof-counter proof)))
         (line (proof-line number (proof-depth proof) formula rule citations)))
    (vector-push-extend line (proof-lines proof))
    number))

(defmacro with-subproof ((proof) &body body)
  `(progn
     (incf (proof-depth ,proof))
     (unwind-protect (progn ,@body)
       (decf (proof-depth ,proof)))))

(defun proof-line-by-number (proof number)
  (loop for line across (proof-lines proof)
        when (= number (proof-line-number line)) return line))

(defun available-term-line (term environment)
  (or (cdr (assoc term environment :test #'eq))
      (error "Proof term ~S is not available in the current scope." term)))

(defun line-at-current-depth (proof line-number)
  "Return LINE-NUMBER, or emit a reiteration line at the current depth."
  (let ((line (proof-line-by-number proof line-number)))
    (unless line
      (error "Cannot reiterate missing line ~D." line-number))
    (cond
      ((= (proof-line-depth line) (proof-depth proof))
       line-number)
      ((< (proof-line-depth line) (proof-depth proof))
       (emit-line proof (proof-line-formula line) "R" (list line-number)))
      (t
       (error "Cannot cite line ~D from a closed subproof." line-number)))))

(defun linearize-subproof (proof assumption body environment)
  "Linearize BODY under ASSUMPTION.  Return the assumption and endpoint lines."
  (let (assumption-line endpoint-line)
    (setf endpoint-line
          (with-subproof (proof)
            (setf assumption-line
                  (emit-line proof (term-formula assumption) "AS" nil))
            (line-at-current-depth
             proof
             (linearize-term body proof (acons assumption assumption-line environment)))))
    (values assumption-line endpoint-line)))

(defun linearize-discharged-rule (term proof environment rule)
  (destructuring-bind (assumption body) (term-args term)
    (multiple-value-bind (assumption-line endpoint-line)
        (linearize-subproof proof assumption body environment)
      (emit-line proof (term-formula term) rule
                 (list assumption-line endpoint-line)))))

(defun linearize-term (term proof environment)
  (ecase (term-kind term)
    ((:premise :assumption)
     (available-term-line term environment))
    (:and-intro
     (destructuring-bind (left right) (term-args term)
       (emit-line proof (term-formula term) "∧I"
                  (list (linearize-term left proof environment)
                        (linearize-term right proof environment)))))
    (:and-elim-left
     (destructuring-bind (conjunction) (term-args term)
       (emit-line proof (term-formula term) "∧E1"
                  (list (linearize-term conjunction proof environment)))))
    (:and-elim-right
     (destructuring-bind (conjunction) (term-args term)
       (emit-line proof (term-formula term) "∧E2"
                  (list (linearize-term conjunction proof environment)))))
    (:imp-intro
     (linearize-discharged-rule term proof environment "→I"))
    (:imp-elim
     (destructuring-bind (implication antecedent) (term-args term)
       (emit-line proof (term-formula term) "→E"
                  (list (linearize-term implication proof environment)
                        (linearize-term antecedent proof environment)))))
    (:not-intro
     (linearize-discharged-rule term proof environment "¬I"))
    (:not-elim
     (destructuring-bind (positive negative) (term-args term)
       (emit-line proof +bot+ "¬E"
                  (list (linearize-term positive proof environment)
                        (linearize-term negative proof environment)))))
    (:bot-elim
     (destructuring-bind (bottom) (term-args term)
       (emit-line proof (term-formula term) "⊥E"
                  (list (linearize-term bottom proof environment)))))
    (:or-intro-left
     (destructuring-bind (left) (term-args term)
       (emit-line proof (term-formula term) "∨I1"
                  (list (linearize-term left proof environment)))))
    (:or-intro-right
     (destructuring-bind (right) (term-args term)
       (emit-line proof (term-formula term) "∨I2"
                  (list (linearize-term right proof environment)))))
    (:or-elim
     (destructuring-bind (disjunction left-assumption left-proof right-assumption right-proof)
         (term-args term)
       (let ((disjunction-line (linearize-term disjunction proof environment)))
         (multiple-value-bind (left-assumption-line left-proof-line)
             (linearize-subproof proof left-assumption left-proof environment)
           (multiple-value-bind (right-assumption-line right-proof-line)
               (linearize-subproof proof right-assumption right-proof environment)
             (emit-line proof (term-formula term) "∨E"
                        (list disjunction-line
                              left-assumption-line left-proof-line
                              right-assumption-line right-proof-line)))))))
    (:iff-intro
     (destructuring-bind (forward backward) (term-args term)
       (emit-line proof (term-formula term) "↔I"
                  (list (linearize-term forward proof environment)
                        (linearize-term backward proof environment)))))
    (:iff-elim-left
     (destructuring-bind (biconditional) (term-args term)
       (emit-line proof (term-formula term) "↔E1"
                  (list (linearize-term biconditional proof environment)))))
    (:iff-elim-right
     (destructuring-bind (biconditional) (term-args term)
       (emit-line proof (term-formula term) "↔E2"
                  (list (linearize-term biconditional proof environment)))))
    (:raa
     (linearize-discharged-rule term proof environment "RAA"))))

(defun linearize-proof (premise-entries root-term)
  (let ((proof (make-proof))
        (environment nil))
    (dolist (premise premise-entries)
      (let ((line (emit-line proof (entry-formula premise) "PR" nil)))
        (push (cons (entry-term premise) line) environment)))
    (linearize-term root-term proof environment)
    proof))

(defun prove (premises conclusion &key
                       (classical *classical*)
                       (depth *default-depth*))
  (let* ((entries (premise-entries premises))
         (root (prove-term conclusion entries :classical classical :depth depth)))
    (and root (linearize-proof entries root))))

;;;; Proof checker

(defun line-error (line control &rest arguments)
  (apply #'error
         (concatenate 'string "Line ~D " control)
         (proof-line-number line)
         arguments))

(defun require-citation-count (line count)
  (unless (= (length (proof-line-citations line)) count)
    (line-error line "uses rule ~A with ~D citation(s), but ~D are required."
                (proof-line-rule line)
                (length (proof-line-citations line))
                count)))

(defun cite (proof line number &key (ordinary t))
  (let ((source (proof-line-by-number proof number)))
    (unless source
      (line-error line "cites missing line ~D." number))
    (when (>= (proof-line-number source) (proof-line-number line))
      (line-error line "cites non-previous line ~D." number))
    (when (and ordinary (> (proof-line-depth source) (proof-line-depth line)))
      (line-error line "illegally cites line ~D from a closed subproof." number))
    source))

(defun cited-lines (proof line &key (ordinary t))
  (mapcar (lambda (number) (cite proof line number :ordinary ordinary))
          (proof-line-citations line)))

(defun valid-subproof-endpoints-p (line assumption body)
  (and (string= (proof-line-rule assumption) "AS")
       (= (proof-line-depth assumption) (1+ (proof-line-depth line)))
       (>= (proof-line-depth body) (proof-line-depth assumption))))

(defun check-discharged-rule (proof line conclusion-p)
  (require-citation-count line 2)
  (destructuring-bind (assumption body)
      (cited-lines proof line :ordinary nil)
    (unless (and (valid-subproof-endpoints-p line assumption body)
                 (funcall conclusion-p
                          (proof-line-formula line)
                          (proof-line-formula assumption)
                          (proof-line-formula body)))
      (line-error line "is not a valid ~A line." (proof-line-rule line)))))

(defun check-proof-line (proof line)
  (let ((rule (proof-line-rule line))
        (formula (proof-line-formula line)))
    (cond
      ((member rule '("PR" "AS") :test #'string=)
       (require-citation-count line 0))
      ((string= rule "R")
       (require-citation-count line 1)
       (destructuring-bind (source) (cited-lines proof line)
         (unless (formula= formula (proof-line-formula source))
           (line-error line "is not a valid reiteration line."))))
      ((string= rule "∧I")
       (require-citation-count line 2)
       (destructuring-bind (left right) (cited-lines proof line)
         (unless (and (conj-p formula)
                      (formula= (conj-left formula) (proof-line-formula left))
                      (formula= (conj-right formula) (proof-line-formula right)))
           (line-error line "is not a valid ∧I line."))))
      ((member rule '("∧E1" "∧E2") :test #'string=)
       (require-citation-count line 1)
       (destructuring-bind (source) (cited-lines proof line)
         (let ((source-formula (proof-line-formula source)))
           (unless (and (conj-p source-formula)
                        (formula= formula
                                  (if (string= rule "∧E1")
                                      (conj-left source-formula)
                                      (conj-right source-formula))))
             (line-error line "is not a valid ~A line." rule)))))
      ((string= rule "→E")
       (require-citation-count line 2)
       (destructuring-bind (implication antecedent) (cited-lines proof line)
         (let ((implication-formula (proof-line-formula implication)))
           (unless (and (impl-p implication-formula)
                        (formula= (impl-left implication-formula)
                                  (proof-line-formula antecedent))
                        (formula= (impl-right implication-formula) formula))
             (line-error line "is not a valid →E line.")))))
      ((string= rule "→I")
       (check-discharged-rule
        proof line
        (lambda (line-formula assumption-formula body-formula)
          (and (impl-p line-formula)
               (formula= (impl-left line-formula) assumption-formula)
               (formula= (impl-right line-formula) body-formula)))))
      ((string= rule "¬I")
       (check-discharged-rule
        proof line
        (lambda (line-formula assumption-formula body-formula)
          (and (neg-p line-formula)
               (formula= (neg-arg line-formula) assumption-formula)
               (bot-p body-formula)))))
      ((string= rule "¬E")
       (require-citation-count line 2)
       (destructuring-bind (positive negative) (cited-lines proof line)
         (let ((negative-formula (proof-line-formula negative)))
           (unless (and (bot-p formula)
                        (neg-p negative-formula)
                        (formula= (neg-arg negative-formula)
                                  (proof-line-formula positive)))
             (line-error line "is not a valid ¬E line.")))))
      ((string= rule "⊥E")
       (require-citation-count line 1)
       (destructuring-bind (bottom) (cited-lines proof line)
         (unless (bot-p (proof-line-formula bottom))
           (line-error line "is not a valid ⊥E line."))))
      ((member rule '("∨I1" "∨I2") :test #'string=)
       (require-citation-count line 1)
       (destructuring-bind (source) (cited-lines proof line)
         (unless (and (disj-p formula)
                      (formula= (proof-line-formula source)
                                (if (string= rule "∨I1")
                                    (disj-left formula)
                                    (disj-right formula))))
           (line-error line "is not a valid ~A line." rule))))
      ((string= rule "∨E")
       (require-citation-count line 5)
       (destructuring-bind (disjunction-number left-assumption-number left-body-number
                            right-assumption-number right-body-number)
           (proof-line-citations line)
         (let ((disjunction (cite proof line disjunction-number))
               (left-assumption (cite proof line left-assumption-number :ordinary nil))
               (left-body (cite proof line left-body-number :ordinary nil))
               (right-assumption (cite proof line right-assumption-number :ordinary nil))
               (right-body (cite proof line right-body-number :ordinary nil)))
           (let ((disjunction-formula (proof-line-formula disjunction)))
             (unless (and (disj-p disjunction-formula)
                          (valid-subproof-endpoints-p line left-assumption left-body)
                          (valid-subproof-endpoints-p line right-assumption right-body)
                          (formula= (proof-line-formula left-assumption)
                                    (disj-left disjunction-formula))
                          (formula= (proof-line-formula right-assumption)
                                    (disj-right disjunction-formula))
                          (formula= formula (proof-line-formula left-body))
                          (formula= formula (proof-line-formula right-body)))
               (line-error line "is not a valid ∨E line."))))))
      ((string= rule "↔I")
       (require-citation-count line 2)
       (destructuring-bind (forward backward) (cited-lines proof line)
         (let ((forward-formula (proof-line-formula forward))
               (backward-formula (proof-line-formula backward)))
           (unless (and (iff*-p formula)
                        (impl-p forward-formula)
                        (impl-p backward-formula)
                        (formula= (impl-left forward-formula) (iff*-left formula))
                        (formula= (impl-right forward-formula) (iff*-right formula))
                        (formula= (impl-left backward-formula) (iff*-right formula))
                        (formula= (impl-right backward-formula) (iff*-left formula)))
             (line-error line "is not a valid ↔I line.")))))
      ((member rule '("↔E1" "↔E2") :test #'string=)
       (require-citation-count line 1)
       (destructuring-bind (source) (cited-lines proof line)
         (let ((source-formula (proof-line-formula source)))
           (unless (and (iff*-p source-formula)
                        (impl-p formula)
                        (if (string= rule "↔E1")
                            (and (formula= (impl-left formula) (iff*-left source-formula))
                                 (formula= (impl-right formula) (iff*-right source-formula)))
                            (and (formula= (impl-left formula) (iff*-right source-formula))
                                 (formula= (impl-right formula) (iff*-left source-formula)))))
             (line-error line "is not a valid ~A line." rule)))))
      ((string= rule "RAA")
       (check-discharged-rule
        proof line
        (lambda (line-formula assumption-formula body-formula)
          (and (neg-p assumption-formula)
               (formula= (neg-arg assumption-formula) line-formula)
               (bot-p body-formula)))))
      (t
       (line-error line "has unknown rule ~S." rule)))))

(defun check-proof (proof)
  (loop for line across (proof-lines proof) do
    (check-proof-line proof line))
  t)

;;;; Input and output

(defun trim-line (line)
  (string-trim '(#\Space #\Tab #\Return) line))

(defun blank-line-p (line)
  (zerop (length (trim-line line))))

(defun separator-line-p (line)
  (let ((line (trim-line line)))
    (and (>= (length line) 5)
         (every (lambda (char) (char= char #\-)) line))))

(defun read-nonblank-lines (pathname)
  (with-open-file (stream pathname :direction :input)
    (loop for line = (read-line stream nil nil)
          while line
          unless (blank-line-p line)
            collect (trim-line line))))

(defun read-problem (pathname)
  (let* ((lines (read-nonblank-lines pathname))
         (separator (position-if #'separator-line-p lines)))
    (unless separator
      (error "~A has no separator line of five or more hyphens." pathname))
    (when (position-if #'separator-line-p lines :start (1+ separator))
      (error "~A has more than one separator line." pathname))
    (let ((premise-lines (subseq lines 0 separator))
          (conclusion-lines (subseq lines (1+ separator))))
      (unless (= (length conclusion-lines) 1)
        (error "~A must contain exactly one conclusion line; found ~D."
               pathname
               (length conclusion-lines)))
      (values (mapcar #'parse-formula premise-lines)
              (parse-formula (first conclusion-lines))))))

(defun citation-string (citations)
  (if citations (format nil "~{~D~^,~}" citations) ""))

(defun print-proof (proof &optional (stream *standard-output*))
  (loop for line across (proof-lines proof) do
    (format stream "~3D. ~A~A~40T~A~48T~A~%"
            (proof-line-number line)
            (make-string (* 2 (proof-line-depth line)) :initial-element #\Space)
            (formula-to-string (proof-line-formula line))
            (proof-line-rule line)
            (citation-string (proof-line-citations line))))
  proof)

;;;; Script entry point

(defun script-arguments ()
  #+sbcl
  (let* ((argv sb-ext:*posix-argv*)
         (script (and *load-truename* (namestring *load-truename*))))
    (labels ((same-file-p (left right)
               (and left right
                    (handler-case (equal (truename left) (truename right))
                      (error () nil)))))
      (let ((script-position
              (position-if (lambda (argument) (same-file-p argument script)) argv)))
        (if script-position
            (subseq argv (1+ script-position))
            (rest argv)))))
  #-sbcl
  nil)

(defun quit (code)
  #-sbcl (declare (ignore code))
  #+sbcl (sb-ext:exit :code code)
  #-sbcl nil)

(defun main ()
  (let ((arguments (script-arguments)))
    (unless (= (length arguments) 1)
      (format *error-output* "Usage: sbcl --script PROVER.lisp FILE~%")
      (quit 2))
    (handler-case
        (multiple-value-bind (premises conclusion) (read-problem (first arguments))
          (let ((proof (prove premises conclusion)))
            (cond
              (proof
               (check-proof proof)
               (print-proof proof)
               (quit 0))
              (t
               (format *error-output* "No proof found.~%")
               (quit 1)))))
      (error (condition)
        (format *error-output* "Error: ~A~%" condition)
        (quit 1)))))

(main)

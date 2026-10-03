;;; SBCL command-line entry point.  Usage:
;;;   sbcl --script prover.lisp problem.nd
;;; For library use, load nd-prover.lisp instead.

(load (merge-pathnames "nd-prover.lisp" *load-truename*))

#+sbcl
(sb-ext:exit :code (nd-prover:main (rest sb-ext:*posix-argv*)))

#-sbcl
(error "Run this script with SBCL, or load nd-prover.lisp as a library.")

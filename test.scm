(add-load-path "./")
#< (srfi :105) >
(import (rnrs)
	(srfi :64))

(test-begin "SRFI-105 tests")

;; from SRFI-105 samples
(test-equal "1" '(* a (+ b c)) '{a * {b + c}})
(test-equal "2" '(eqv? x `a) '{x eqv? `a})
(test-equal "3" '(/ (- a) b) '{(- a) / b})
(test-equal "4" '(+ (f a b) (g h)) '{(f a b) + (g h)})
(test-equal "5" '(+ a (f b) x) '{a + (f b) + x})
(test-equal "6" '(and (> a 0) (>= b 1)) '{{a > 0} and {b >= 1}})

(test-end)
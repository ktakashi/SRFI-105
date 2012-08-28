;;; -*- code:scheme; coding: utf-8 -*-
;;;
;;; SRFI-105 - SRFI-105 library.
;;;
;;; Copyright (C) 2012 David A. Wheeler and Alan Manuel K. Gloria.
;;;         All Rights Reserved.
;;;
;;; Permission is hereby granted, free of charge, to any person obtaining
;;; a copy of this software and associated documentation files
;;; (the "Software"), to deal in the Software without restriction, including
;;; without limitation the rights to use, copy, modify, merge, publish,
;;; distribute, sublicense, and/or sell copies of the Software, and to permit
;;; persons to whom the Software is furnished to do so, subject to the
;;; following conditions:
;;;
;;; The above copyright notice and this permission notice shall be included
;;; in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;;; DEALINGS IN THE SOFTWARE.

;; Ported by Takashi Kato
;; From reference implementation
(library (srfi :105)
    (export :export-reader-macro)
    (import (rnrs) (sagittarius reader))
  ;; Return true if lyst has an even # of parameters, and the (alternating)
  ;; first parameters are "op".  Used to determine if a longer lyst is infix.
  ;; If passed empty list, returns true (so recursion works correctly).
  (define (even-and-op-prefix? op lyst)
    (cond
     ((null? lyst) #t)
     ((not (pair? lyst)) #f)
     ((not (eq? op (car lyst))) #f) ; fail - operators not the same
     ((not (pair? (cdr lyst)))  #f) ; Wrong # of parameters or improper
     (else (even-and-op-prefix? op (cddr lyst))))) ; recurse.

  ;; Return true if the lyst is in simple infix format
  ;; (and thus should be reordered at read time).
  (define (simple-infix-list? lyst)
    (and
     (pair? lyst)           ; Must have list;  '() doesn't count.
     (pair? (cdr lyst))     ; Must have a second argument.
     (pair? (cddr lyst))    ; Must have a third argument (we check it
					; this way for performance)
     (symbol? (cadr lyst))  ; 2nd parameter must be a symbol.
     (even-and-op-prefix? (cadr lyst) (cdr lyst)))) ; true if rest is simple

  ;; Return alternating parameters in a list (1st, 3rd, 5th, etc.)
  (define (alternating-parameters lyst)
    (if (or (null? lyst) (null? (cdr lyst)))
	lyst
	(cons (car lyst) (alternating-parameters (cddr lyst)))))

  ;; Not a simple infix list - transform it.  Written as a separate procedure
  ;; so that future experiments or SRFIs can easily replace just this piece.
  (define (transform-mixed-infix lyst)
    (cons 'nfx lyst))

  ;; Given curly-infix lyst, map it to its final internal format.
  (define (process-curly lyst)
    (cond
     ((not (pair? lyst)) lyst) ; E.G., map {} to ().
     ((null? (cdr lyst)) ; Map {a} to a.
      (car lyst))
     ((and (pair? (cdr lyst)) (null? (cddr lyst))) ; Map {a b} to (a b).
      lyst)
     ((simple-infix-list? lyst) ; Map {a OP b [OP c...]} to (OP a b [c...])
      (cons (cadr lyst) (alternating-parameters lyst)))
     (else  (transform-mixed-infix lyst))))

  ;; reader macro
  (define-reader-macro |{-reader|
    #\{
    (lambda (p c) (process-curly (read-delimited-list #\} p))))
  (define-reader-macro |}-reader|
    #\}
    (lambda (p c) (error '|}-reader| "unexpected #\\}")))
  
  )

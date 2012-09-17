;;; -*- mode:scheme; coding: utf-8; -*-
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
    (import (rnrs) (sagittarius) (sagittarius reader))
  ;; Return true if lyst has an even # of parameters, and the (alternating)
  ;; first parameters are "op".  Used to determine if a longer lyst is infix.
  ;; If passed empty list, returns true (so recursion works correctly).
  (define (even-and-op-prefix? op lyst)
    (cond
     ((null? lyst) #t)
     ((not (pair? lyst)) #f)
     ((not (equal? op (car lyst))) #f) ; fail - operators not the same
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
     (else (transform-mixed-infix lyst))))

  ;; From reference implementation but modified to be able to execute on
  ;; Sagittarius.

  ;; ------------------------------------------------
  ;; Key procedures to implement neoteric-expressions
  ;; ------------------------------------------------

  (define (read-error msg . irr) (apply error 'read-error msg irr))
  (define consume-to-eol get-line)

  ;; Read the "inside" of a list until its matching stop-char, returning list.
  ;; stop-char needs to be closing paren, closing bracket, or closing brace.
  ;; This is like read-delimited-list of Common Lisp.
  ;; This implements a useful extension: (. b) returns b.
  (define (my-read-delimited-list stop-char port)
    (let* ((c   (peek-char port)))
      (cond
       ((eof-object? c) (read-error "EOF in middle of list") '())
        ((eqv? c #\;)
	 (consume-to-eol port)
	 (my-read-delimited-list stop-char port))
        ((char-whitespace? c)
	 (read-char port)
	 (my-read-delimited-list stop-char port))
        ((char=? c stop-char)
	 (read-char port)
	 '())
        ((or (eqv? c #\)) (eqv? c #\]) (eqv? c #\}))
	 (read-char port)
	 (read-error "Bad closing character" c))
        (else
	 (let ((datum (neoteric-read port)))
	   (cond
	    ((eq? datum '|.|)
	     (let ((datum2 (neoteric-read port)))
	       (consume-whitespace port)
	       (cond
		((eof-object? datum2)
		 (read-error "Early eof in (... .)\n")
		  '())
		((not (eqv? (peek-char port) stop-char))
		 (read-error "Bad closing character after . datum" datum2))
		(else
		 (read-char port)
		 datum2))))
	    (else
	     (cons datum
		   (my-read-delimited-list stop-char port)))))))))
  
  ;; Implement neoteric-_expression_'s prefixed (), [], and {}.
  ;; At this point, we have just finished reading some _expression_, which
  ;; MIGHT be a prefix of some longer _expression_.  Examine the next
  ;; character to be consumed; if it's an opening paren, bracket, or brace,
  ;; then the _expression_ "prefix" is actually a prefix.
  ;; Otherwise, just return the prefix and do not consume that next char.
  ;; This recurses, to handle formats like f(x)(y).
  (define (neoteric-process-tail port prefix)
    (let* ((c (peek-char port)))
      (cond
       ((eof-object? c) prefix)
       ((char=? c #\( ) ; Implement f(x).
	(read-char port)
	(neoteric-process-tail port
			       (cons prefix (my-read-delimited-list #\) port))))
       ((char=? c #\[ )  ; Implement f[x]
	(read-char port)
	(neoteric-process-tail port
			       (cons 'bracketaccess
				     (cons prefix
					   (my-read-delimited-list #\] port)))))
       ((char=? c #\{ )  ; Implement f{x}. Balance }
	(neoteric-process-tail port
			       (let ((tail (neoteric-read port)))
				 (if (eqv? tail '())
				     (list prefix) ; Map f{} to (f), not (f ()).
				     (list prefix tail)))))
       (else prefix))))

  (define (neoteric-read . port)
    (if (null? port)
	(neoteric-read-real (current-input-port))
	(neoteric-read-real (car port))))
  
  ;; reference implementation does not have this
  (define-constant neoteric-delimiters 
    '(#\{ #\} #\( #\) #\[ #\] #\" #\;))
  ;; is this Guile's procedure?
  (define (read-until-delim port delims)
    (do ((c (peek-char port) (peek-char port)) (r '() (cons c r)))
	((or (char-whitespace? c) (memv c delims)) (reverse! r))
      (read-char port)))
  (define (read-number port initial)
    (do ((c (peek-char port) (peek-char port)) (r initial (cons c r)))
	((or (char-whitespace? c) (and (not (char-numeric? c))
				       (not (char=? c #\.))))
	 (string->number (list->string (reverse! r))))
      (read-char port)))

  ;; This is the "real" implementation of neoteric-read
  ;; (neoteric-read just figures out the port and calls neoteric-read-real).
  ;; It implements an entire reader, as a demonstration, but if you can
  ;; update your existing reader you should just update that instead.
  ;; This is a simple R5RS reader, with a few minor (common) extensions.
  ;; The key part is that it implements [] and {} as delimiters, and
  ;; after it reads in some datum (the "prefix"), it calls
  ;; neoteric-process-tail to see if there's a "tail".
  (define (neoteric-read-real port)
    (let* ((c (peek-char port))
	   (prefix
	    ;; This cond is a normal Scheme reader, puts result in "prefix"
	    ;; This implements "read-_expression_-as-usual" as described above.
	    (cond
	     ((eof-object? c) c)
	     ((char=? c #\;)
	      (consume-to-eol port)
	      (neoteric-read-real port))
	     ((char-whitespace? c)
	      (read-char port)
	      (neoteric-read-real port))
	     ((char=? c #\( )
	      (read-char port)
	      (my-read-delimited-list #\) port))
	     ((char=? c #\) )
	      (read-char port)
	      (read-error "Closing parenthesis without opening")
	      (neoteric-read-real port))
	     ((char=? c #\[ )
	      (read-char port)
	      (my-read-delimited-list #\] port))
	     ((char=? c #\] )
	      (read-char port)
	      (read-error "Closing bracket without opening")
	      (neoteric-read-real port))
	     ((char=? c #\{ )
	      (read-char port)
	      (process-curly
	       (my-read-delimited-list #\} port)))
	     ((char=? c #\} )
	      (read-char port)
	      (read-error "Closing brace without opening")
	      (neoteric-read-real port))
	     ((char=? c #\") ; Strings are delimited by ", so can call directly
	      (default-scheme-read port))
	     ((char=? c #\')
	      (read-char port)
	      (list 'quote (neoteric-read-real port)))
	     ((char=? c #\`)
	      (read-char port)
	      (list 'quasiquote (neoteric-read-real port)))
	     ((char=? c #\,)
	      (read-char port)
	      (cond
	       ((char=? #\@ (peek-char port))
		(read-char port)
		(list 'unquote-splicing (neoteric-read-real port)))
	       (else
		(list 'unquote (neoteric-read-real port)))))
	     ((char-numeric? c) ; Initial digit.
	      (read-number port '()))
	     ((char=? c #\#) (process-sharp port))
	     ((char=? c #\.) (process-period port))
	     ((or (char=? c #\+) (char=? c #\-))  ; Initial + or -
	      (read-char port)
	      (if (char-numeric? (peek-char port))
		  (read-number port (list c))
		  (string->symbol (list->string 
				   (cons c (read-until-delim 
					    port neoteric-delimiters))))))
	     (else ; Nothing else.  Must be a symbol start.
	      (string->symbol (list->string
			       (read-until-delim port neoteric-delimiters)))))))
      ;; Here's the big change to implement neoteric-expressions:
      (if (eof-object? prefix)
	  prefix
	  (neoteric-process-tail port prefix))))

  ;; We have too many possibilities to handle #\# so  let reader process 
  ;; it on Sagittarius.
  (define process-sharp read)

  (define (process-period port)
    ;; We've peeked a period character.  Returns what it represents.
    (read-char port) ; Remove .
    (let ((c (peek-char port)))
      (cond
       ((eof-object? c) '|.|) ; period eof; return period.
       ((char-numeric? c)
	(read-number port (list #\.)))  ; period digit - it's a number.
       (else
	;; At this point, Scheme only requires support for "." or "...".
	;; As an extension we can support them all.
	(string->symbol
	 (list->string (cons #\.
			     (read-until-delim port neoteric-delimiters))))))))

  ;; reader macro
  (define-reader-macro |{-reader|
    #\{
    (lambda (p c) (process-curly (my-read-delimited-list #\} p))))
  (define-reader-macro |}-reader|
    #\}
    (lambda (p c) (error '|}-reader| "unexpected #\\}")))
  
  )

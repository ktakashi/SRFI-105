# SRFI-105 experimental implementation for Sagittarius

## How to use?

    #< (srfi :105) >
    (print '{a + b})

or if you are using 0.3.7 (currently it's HEAD version) you can also use it with
this syntax

    #!read-macro=srfi/:105
    (print '{a + b})

or

    #!read-macro=curly-infix
    (print '{a + b})

The latter form is much easier to keep compatibility with other implementation
if it can handle `#!curly-infix` notation.

## Caution

This SRFI is not final yet, so it has high possibility to change.

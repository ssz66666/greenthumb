#lang s-exp rosette

(require "../validator.rkt"
         "../ast.rkt")
(provide llve-demo-validator%)

(define llve-demo-validator%
  (class validator%
    (super-new)
    (inherit-field printer)
    (inherit sym-op sym-arg encode-sym)
    (override encode-sym-inst) 

    ;; Encode instruction x.
    ;; If x is a concrete instruction, then encode textual representation using number.
    ;; If (inst-op x) = #f, create symbolic instruction.
    (define (encode-sym-inst x)
      (if (inst-op x)
          (send printer encode-inst x)
          (inst (sym-op) (vector (sym-arg) (sym-arg) (sym-arg)))))

    ))
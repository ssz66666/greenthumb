#lang racket

(require "controller.rkt" "state.rkt" "ast.rkt")

(define t (current-seconds))

;; (superoptimize (encode "325 b! @b push drop pop 325 b! @b 0 b! !b dup 0 b! @b or over 0 b! @b and or")
;;                (encode "_ _ _ _ _ _ _ _ _ _ _ _ _ _")
;;                (cons 1 2)
;;                (constraint r s t))

(superoptimize (encode "65536 2*")
               (encode "_")
               (cons 0 0)
               (constraint [data 1] s t))

;; (print-program
;; (superoptimize (encode (list (block "-3" #f #f) (-iftf "1" "2")))
;;                (encode (list (block "_" #f #f) (-iftf "1" "2")))
;;                (cons 0 0)
;;                (constraint t)))
;; (print-program
;; (superoptimize (encode (forloop "3" "0"))
;;                (encode (forloop "3" "dup dup or"))
;;                (cons 0 0)
;;                (constraint memory r s t)))


;; (superoptimize (encode "a 277 b! dup or a! @+ !b @+ !b @+
;; 277 a! ! 3 b! @b ! 0 b! @b !
;; 277 b! @b 0 b! !b 1 b! @b 277 b! !b 277 b! @b 1" 
;; (encode "a 277 b! dup or a! @+ !b @+ !b @+
;; 277 a! ! 3 b! @b ! 0 b! @b !)
;; _ _ _ _ _ _ _ _") 
;;                (cons 4 2)
;;                (constraint memory s t))

;;;;;;;;;;;;;;;; assume ;;;;;;;;;;;;;;;;;;
;; (superoptimize (encode "0 a! !+ push !+ pop dup 1 b! @b 0 b! @b 65535 or over - and + or push drop pop")
;;                (encode "_ _ _ _ _ _ _ _ _")
;;                (cons 2 0)
;;                (constraint s t)
;;                #:assume (constrain-stack '((<= . 65535) (<= . 65535) (<= . 65535))))

;;;;;;;;;;;;;;;; no comm ;;;;;;;;;;;;;;;;;;
;; (superoptimize (encode "2 b! @b 3 b! !b 1 b! @b 2 b! !b")
;;                (encode "_ _ _ _ _ _ _ _")
;;                (cons 4 0)
;;                (constraint memory s t))
;; (superoptimize (encode "0 a! !+ !+ !+ !+ 3 b! @b 1 b! @b")
;;                (encode "_ _ _ _ _ _ _ _ _ _")
;;                (cons 4 0)
;;                (constraint [data 1] memory s t))

;;;;;;;;;;;;;;;; communication ;;;;;;;;;;;;;;;;;;;
;; (superoptimize (encode "325 b! !b 277 b! !b 373 b! !b 469 b! !b")
;;                (encode "_ _ _ _ _ _ _ _ _ _ _ _")
;;                (cons 0 0)
;;                (constraint memory s t))
;; (superoptimize (encode "2 b! @b 277 b! !b 1 b! @b 277 b! !b")
;;                (encode "_ _ _ _ _ _ _ _")
;;                (cons 3 0)
;;                (constraint memory s t))
;; (superoptimize (encode "4 a! !+ 4 b! @b 373 b! @b +")
;;                (encode "_ _ _ _ _ _ _ _")
;;                (cons 5 1)
;;                (constraint memory s t))
;; (superoptimize (encode "5 b! !b 373 b! @b 5 b! @b 277 b! !b")
;;                (encode "_ _ _ _ _ _ _ _ _ _")
;;                (cons 6 1)
;;                (constraint memory s t))
(pretty-display `(time ,(- (current-seconds) t)))
#lang racket

(require "arm/arm-machine.rkt" "ast.rkt" "arm/arm-ast.rkt")
(provide forwardbackward%)

(struct concat (collection inst))
(struct box (val))

(define forwardbackward%
  (class object%
    (super-new)
    (init-field machine enum simulator simulator-precise
                printer parser
                validator validator-precise
		inverse)
    (abstract vector->id mask-in
              reduce-precision increase-precision)
    (public synthesize-window)
    
    (define debug #f)

    (define c-behaviors 0)
    (define c-progs 0)
    (define (class-insert! class live states-vec prog)
      (set! c-progs (add1 c-progs))

      (define (insert-inner x states-vec prog)
        (define key (car states-vec))
        (if (= (length states-vec) 1)
	    (if (hash-has-key? x key)
		(hash-set! x key (cons prog (hash-ref x key)))
		(begin
		  (set! c-behaviors (add1 c-behaviors))
		  (hash-set! x key (list prog))))
	    (let ([has-key (hash-has-key? x key)])
	      (unless has-key (hash-set! x key (make-hash)))
	      (insert-inner (hash-ref x key) (cdr states-vec) prog))))

      ;(set! states-vec (map (lambda (x) (abstract x live-list identity)) states-vec))
      (define key (sort live <))
      (unless (hash-has-key? class key) (hash-set! class key (make-hash)))
      (insert-inner (hash-ref class key) states-vec prog))

    (define c-behaviors-bw 0)
    (define c-progs-bw 0)
    (define (class-insert-bw! class live states-vec prog)
      ;;(pretty-display `(class-insert-bw! ,(map length states-vec)))
      (set! c-progs-bw (add1 c-progs-bw))

      (define (insert-inner x states-vec prog)
        (define key-list (car states-vec))
        (if (= (length states-vec) 1)
	    (for ([key key-list])
		 (if (hash-has-key? x key)
		     (hash-set! x key (cons prog (hash-ref x key)))
		     (begin
		       (set! c-behaviors-bw (add1 c-behaviors-bw))
		       (hash-set! x key (list prog)))))
	    (for ([key key-list])
		 (let ([has-key (hash-has-key? x key)])
		   (unless has-key (hash-set! x key (make-hash)))
		   (insert-inner (hash-ref x key) (cdr states-vec) prog)))))

      ;(set! states-vec (map (lambda (x) (abstract x live-list identity)) states-vec))
      (define key (sort live <))
      (unless (hash-has-key? class key) (hash-set! class key (make-hash)))
      (insert-inner (hash-ref class key) states-vec prog))

    (define (count-collection x)
      (cond
       [(concat? x) (count-collection (concat-collection x))]
       [(vector? x) 1]
       [(list? x) (foldl + 0 (map count-collection x))]
       [else (raise (format "count-collection: unimplemented for ~a" x))]))

    (define (collect-behaviors x)
      (cond
       [(list? x)  x]
       [(hash? x)
        (let ([ans (list)])
          (for ([val (hash-values x)])
               (set! ans (append (collect-behaviors val) ans)))
          ans)]
       [(box? x) (collect-behaviors (box-val x))]
       [else
        (raise (format "collect-behaviors: unimplemented for ~a" x))]
       ))
    
    (define (get-collection-iterator collection)
      (define ans (list))
      (define (loop x postfix)
        (cond
         [(concat? x)
          (loop (concat-collection x) (vector-append (vector (concat-inst x)) postfix))]
         [(vector? x) 
          (set! ans (cons (vector-append x postfix) ans))]
         [(list? x) 
          (if (empty? x)
              (set! ans (cons postfix ans))
              (for ([i x]) (loop i postfix)))]
         [(set? x) 
          (if (set-empty? x)
              (set! ans (cons postfix ans))
              (for ([i x]) (loop i postfix)))]

         ))
      (loop collection (vector))
      ans)
    
    (define t-load 0)
    (define t-build 0)
    (define t-build-inter 0)
    (define t-build-hash 0)
    (define t-build-hash2 0)
    (define t-intersect 0)
    (define t-interpret 0)
    (define t-extra 0)
    (define t-verify 0)
    (define c-build-hash 0)
    (define c-build-hash2 0)
    (define c-intersect 0)
    (define c-interpret 0)
    (define c-extra 0)
    (define c-check 0)

    (define t-collect 0)
    (define t-check 0)

    (define (synthesize-window spec sketch prefix postfix constraint extra 
			       [cost #f] [time-limit 3600]
			       #:hard-prefix [hard-prefix (vector)] 
			       #:hard-postfix [hard-postfix (vector)]
			       #:assume-interpret [assume-interpret #t]
			       #:assume [assumption (send machine no-assumption)])

      (define start-time (current-seconds))
      (define spec-precise spec)
      (define prefix-precise prefix)
      (define postfix-precise postfix)
      (set! spec (reduce-precision spec))
      (set! prefix (reduce-precision prefix))
      (set! postfix (reduce-precision postfix))

      (send machine analyze-opcode prefix spec postfix)
      (send machine analyze-args prefix spec postfix #:vreg 0)
      (define live2 (send validator get-live-in postfix constraint extra))
      (define live2-vec (send machine progstate->vector live2))
      (define live1 (send validator get-live-in spec live2 extra))
      (define live1-list (send machine get-operand-live live1))
      (define live2-list (send machine get-operand-live live2))
             
      (define ntests 2)
      ;; (define inits
      ;;   (send validator generate-input-states ntests (vector-append prefix spec postfix)
      ;;         assumption extra #:db #t))
      ;; p19
      (define inits
        (list
         (progstate (vector -6 -5 3 5) (vector) -1 4)
         (progstate (vector 6 3 4 5) (vector) -1 4)
         ))
      (define states1 
	(map (lambda (x) (send simulator interpret prefix x #:dep #f)) inits))
      (define states2
	(map (lambda (x) (send simulator interpret spec x #:dep #f)) states1))
      (define states1-vec 
	(map (lambda (x) (send machine progstate->vector x)) states1))
      (define states2-vec 
	(map (lambda (x) (send machine progstate->vector x)) states2))
      (define states2-vec-list (map list states2-vec))

      (pretty-display `(states1-vec ,states1-vec))
      (pretty-display `(states2-vec ,states2-vec))
      (pretty-display `(live2-vec ,live2-vec))
      
      (define ce-limit 10000)
      (define ce-in (make-vector ce-limit))
      (define ce-out-vec (make-vector ce-limit))
      (define ce-count ntests)
      (define ce-count-extra ntests)

      (define ce-in-final (list))
      (define ce-out-vec-final (list))


      (define prev-classes (make-hash))
      (class-insert! prev-classes live1-list states1-vec (vector))
      (define classes (make-hash))

      (define prev-classes-bw (make-hash))
      (class-insert-bw! prev-classes-bw live2-list states2-vec-list (vector))
      (define classes-bw (make-hash))
      
      (define (gen-inverse-behaviors iterator)
        (define p (iterator))
        (define my-inst (car p))
        (when my-inst
          ;(send printer print-syntax (send printer decode my-inst))
          (send inverse gen-inverse-behavior my-inst)
          (gen-inverse-behaviors iterator)
          ))
      
      (gen-inverse-behaviors (send enum reset-generate-inst #f #f #f #f `all #f #:no-args #t))

      (define (check-final p)
        (pretty-display (format "[5] check-final ~a" (length ce-in-final)))
        (send printer print-syntax (send printer decode p))
        (define
          pass
          (for/and ([input ce-in-final]
                    [output-vec ce-out-vec-final])
                   (let ([my-output-vec
                          (send machine progstate->vector
                                (send simulator-precise interpret p input #:dep #f))])
                     (send machine state-eq? output-vec my-output-vec live2-vec))))

        (when
         pass
         (define ce (send validator-precise counterexample 
                          (vector-append prefix-precise spec-precise postfix-precise)
                          (vector-append prefix-precise p postfix-precise)
                          constraint extra #:assume assumption))

         (if ce
             (let* ([ce-input
                     (send simulator-precise interpret prefix-precise ce #:dep #f)]
                    [ce-output
                     (send simulator-precise interpret spec-precise ce-input #:dep #f)]
                    [ce-output-vec
                     (send machine progstate->vector ce-output)])
               (when debug
                     (pretty-display "[6] counterexample (precise)")
                     (send machine display-state ce-input)
                     (pretty-display `(ce-out-vec ,ce-output-vec)))
               (set! ce-in-final (cons ce-input ce-in-final))
               (set! ce-out-vec-final (cons ce-output-vec ce-out-vec-final))
               )
             (begin
               (pretty-display "[7] FOUND!!!")
               (send printer print-syntax (send printer decode p))
               (pretty-display `(ce-count ,ce-count-extra))
               (pretty-display `(ce-count-precise ,(length ce-in-final)))
	       (pretty-display `(time ,(- (current-seconds) start-time)))
               (raise p))))
        )
      
      (define (check-eqv progs progs-bw my-inst my-ce-count)
        (set! c-check (add1 c-check))
        (define t00 (current-milliseconds))
        
          
        (define (inner-progs p)
          
          ;; (pretty-display "After renaming")
          ;; (send printer print-syntax (send printer decode p))
          (when debug
                (pretty-display "[2] all correct")
                (pretty-display `(ce-count-extra ,ce-count-extra))
                )
          (when (= ce-count-extra ce-limit)
                (raise "Too many counterexamples")
                )
          
          (define ce (send validator counterexample 
                           (vector-append prefix spec postfix)
                           (vector-append prefix p postfix)
                           constraint extra #:assume assumption))

          (if ce
              (let* ([ce-input (send simulator interpret prefix ce #:dep #f)]
                     [ce-input-vec
                      (send machine progstate->vector ce-input)]
                     [ce-output
                      (send simulator interpret spec ce-input #:dep #f)]
                     [ce-output-vec
                      (send machine progstate->vector ce-output)])
                (when debug
                      (pretty-display "[3] counterexample")
                      ;;(send machine display-state ce-input)
                      (pretty-display `(ce ,ce-count-extra ,ce-input-vec ,ce-output-vec)))
                (vector-set! ce-in ce-count-extra ce-input)
                (vector-set! ce-out-vec ce-count-extra ce-output-vec)
                (set! ce-count-extra (add1 ce-count-extra))
                )
              (begin
                (pretty-display "[4] found")
                (send printer print-syntax (send printer decode p))
                (check-final (increase-precision p))
                )))

        (define (inner-behaviors p)
          (define t0 (current-milliseconds))
          
          
          (define
            pass
            (for/and ([i (reverse (range my-ce-count ce-count-extra))])
                     (let* ([input (vector-ref ce-in i)]
                            [output-vec (vector-ref ce-out-vec i)]
                            [my-output (send simulator interpret p input #:dep #f)]
                            [my-output-vec (and my-output (send machine progstate->vector my-output))])
                       (and my-output
                            (send machine state-eq? output-vec my-output-vec live2-vec)))))
          
          (define t1 (current-milliseconds))
          (set! t-extra (+ t-extra (- t1 t0)))
          ;;(set! c-extra (+ c-extra (- ce-count-extra my-ce-count)))
          (set! c-extra (add1 c-extra))
          (when pass
                (inner-progs p)
                (define t2 (current-milliseconds))
                (set! t-verify (+ t-verify (- t2 t1))))

          )

        (define h1
          (if (= my-ce-count ntests)
              (get-collection-iterator progs)
              progs))

        (define h2
          (if (= my-ce-count ntests)
              (get-collection-iterator progs-bw)
              progs-bw))

        
        ;; (let ([x my-inst])
        ;;   (when (and (equal? `eor
        ;;                      (vector-ref (get-field inst-id machine) (inst-op x)))
        ;;              (equal? `nop 
        ;;                      (vector-ref (get-field shf-inst-id machine) 
        ;;                                  (inst-shfop x)))
        ;;              (equal? 0 (vector-ref (inst-args x) 0))
        ;;              (equal? 0 (vector-ref (inst-args x) 1))
        ;;              (equal? 1 (vector-ref (inst-args x) 2))
        ;;              )
        ;;         (newline)
        ;;         (pretty-display (format "CHECK-EQV ~a ~a" (length h1) (length h2)))))
        
        (define t11 (current-milliseconds))
        
        (for* ([p1 h1]
               [p2 h2])
              (inner-behaviors (vector-append p1 (vector my-inst) p2)))
        (define t22 (current-milliseconds))
        (set! t-collect (+ t-collect (- t11 t00)))
        (set! t-check (+ t-check (- t22 t11)))
        )

      (define (refine my-classes my-classes-bw my-inst my-live1 my-live2)
        
        (define (outer my-classes my-classes-bw level)
          ;;(pretty-display `(outer ,beh-id ,level ,my-classes ,my-classes-bw))
          (define real-hash my-classes)
          (define real-hash-bw my-classes-bw)
                                            
          (when (and (list? real-hash)
                     (or (> (count-collection real-hash) 8)
                         (hash? real-hash-bw)
                         (and (list? real-hash-bw)
                              (> (count-collection real-hash-bw) 8))))
                ;; list of programs
                (define t0 (current-milliseconds))
                (set! real-hash (make-hash))
                (define input (vector-ref ce-in level)) ;;TODO
                
                (define (loop iterator)
                  (define prog (and (not (empty? iterator)) (car iterator)))
                  (when 
                   prog
                   (let* ([s0 (current-milliseconds)]
                          [state (send simulator interpret prog input #:dep #f)]
                          [state-vec (and state (send machine progstate->vector state))]
                          [s1 (current-milliseconds)])
                     (if (hash-has-key? real-hash state-vec)
                         (hash-set! real-hash state-vec
                                    (cons prog (hash-ref real-hash state-vec)))
                         (hash-set! real-hash state-vec (list prog)))
                     (let ([s2 (current-milliseconds)])
                       (set! t-build-inter (+ t-build-inter (- s1 s0)))
                       (set! t-build-hash (+ t-build-hash (- s2 s1)))
                       (set! c-build-hash (add1 c-build-hash))
                       )
                     )
                   (loop (cdr iterator))
                   ))

                (if (= level ntests)
                    (loop (get-collection-iterator my-classes))
                    (loop my-classes))
                (define t1 (current-milliseconds))
                (set! t-build (+ t-build (- t1 t0)))
                )
          
          (when (and (list? real-hash-bw)
                     (hash? real-hash))
                     ;;(> (count-collection real-hash-bw) 8))
                ;; list of programs
                (define t0 (current-milliseconds))
                (set! real-hash-bw (make-hash))
                (define output-vec (vector-ref ce-out-vec level))
                
                (define (loop-bw iterator)
                  (define prog (and (not (empty? iterator)) (car iterator)))
                  (when 
                   prog
                    (let ([s0 (current-milliseconds)]
                          [states-vec (send inverse interpret-inst (vector-ref prog 0) output-vec live2-list)] ;; only work with 1 instruction
                          [s1 (current-milliseconds)])
                                             
                      (when
                          states-vec
                        (for ([state-vec states-vec])
                          (if (hash-has-key? real-hash-bw state-vec)
                              (hash-set! real-hash-bw state-vec
                                         (cons prog (hash-ref real-hash-bw state-vec)))
                              (hash-set! real-hash-bw state-vec (list prog)))))        
                      (let ([s2 (current-milliseconds)])
                        (set! t-build-inter (+ t-build-inter (- s1 s0)))
                        (set! t-build-hash2 (+ t-build-hash2 (- s2 s1)))
                        (set! c-build-hash2 (add1 c-build-hash2))
                        )
                      )
                    (loop-bw (cdr iterator))))
                
                (if (= level ntests)
                    (loop-bw (get-collection-iterator my-classes-bw))
                    (loop-bw my-classes-bw))
                (define t1 (current-milliseconds))
                (set! t-build (+ t-build (- t1 t0)))
                )
          
          (define (inner)
            (define t0 (current-milliseconds))
            (define inters-fw (hash-keys real-hash))
            (define t1 (current-milliseconds))
            (set! t-intersect (+ t-intersect (- t1 t0)))
            (set! c-intersect (add1 c-intersect))

            (for ([inter inters-fw])
              (let* ([t0 (current-milliseconds)]
                     [out (send simulator interpret (vector my-inst) (send machine vector->progstate inter) #:dep #f)]
                     [out-vec (and out (mask-in (send machine progstate->vector out) my-live2))]
                     [condition (and out (hash-has-key? real-hash-bw out-vec))]
                     [t1 (current-milliseconds)]
                     )
                ;; (let ([x my-inst])
                ;;   (when (and (equal? `eor
                ;;                      (vector-ref (get-field inst-id machine) (inst-op x)))
                ;;              (equal? `nop 
                ;;                      (vector-ref (get-field shf-inst-id machine) 
                ;;                                  (inst-shfop x)))
                ;;              (equal? 0 (vector-ref (inst-args x) 0))
                ;;              (equal? 0 (vector-ref (inst-args x) 1))
                ;;              (equal? 1 (vector-ref (inst-args x) 2))
                ;;              )
                ;;         (pretty-display `(inner ,level ,inter ,out-vec ,condition))))
                       
                (set! t-interpret (+ t-interpret (- t1 t0)))
                (set! c-interpret (add1 c-interpret))
                (when
                 condition
                 (if (= 1 (- ce-count level))
                     (begin
                       (check-eqv (hash-ref real-hash inter)
                                  (hash-ref real-hash-bw out-vec)
                                  my-inst ce-count)
                       (set! ce-count ce-count-extra))
                     (let-values ([(a b)
                                   (outer (hash-ref real-hash inter)
                                          (hash-ref real-hash-bw out-vec)
                                          (add1 level))])
                       (hash-set! real-hash inter a)
                       (hash-set! real-hash-bw out-vec b))))))
            )
            
          (cond
           [(and (hash? real-hash) (hash? real-hash-bw))
            (inner)
            (values real-hash real-hash-bw)]

           [else
            (check-eqv (collect-behaviors real-hash)
                       (collect-behaviors real-hash-bw)
                       my-inst level)
            ;; (values (cond
            ;;          [(hash? real-hash) real-hash]
            ;;          [(box? real-hash) real-hash]
            ;;          [else (box real-hash)])
            ;;         (cond
            ;;          [(hash? real-hash-bw) real-hash-bw]
            ;;          [(box? real-hash-bw) real-hash-bw]
            ;;          [else (box real-hash-bw)]))
            (values real-hash real-hash-bw)
            ]))
       
        (outer my-classes my-classes-bw 0)
        )


      (define (build-hash old-liveout my-hash iterator) 
        ;; Call instruction generator
        (define inst-liveout-vreg (iterator))
        (define my-inst (first inst-liveout-vreg))
	(define my-liveout (second inst-liveout-vreg))

        (define cache (make-hash))
        (when 
         my-inst
         ;;(send printer print-syntax-inst (send printer decode-inst my-inst))

         (define (recurse x states2-vec)
           (if (list? x)
               (class-insert! classes my-liveout (reverse states2-vec) (concat x my-inst))
               (for ([pair (hash->list x)])
                    (let* ([state-vec (car pair)]
                           [state (send machine vector->progstate state-vec)]
                           [val (cdr pair)]
                           [out 
                            (if (and (list? val) (hash-has-key? cache state-vec))
                                (hash-ref cache state-vec)
                                (let ([tmp
                                       (with-handlers*
                                        ([exn? (lambda (e) #f)])
                                        (send machine progstate->vector 
                                              (send simulator interpret 
                                                    (vector my-inst)
                                                    state
                                                    #:dep #f)))])
                                  (when (list? val) (hash-set! cache state-vec tmp))
                                  tmp))
                            ])
                      (when out (recurse val (cons out states2-vec)))))))
         
         (recurse my-hash (list))
         (build-hash old-liveout my-hash iterator)))

      (define (build-hash-bw old-liveout my-hash iterator)
        (define inst-liveout-vreg (iterator))
	(define my-inst (first inst-liveout-vreg))
	(define my-liveout (third inst-liveout-vreg))

	(when my-inst
          ;;(send printer print-syntax-inst (send printer decode-inst my-inst))
          ;;(pretty-display `(live ,my-liveout))
          (define (recurse x states-vec-accum)
            (if (list? x)
                (begin
                  (class-insert-bw! classes-bw my-liveout (reverse states-vec-accum) 
                                    (concat x my-inst))
                  )
                (for ([pair (hash->list x)])
                  (let* ([state-vec (car pair)]
                         [val (cdr pair)]
                         [out (send inverse interpret-inst my-inst state-vec old-liveout)])
                    (when (and out (not (empty? out)))
                      (recurse val (cons out states-vec-accum)))))))
          
          (recurse my-hash (list))
          (build-hash-bw old-liveout my-hash iterator)
          )
	)

      ;; Grow forward
      (for ([i 2])
        (newline)
        (pretty-display `(grow ,i))
        (set! c-behaviors 0)
        (set! c-progs 0)
      	(for ([pair (hash->list prev-classes)])
      	     (let* ([live-list (car pair)]
      		    [my-hash (cdr pair)]
      		    [iterator (send enum reset-generate-inst #f live-list #f #f `all #f)])
               (pretty-display `(live ,live-list))
      	       (build-hash live-list my-hash iterator)))
        (set! prev-classes classes)
        (set! classes (make-hash))
        (pretty-display `(behavior ,i ,c-behaviors ,c-progs ,(- (current-seconds) start-time)))
        )

      ;; Grow backward
      (for ([i 1])
           (newline)
           (pretty-display `(grow-bw ,i))
           (set! c-behaviors-bw 0)
           (set! c-progs-bw 0)
	   (for ([pair (hash->list prev-classes-bw)])
		(let* ([live-list (car pair)]
                       [my-hash (cdr pair)]
                       [iterator (send enum reset-generate-inst #f #f live-list #f `all #f)])
                  (newline)
                  (pretty-display `(live ,live-list))
		  (build-hash-bw live-list my-hash iterator)))
           (set! prev-classes-bw classes-bw)
           (set! classes-bw (make-hash))
           (pretty-display `(behavior-bw ,i ,c-behaviors-bw ,c-progs-bw ,(- (current-seconds) start-time)))
        )

      (define (refine-all hash1 live1 hash2 live2 iterator)
	(define inst-liveout-vreg (iterator))
        (define my-inst (first inst-liveout-vreg))

        (when 
            my-inst
          (send printer print-syntax-inst (send printer decode-inst my-inst))
          (define ttt (current-milliseconds))
          (refine hash1 hash2 my-inst live1 live2)
          (pretty-display (format "search ~a = ~a\t(~a + ~a/~a + ~a/~a)\t~a/~a\t~a/~a\t~a/~a (~a) ~a" 
                                  (- (current-milliseconds) ttt)
                                  t-build t-build-inter t-build-hash c-build-hash t-build-hash2 c-build-hash2
                                  t-intersect c-intersect
                                  t-interpret c-interpret
                                  t-extra c-extra c-check
                                  t-verify
                                  ))
          (set! t-build 0) (set! t-build-inter 0) (set! t-build-hash 0) (set! t-build-hash2 0) (set! t-intersect 0) (set! t-interpret 0) (set! t-extra 0) (set! t-verify 0)
          (set! c-build-hash 0) (set! c-build-hash2 0) (set! c-intersect 0) (set! c-interpret 0) (set! c-extra 0) (set! c-check 0)
          (set! t-collect 0) (set! t-check 0)
          (refine-all hash1 live1 hash2 live2 iterator)))

      ;; Search
      (define ttt (current-milliseconds))
      (for* ([pair1 (hash->list prev-classes)]
             [pair2 (hash->list prev-classes-bw)])
           (let* ([live1 (car pair1)]
                  [my-hash1 (cdr pair1)]
                  [live2 (car pair2)]
                  [my-hash2 (cdr pair2)]
                  [iterator
                   (send enum reset-generate-inst #f live1 live2 #f `all #f)])
             (newline)
             (pretty-display `(refine ,live1 ,live2))
             (refine-all my-hash1 live1 my-hash2 live2 iterator)
             ))
      )
    ))
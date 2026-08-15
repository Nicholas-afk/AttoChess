(set-option :produce-proofs true)
(set-logic QF_AUFBV)
(define-sort Byte () (_ BitVec 8))
(define-sort Word () (_ BitVec 16))
(define-sort Table () (Array Byte Byte))
(define-fun old-eval () Table
  (store (store (store (store (store (store (store (store
    ((as const Table) #x00)
    #x00 #x00) #x01 #x00) #x02 #x03) #x03 #x03)
    #x04 #x01) #x05 #x09) #x06 #x05) #x07 #x2e))
; The candidate has seven explicit bytes; index 7 aliases init_db[0]=2Eh.
(define-fun candidate-eval () Table
  (store (store (store (store (store (store (store (store
    ((as const Table) #x00)
    #x00 #x00) #x01 #x00) #x02 #x03) #x03 #x03)
    #x04 #x01) #x05 #x09) #x06 #x05) #x07 #x2e))
(define-fun blocked ((cell Byte) (mask Byte)) Bool
  (distinct (bvand cell mask) #x00))
(define-fun in-display ((off Word)) Bool
  (and (bvuge off #x0018) (bvule off #x0079)))
(define-fun in-source-scan ((off Word)) Bool
  (and (bvuge off #x001c) (bvult off #x0078)))
(define-fun read-by-self-feed ((off Word)) Bool (bvule off #x0002))

(declare-const captured-type Byte)
(declare-const color-mask Byte)
(declare-const changed-offset Word)
(assert (or (= color-mask #x18) (= color-mask #x28)))
; First row's four CR/LF bytes are unchanged; only its eight interior cells use
; the overlapped fill byte.
(assert (and (bvuge changed-offset #x0004) (bvule changed-offset #x000b)))

(define-fun eval-index () Byte (bvand captured-type #x07))
(define-fun original-xlat () Byte (select old-eval eval-index))
(define-fun candidate-xlat () Byte (select candidate-eval eval-index))
(define-fun original-border-blocks () Bool (blocked #x09 color-mask))
(define-fun candidate-border-blocks () Bool (blocked #x2e color-mask))
(define-fun original-is-literal-fill () Bool (= (bvand #x09 #x80) #x00))
(define-fun candidate-is-literal-fill () Bool (= (bvand #x2e #x80) #x00))
; Concrete runtime identity behind the overlap: eval_db=01F1h, init_db=01F8h.
(define-fun overlap-address-correct () Bool
  (= (bvadd #x01f1 #x0007) #x01f8))

; Negation of table, border-class, and hidden-offset equivalence.
(assert (or
  (distinct original-xlat candidate-xlat)
  (distinct original-border-blocks candidate-border-blocks)
  (not original-border-blocks)
  (not candidate-border-blocks)
  (distinct original-is-literal-fill candidate-is-literal-fill)
  (not original-is-literal-fill)
  (not candidate-is-literal-fill)
  (not overlap-address-correct)
  (in-display changed-offset)
  (in-source-scan changed-offset)
  (read-by-self-feed changed-offset)))
(check-sat)
(get-proof)

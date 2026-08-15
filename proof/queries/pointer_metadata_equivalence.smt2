(set-option :produce-proofs true)
(set-logic QF_AUFBV)
(define-sort Byte () (_ BitVec 8))
(define-sort Word () (_ BitVec 16))
(define-sort Mem () (Array Word Byte))
(define-fun parity-even ((x Byte)) Bool
  (= (bvxor ((_ extract 0 0) x)
     (bvxor ((_ extract 1 1) x)
     (bvxor ((_ extract 2 2) x)
     (bvxor ((_ extract 3 3) x)
     (bvxor ((_ extract 4 4) x)
     (bvxor ((_ extract 5 5) x)
     (bvxor ((_ extract 6 6) x) ((_ extract 7 7) x)))))))) #b0))
(define-fun old-relative ((t Byte)) Byte
  (ite (= t #x02) #x05
  (ite (= t #x03) #x0a
  (ite (= t #x04) #x08
  (ite (= t #x05) #x0b
  (ite (= t #x06) #x0c #x09))))))
(define-fun new-absolute-low ((t Byte)) Byte
  (ite (= t #x02) #xe4
  (ite (= t #x03) #xea
  (ite (= t #x04) #xe9
  (ite (= t #x05) #xed
  (ite (= t #x06) #xef #xed))))))
(define-fun expected-vector ((t Byte)) Word
  (ite (= t #x02) #x01e4
  (ite (= t #x03) #x01ea
  (ite (= t #x04) #x01e9
  (ite (= t #x05) #x01ed
  (ite (= t #x06) #x01ef #x01ed))))))
(define-fun sign-extend-byte ((x Byte)) Word
  (concat (ite (= ((_ extract 7 7) x) #b1) #xff #x00) x))
(define-fun reachable-cell ((x Byte)) Bool
  (or (= x #x00) (= x #x09) (= x #x2e) (= x #x0d) (= x #x0a)
      (= x #xa2) (= x #xa3) (= x #xa5) (= x #xa6) (= x #xa7)
      (= x #x24) (= x #x14)
      (= x #x92) (= x #x93) (= x #x95) (= x #x96) (= x #x97)))

(declare-const vector-memory Mem)
(declare-const source-cell Byte)
(declare-const moving-cell Byte)
(declare-const captured-cell Byte)
(declare-const side-mask Byte)
(declare-const di0 Word)
(assert (reachable-cell source-cell))
(assert (reachable-cell moving-cell))
(assert (reachable-cell captured-cell))
(assert (or (= side-mask #x18) (= side-mask #x28)))
; Exact MOV BL,[BP] / TEST BL,DL / AND BL,07h / JZ reachability.
(assert (= (bvand source-cell side-mask) #x00))
(assert (distinct (bvand source-cell #x07) #x00))
(define-fun piece-type () Byte (bvand source-cell #x07))
(define-fun type-index () Word
  ((_ zero_extend 8) (bvsub piece-type #x02)))
; Make/undo only stores zero or an existing cell, so the initialized alphabet
; is inductive under every speculative board transition.
(define-fun moved-source-cell () Byte #x00)
(define-fun moved-destination-cell () Byte moving-cell)
(define-fun undone-destination-cell () Byte captured-cell)

; Counterfactual old relative table, adjacent to the final vector block.  This
; isolates the pointer-algorithm rewrite from the independent one-byte layout
; shift.  The actual 273-byte address is checked below after rebasing by -1.
(define-fun old-final-metadata-address () Word
  (bvadd #x01de type-index))
(define-fun old-final-si-after-lodsb () Word
  (bvadd old-final-metadata-address #x0001))
(define-fun old-relative-ax () Word
  (sign-extend-byte (old-relative piece-type)))
(define-fun old-final-vector-si () Word
  (bvadd old-final-si-after-lodsb old-relative-ax))

; Exact preceding 273-byte layout: moves_db=01DFh and vectors begin at 01E5h.
(define-fun old-273-metadata-address () Word
  (bvadd #x01df type-index))
(define-fun old-273-vector-si () Word
  (bvadd (bvadd old-273-metadata-address #x0001) old-relative-ax))
(define-fun old-273-vector-si-rebased () Word
  (bvsub old-273-vector-si #x0001))

; New path: MOV BX,eval_db establishes BH=01h; MOV BL,[BP] / AND BL,07h
; changes only BL. LEA BX+53h addresses metadata 0155h..015Ah.
(define-fun old-zf-after-type-mask () Bool (= piece-type #x00))
(define-fun new-zf-after-type-mask () Bool (= piece-type #x00))
(define-fun new-bx-after-type-mask () Word (concat #x01 piece-type))
(define-fun new-metadata-address () Word
  (bvadd new-bx-after-type-mask #x0053))
(define-fun new-si-after-lodsb () Word
  (bvadd new-metadata-address #x0001))
(define-fun new-ax-pointer () Word
  (concat #x01 (new-absolute-low piece-type)))
(define-fun new-vector-si () Word new-ax-pointer)

; Old AX holds the relative scalar; after XCHG the new temporary AX holds the
; post-LODSB metadata address. The following vector LODSB replaces AL and CBW
; replaces AH before ADD DI,AX or any branch can observe either temporary AX.
(define-fun old-vector-byte () Byte (select vector-memory old-final-vector-si))
(define-fun new-vector-byte () Byte (select vector-memory new-vector-si))
(define-fun old-ax-after-cbw () Word (sign-extend-byte old-vector-byte))
(define-fun new-ax-after-cbw () Word (sign-extend-byte new-vector-byte))
(define-fun old-di-after-add () Word (bvadd di0 old-ax-after-cbw))
(define-fun new-di-after-add () Word (bvadd di0 new-ax-after-cbw))
(define-fun old-zf-after-add () Bool (= old-di-after-add #x0000))
(define-fun new-zf-after-add () Bool (= new-di-after-add #x0000))
(define-fun old-sf-after-add () Bool
  (= ((_ extract 15 15) old-di-after-add) #b1))
(define-fun new-sf-after-add () Bool
  (= ((_ extract 15 15) new-di-after-add) #b1))
(define-fun old-pf-after-add () Bool
  (parity-even ((_ extract 7 0) old-di-after-add)))
(define-fun new-pf-after-add () Bool
  (parity-even ((_ extract 7 0) new-di-after-add)))

; Negation of pointer, branch, kill, and first-live-use equivalence.
(assert (or
  (not (bvuge piece-type #x02))
  (not (bvule piece-type #x07))
  (not (reachable-cell moved-source-cell))
  (not (reachable-cell moved-destination-cell))
  (not (reachable-cell undone-destination-cell))
  (distinct old-zf-after-type-mask new-zf-after-type-mask)
  (distinct old-final-vector-si (expected-vector piece-type))
  (distinct old-273-vector-si-rebased (expected-vector piece-type))
  (distinct new-vector-si (expected-vector piece-type))
  (distinct old-final-vector-si new-vector-si)
  (distinct new-metadata-address
            (bvadd #x0155 type-index))
  (distinct old-vector-byte new-vector-byte)
  (distinct old-ax-after-cbw new-ax-after-cbw)
  (distinct old-di-after-add new-di-after-add)
  (distinct old-zf-after-add new-zf-after-add)
  (distinct old-sf-after-add new-sf-after-add)
  (distinct old-pf-after-add new-pf-after-add)))
(check-sat)
(get-proof)

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

(declare-const mem0 Mem)
(declare-const src Word)
(declare-const dst Word)
(declare-const al Byte)
(declare-const bl Byte)
(declare-const dl Byte)
(assert (distinct src dst))

(define-fun moving () Byte (select mem0 src))
(define-fun captured () Byte (select mem0 dst))
; Contract of the recursive call: the candidate move remains made, while all
; recursively explored reply moves have been undone before return.
(define-fun moved () Mem (store (store mem0 src #x00) dst moving))

; Original POPA restores saved BH=captured; XCHG then yields BH=moving.
(define-fun original-after-xchg () Mem (store moved dst captured))
(define-fun original-bh-after-xchg () Byte (select moved dst))
(define-fun original-undone () Mem
  (store original-after-xchg src original-bh-after-xchg))
; Optimized POPA restores saved AH=captured; the same dataflow uses AH.
(define-fun candidate-after-xchg () Mem (store moved dst captured))
(define-fun candidate-ah-after-xchg () Byte (select moved dst))
(define-fun candidate-undone () Mem
  (store candidate-after-xchg src candidate-ah-after-xchg))

; These are the only immediate continuation decisions: captured color controls
; JNZ, piece-type parity controls the slider continuation, and NEG AL controls
; vector sign/termination.  Their inputs are live and identical.
(define-fun original-captured-color () Bool
  (distinct (bvand (select original-undone dst) dl) #x00))
(define-fun candidate-captured-color () Bool
  (distinct (bvand (select candidate-undone dst) dl) #x00))
(define-fun original-slider () Bool (parity-even bl))
(define-fun candidate-slider () Bool (parity-even bl))
(define-fun original-next-vector () Byte (bvneg al))
(define-fun candidate-next-vector () Byte (bvneg al))

; Negation of exact board undo plus the live continuation projection.
(assert (or
  (distinct original-undone mem0)
  (distinct candidate-undone mem0)
  (distinct original-undone candidate-undone)
  (distinct original-captured-color candidate-captured-color)
  (distinct original-slider candidate-slider)
  (distinct original-next-vector candidate-next-vector)))
(check-sat)
(get-proof)

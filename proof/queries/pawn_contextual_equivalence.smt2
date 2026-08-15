(set-option :produce-proofs true)
(set-logic QF_AUFBV)
(define-sort Byte () (_ BitVec 8))
(define-sort Word () (_ BitVec 16))
(define-sort Mem () (Array Word Byte))
(define-fun bool-bit ((b Bool)) (_ BitVec 1) (ite b #b1 #b0))
(define-fun parity-even ((x Byte)) Bool
  (= (bvxor ((_ extract 0 0) x)
     (bvxor ((_ extract 1 1) x)
     (bvxor ((_ extract 2 2) x)
     (bvxor ((_ extract 3 3) x)
     (bvxor ((_ extract 4 4) x)
     (bvxor ((_ extract 5 5) x)
     (bvxor ((_ extract 6 6) x) ((_ extract 7 7) x)))))))) #b0))
(define-fun rcl-byte-1 ((x Byte) (cf Bool)) Byte
  (concat ((_ extract 6 0) x) (bool-bit cf)))

(declare-const board0 Mem)
(declare-const stack0 Mem)
(declare-const src Word)
(declare-const dst Word)
(declare-const al Byte)
(declare-const bl Byte)
(declare-const cx Word)
(declare-const dx Word)
(declare-const bp Word)
(declare-const si Word)
(declare-const di Word)
(declare-const sp Word)
(declare-const recursive-score Byte)
(declare-const incumbent Byte)
(declare-const score-slot Word)
(declare-const dst-slot Word)
(declare-const src-slot Word)
(define-fun dl () Byte ((_ extract 7 0) dx))
(define-fun dh () Byte ((_ extract 15 8) dx))
(define-fun captured () Byte (select board0 dst))
(define-fun moving () Byte (select board0 src))

(assert (distinct src dst))
(assert (or (= dx #x2818) (= dx #x1828)))
; Exact reachability conditions for this pawn-predicate cut point.
(assert (= (bvand captured dh) #x00))
(define-fun is-pawn () Bool (= bl #x04))
(assert (=> is-pawn (distinct (bvand (bvxor al dh) #x20) #x00)))

(define-fun diagonal () Bool (distinct (bvand al #x01) #x00))
(define-fun original-ah-for-test () Byte
  (ite diagonal captured (bvxor captured #x30)))
(define-fun original-pawn-accept () Bool
  (distinct (bvand original-ah-for-test dl) #x00))
(define-fun occupancy () Bool (distinct (bvand captured dl) #x00))
(define-fun candidate-rcl () Byte (rcl-byte-1 al occupancy))
(define-fun candidate-pawn-accept () Bool
  (parity-even (bvand candidate-rcl #x03)))
(define-fun original-enter-eval () Bool
  (or (not is-pawn) original-pawn-accept))
(define-fun candidate-enter-eval () Bool
  (or (not is-pawn) candidate-pawn-accept))

; Both recursive calls enter with this same normalized board. Incoming AX/BX
; differences have been killed by the exact callee prefix proved separately.
; Equality of recursive-score is an explicit compositional hypothesis.  A
; separate whole-search argument must discharge it; this query proves neither
; induction nor recursive score equality on its own.
(define-fun moved () Mem (store (store board0 src #x00) dst moving))
(define-fun original-undone () Mem
  (store (store moved dst captured) src (select moved dst)))
(define-fun candidate-undone () Mem
  (store (store moved dst captured) src (select moved dst)))
(define-fun original-board-out () Mem
  (ite original-enter-eval original-undone board0))
(define-fun candidate-board-out () Mem
  (ite candidate-enter-eval candidate-undone board0))

; CMP AL,[score] / JL performs the same signed comparison because the recursive
; result is equal.  The three best-record writes are therefore identical.
(define-fun update-best () Bool (not (bvslt recursive-score incumbent)))
(define-fun best0 () Mem (store stack0 score-slot incumbent))
(define-fun original-best-out () Mem
  (ite original-enter-eval
    (ite update-best
      (store (store (store best0 score-slot recursive-score)
                           dst-slot ((_ extract 7 0) di))
                   src-slot ((_ extract 7 0) bp))
      best0)
    stack0))
(define-fun candidate-best-out () Mem
  (ite candidate-enter-eval
    (ite update-best
      (store (store (store best0 score-slot recursive-score)
                           dst-slot ((_ extract 7 0) di))
                   src-slot ((_ extract 7 0) bp))
      best0)
    stack0))

; Immediate post-undo decisions and continuation-live register projection.
(define-fun original-dst-colored () Bool
  (distinct (bvand (select original-board-out dst) dl) #x00))
(define-fun candidate-dst-colored () Bool
  (distinct (bvand (select candidate-board-out dst) dl) #x00))
(define-fun original-neg-al () Byte (bvneg al))
(define-fun candidate-neg-al () Byte (bvneg al))
(define-fun original-bl-out () Byte bl)
(define-fun candidate-bl-out () Byte bl)
(define-fun original-cx-out () Word cx)
(define-fun candidate-cx-out () Word cx)
(define-fun original-dx-out () Word dx)
(define-fun candidate-dx-out () Word dx)
(define-fun original-bp-out () Word bp)
(define-fun candidate-bp-out () Word bp)
(define-fun original-si-out () Word si)
(define-fun candidate-si-out () Word si)
(define-fun original-di-out () Word di)
(define-fun candidate-di-out () Word di)
(define-fun original-sp-out () Word sp)
(define-fun candidate-sp-out () Word sp)

; Negation of contextual equivalence.  AH/BH and dead local-frame bytes are not
; live outputs; AX/BX are either killed at call entry or before loop reuse.
(assert (or
  (distinct original-enter-eval candidate-enter-eval)
  (distinct original-board-out candidate-board-out)
  (distinct original-dst-colored candidate-dst-colored)
  (distinct original-neg-al candidate-neg-al)
  (distinct original-best-out candidate-best-out)
  (distinct original-bl-out candidate-bl-out)
  (distinct original-cx-out candidate-cx-out)
  (distinct original-dx-out candidate-dx-out)
  (distinct original-bp-out candidate-bp-out)
  (distinct original-si-out candidate-si-out)
  (distinct original-di-out candidate-di-out)
  (distinct original-sp-out candidate-sp-out)))
(check-sat)
(get-proof)

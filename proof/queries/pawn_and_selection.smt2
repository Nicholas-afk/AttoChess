; Local obligations only, not a whole-program proof. Replay with:
; z3 proof/queries/pawn_and_selection.smt2
(set-option :produce-proofs true)
(set-logic QF_BV)
(declare-const cell (_ BitVec 8))
(declare-const dl (_ BitVec 8))
(declare-const dh (_ BitVec 8))
(declare-const score (_ BitVec 8))
(define-fun reachable-cell () Bool
  (or (= cell #x00) (= cell #x09) (= cell #x2e) (= cell #x0d) (= cell #x0a)
      (= cell #xa2) (= cell #xa3) (= cell #xa5) (= cell #xa6) (= cell #xa7)
      (= cell #x24) (= cell #x14)
      (= cell #x92) (= cell #x93) (= cell #x95) (= cell #x96) (= cell #x97)))
(assert reachable-cell)
(assert (or (and (= dl #x18) (= dh #x28))
            (and (= dl #x28) (= dh #x18))))
; The candidate's TEST AH,DH / JNZ has already accepted this destination.
(assert (= (bvand cell dh) #x00))
; NEG sets CF iff its input is nonzero. The old sequence first ANDs DL.
; Both then feed the same RCL/TEST/POP/JPO sequence.
(define-fun old-carry () Bool (distinct (bvand cell dl) #x00))
(define-fun new-carry () Bool (distinct cell #x00))
; JL skips a best-record write exactly for signed-less-than. No byte score
; is below the new initial incumbent -128, so the first candidate is recorded.
(assert (or (distinct old-carry new-carry) (bvslt score #x80)))
(check-sat)
(get-proof)

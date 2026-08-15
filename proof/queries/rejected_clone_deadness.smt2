(set-option :produce-proofs true)
(set-logic QF_AUFBV)
(define-sort Byte () (_ BitVec 8))
(define-sort Word () (_ BitVec 16))
(define-sort Edge () (_ BitVec 2))
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
(declare-const edge Edge)
(declare-const al0 Byte)
(declare-const destination Byte)
(declare-const bl Byte)
(declare-const dl Byte)
(declare-const dh Byte)
(declare-const sp Word)
(assert (bvule edge #b10))
(assert (or (and (= dl #x18) (= dh #x28))
            (and (= dl #x28) (= dh #x18))))

(define-fun destination-blocked () Bool
  (distinct (bvand destination dh) #x00))
(define-fun direction-ok () Bool
  (distinct (bvand (bvxor al0 dh) #x20) #x00))
(define-fun diagonal () Bool (distinct (bvand al0 #x01) #x00))
(define-fun original-test-ah () Byte
  (ite diagonal destination (bvxor destination #x30)))
(define-fun original-pawn-accept () Bool
  (distinct (bvand original-test-ah dl) #x00))
(define-fun occupancy () Bool (distinct (bvand destination dl) #x00))
(define-fun candidate-rcl () Byte (rcl-byte-1 al0 occupancy))
(define-fun candidate-pawn-accept () Bool
  (parity-even (bvand candidate-rcl #x03)))

; Select one of the exact three control-flow rejection conditions.
(define-fun selected-reject-condition () Bool
  (ite (= edge #b00)
       destination-blocked
  (ite (= edge #b01)
       (and (not destination-blocked) (= bl #x04) (not direction-ok))
       (and (not destination-blocked) (= bl #x04) direction-ok
            (not original-pawn-accept)))))
(assert selected-reject-condition)
(define-fun original-rejects () Bool
  (ite (= edge #b00) destination-blocked
  (ite (= edge #b01) (not direction-ok) (not original-pawn-accept))))
(define-fun candidate-rejects () Bool
  (ite (= edge #b00) destination-blocked
  (ite (= edge #b01) (not direction-ok) (not candidate-pawn-accept))))

; PUSH/POP restores AL and SP on both pawn edges. The blocked-destination edge
; changes neither. No selected edge has executed CALL move_sub or board stores.
(define-fun original-al-at-vec-cont () Byte al0)
(define-fun candidate-al-at-vec-cont () Byte al0)
(define-fun original-sp-at-vec-cont () Word sp)
(define-fun candidate-sp-at-vec-cont () Word sp)
(define-fun original-board-at-vec-cont () Mem board0)
(define-fun candidate-board-at-vec-cont () Mem board0)
(define-fun original-target () Word #x01d3)
(define-fun candidate-target () Word #x01d3)
(define-fun original-neg-al () Byte (bvneg original-al-at-vec-cont))
(define-fun candidate-neg-al () Byte (bvneg candidate-al-at-vec-cont))

; Negation of all three reject-edge value projections. Register deadness after
; this join is checked by a separate exhaustive decoded-CFG traversal.
(assert (or
  (distinct original-rejects candidate-rejects)
  (not original-rejects)
  (not candidate-rejects)
  (distinct original-target candidate-target)
  (distinct original-al-at-vec-cont candidate-al-at-vec-cont)
  (distinct original-sp-at-vec-cont candidate-sp-at-vec-cont)
  (distinct original-board-at-vec-cont candidate-board-at-vec-cont)
  (distinct original-neg-al candidate-neg-al)))
(check-sat)
(get-proof)

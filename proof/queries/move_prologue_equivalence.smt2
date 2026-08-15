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
(define-fun swap-dl-dh ((dx Word)) Word
  (concat ((_ extract 7 0) dx) ((_ extract 15 8) dx)))

(declare-const mem0 Mem)
(declare-const bp Word)
(declare-const di Word)
(declare-const ax0 Word)
(declare-const cx Word)
(declare-const dx Word)
(assert (distinct bp di))
; CX is initialized to a small depth and never carries into CH.
(assert (= ((_ extract 15 8) cx) #x00))

(define-fun source () Byte (select mem0 bp))
(define-fun captured () Byte (select mem0 di))
; Original CMP [BP],CH / JZ $.
(define-fun original-diverges () Bool
  (= source ((_ extract 15 8) cx)))
; Candidate XOR AX,AX; XCHG AL,[BP]; TEST AL,AL / JZ $.
(define-fun candidate-mem-after-source () Mem (store mem0 bp #x00))
(define-fun candidate-al-after-source () Byte source)
(define-fun candidate-diverges () Bool (= candidate-al-after-source #x00))

; On the nonempty path both programs now execute the same two exchanges.
(define-fun original-moved () Mem
  (store (store mem0 bp #x00) di source))
(define-fun candidate-moved () Mem
  (store candidate-mem-after-source di candidate-al-after-source))
(define-fun original-ax-before-and () Word (concat #x00 captured))
(define-fun candidate-ax-before-and () Word (concat #x00 captured))
(define-fun original-dx-after-swap () Word (swap-dl-dh dx))
(define-fun candidate-dx-after-swap () Word (swap-dl-dh dx))

; The old XOR leaves ZF=1.  On every continuing candidate path, TEST AL,AL
; leaves ZF=0.  This records the real intermediate difference rather than
; pretending the flags agree.
(define-fun original-zf-before-and () Bool true)
(define-fun candidate-zf-before-and () Bool (= source #x00))
; AND AL,07h is the first later arithmetic instruction and overwrites all
; flags subsequently read by Jcc: CF,PF,ZF,SF,OF (AF remains unobserved).
(define-fun and-result () Byte (bvand captured #x07))
(define-fun original-cf-after-and () Bool false)
(define-fun candidate-cf-after-and () Bool false)
(define-fun original-pf-after-and () Bool (parity-even and-result))
(define-fun candidate-pf-after-and () Bool (parity-even and-result))
(define-fun original-zf-after-and () Bool (= and-result #x00))
(define-fun candidate-zf-after-and () Bool (= and-result #x00))
(define-fun original-sf-after-and () Bool (= ((_ extract 7 7) and-result) #b1))
(define-fun candidate-sf-after-and () Bool (= ((_ extract 7 7) and-result) #b1))
(define-fun original-of-after-and () Bool false)
(define-fun candidate-of-after-and () Bool false)

; Both self-loops emit no DOS/console/memory events.  Registers need not be
; compared because neither divergent execution has a post-state.
(define-fun original-divergent-events () Word #x0000)
(define-fun candidate-divergent-events () Word #x0000)

; Negation of trace equivalence on empty source and state equivalence on the
; continuing path, plus the exact dead-flag fact before AND.
(assert (or
  (distinct original-diverges candidate-diverges)
  (and original-diverges
       (or (distinct candidate-mem-after-source mem0)
           (distinct original-divergent-events candidate-divergent-events)))
  (and (not original-diverges)
       (or (distinct original-moved candidate-moved)
           (distinct original-ax-before-and candidate-ax-before-and)
           (distinct original-dx-after-swap candidate-dx-after-swap)
           (not original-zf-before-and)
           candidate-zf-before-and
           (distinct original-cf-after-and candidate-cf-after-and)
           (distinct original-pf-after-and candidate-pf-after-and)
           (distinct original-zf-after-and candidate-zf-after-and)
           (distinct original-sf-after-and candidate-sf-after-and)
           (distinct original-of-after-and candidate-of-after-and)))))
(check-sat)
(get-proof)

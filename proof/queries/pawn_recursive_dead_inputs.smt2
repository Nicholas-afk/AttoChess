(set-option :produce-proofs true)
(set-logic QF_AUFBV)
(define-sort Byte () (_ BitVec 8))
(define-sort Word () (_ BitVec 16))
(define-sort Mem () (Array Word Byte))
(define-fun material ((x Byte)) Byte
  (ite (= (bvand x #x07) #x00) #x00
  (ite (= (bvand x #x07) #x01) #x00
  (ite (= (bvand x #x07) #x02) #x03
  (ite (= (bvand x #x07) #x03) #x03
  (ite (= (bvand x #x07) #x04) #x01
  (ite (= (bvand x #x07) #x05) #x09
  (ite (= (bvand x #x07) #x06) #x05 #x2e))))))))
(define-fun swap-dl-dh ((dx Word)) Word
  (concat ((_ extract 7 0) dx) ((_ extract 15 8) dx)))

(declare-const mem0 Mem)
(declare-const bp Word)
(declare-const di Word)
(declare-const cx Word)
(declare-const dx Word)
(declare-const incoming-ax-a Word)
(declare-const incoming-ax-b Word)
(declare-const incoming-bx-a Word)
(declare-const incoming-bx-b Word)
(declare-const eval-base Word)
(assert (distinct bp di))
; The audited recursion uses depths 0..4, so CH=0.  This obligation concerns
; the continuing call path: its selected source is nonzero, hence not CH.
(assert (= ((_ extract 15 8) cx) #x00))
(assert (distinct (select mem0 bp) #x00))
(assert (distinct (select mem0 bp) ((_ extract 15 8) cx)))

; XOR AX,AX kills every incoming AX bit before the first read of AX.
(define-fun killed-ax-a () Word (bvxor incoming-ax-a incoming-ax-a))
(define-fun killed-ax-b () Word (bvxor incoming-ax-b incoming-ax-b))
; XCHG AL,[BP]; XCHG AL,[DI] creates the common speculative board.
(define-fun mem1-a () Mem
  (store mem0 bp ((_ extract 7 0) killed-ax-a)))
(define-fun mem1-b () Mem
  (store mem0 bp ((_ extract 7 0) killed-ax-b)))
(define-fun source-a () Byte (select mem0 bp))
(define-fun source-b () Byte (select mem0 bp))
(define-fun captured-a () Byte (select mem1-a di))
(define-fun captured-b () Byte (select mem1-b di))
(define-fun mem2-a () Mem (store mem1-a di source-a))
(define-fun mem2-b () Mem (store mem1-b di source-b))
; AND AL,07h; MOV BX,eval_db; XLAT.  MOV kills every incoming BX bit.
(define-fun search-ax-a () Word (concat #x00 (material captured-a)))
(define-fun search-ax-b () Word (concat #x00 (material captured-b)))
(define-fun search-bx-a () Word
  (bvadd (bvxor incoming-bx-a incoming-bx-a) eval-base))
(define-fun search-bx-b () Word
  (bvadd (bvxor incoming-bx-b incoming-bx-b) eval-base))
(define-fun depth-zero-a () Bool (= cx #x0000))
(define-fun depth-zero-b () Bool (= cx #x0000))

; Negation: some search-entry observable still depends on incoming AX or BX.
(assert (or
  (distinct killed-ax-a killed-ax-b)
  (distinct mem2-a mem2-b)
  (distinct search-ax-a search-ax-b)
  (distinct search-bx-a search-bx-b)
  (distinct (swap-dl-dh dx) (swap-dl-dh dx))
  (distinct depth-zero-a depth-zero-b)))
(check-sat)
(get-proof)

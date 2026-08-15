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
(define-fun store-word-le ((m Mem) (a Word) (v Word)) Mem
  (store (store m a ((_ extract 7 0) v))
               (bvadd a #x0001) ((_ extract 15 8) v)))

(declare-const mem0 Mem)
(declare-const sp Word)
(declare-const al0 Byte)
(declare-const ah0 Byte)
(declare-const dl Byte)
(declare-const dh Byte)

; The only color-mask states reachable from MOV DX,1828h and XCHG DL,DH.
(assert (or (and (= dl #x18) (= dh #x28))
            (and (= dl #x28) (= dh #x18))))
; The preceding TEST AH,DH / JNZ has admitted this destination.
(assert (= (bvand ah0 dh) #x00))
; The preceding direction TEST has admitted this signed pawn vector.
(assert (distinct (bvand (bvxor al0 dh) #x20) #x00))

; Both programs have already executed PUSH AX / ... / POP AX for direction.
; That PUSH leaves AX in the scratch word below the restored SP.
(define-fun ax0 () Word (concat ah0 al0))
(define-fun scratch () Word (bvsub sp #x0002))
(define-fun mem-after-direction () Mem (store-word-le mem0 scratch ax0))

; Original: TEST AL,1; diagonal skips XOR; straight toggles both color bits;
; TEST AH,DL accepts exactly when its result is nonzero.
(define-fun diagonal () Bool (distinct (bvand al0 #x01) #x00))
(define-fun original-test-value () Byte
  (bvand (ite diagonal ah0 (bvxor ah0 #x30)) dl))
(define-fun original-accept () Bool (distinct original-test-value #x00))

; Optimized exact instruction semantics:
;   PUSH AX       writes the same AX to the same scratch word
;   AND AH,DL     isolates zero or the opponent color bit
;   NEG AH        sets CF iff that isolated byte is nonzero
;   RCL AL,1      puts old AL bit 0 in result bit 1 and CF in result bit 0
;   TEST AL,3     sets PF iff those two bits agree
;   POP AX        restores AX and does not modify PF
;   JPO reject    rejects iff PF=0, so acceptance is PF=1
(define-fun candidate-and-ah () Byte (bvand ah0 dl))
(define-fun candidate-cf-after-neg () Bool (distinct candidate-and-ah #x00))
(define-fun candidate-rcl-al () Byte
  (rcl-byte-1 al0 candidate-cf-after-neg))
(define-fun candidate-test-value () Byte (bvand candidate-rcl-al #x03))
(define-fun candidate-pf-after-test () Bool (parity-even candidate-test-value))
(define-fun candidate-pf-after-pop () Bool candidate-pf-after-test)
(define-fun candidate-accept () Bool candidate-pf-after-pop)
(define-fun expected-accept () Bool (= diagonal candidate-cf-after-neg))
(define-fun mem-after-candidate-push () Mem
  (store-word-le mem-after-direction scratch ax0))
(define-fun candidate-al-after-pop () Byte al0)
(define-fun candidate-ah-after-pop () Byte ah0)
(define-fun candidate-sp-after-pop () Word sp)

; Negation of the exact predicate and live-state theorem.
(assert (or
  (distinct original-accept candidate-accept)
  (distinct candidate-accept expected-accept)
  (distinct candidate-al-after-pop al0)
  (distinct candidate-ah-after-pop ah0)
  (distinct candidate-sp-after-pop sp)
  (distinct mem-after-candidate-push mem-after-direction)))
(check-sat)
(get-proof)

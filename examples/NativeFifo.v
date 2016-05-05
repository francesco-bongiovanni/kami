Require Import Arith.Peano_dec Bool String List.
Require Import Lib.CommonTactics Lib.ilist Lib.Word Lib.Indexer Lib.StringBound.
Require Import Lts.Syntax Lts.Semantics Lts.Equiv.

Set Implicit Arguments.

Section NativeFifo.
  Variable fifoName: string.
  Variable dType: Kind.
  Variable default: ConstT dType.

  Notation "^ s" := (fifoName .. s) (at level 0).

  Definition listEltT ty := list (ty dType).
  Definition listEltK ty := @NativeKind (listEltT ty) nil.
  Definition listElt ty := (^"elt" :: (@NativeConst (listEltT ty) nil nil))%struct.

  Definition listIsEmpty {ty} (l: fullType ty (listEltK ty)) :=
    if eq_nat_dec (length l) 1 then ConstBool true else ConstBool false.
  Definition listEnq {ty} (a: ty dType) (l: fullType ty (listEltK ty)) :=
    a :: l.
  Definition listDeq {ty} (l: fullType ty (listEltK ty)) :=
    match l with
    | nil => nil
    | h :: t => t
    end.
  Definition listFirstElt {ty} (l: fullType ty (listEltK ty)): Expr ty (SyntaxKind dType) :=
    match l with
    | nil => ($$default)%kami
    | h :: t => (#h)%kami
    end.

  (* defined methods *)
  Definition nativeEnq {ty} : forall (d: ty dType), ActionT ty Void := fun d =>
    (ReadN elt : listEltK ty <- ^"elt";
     Write ^"elt" <- (Var _ (listEltK ty) (listEnq d elt));
     Retv)%kami.

  Definition nativeDeq {ty} : ActionT ty dType :=
    (ReadN elt : listEltK ty <- ^"elt";
     Assert !$$(listIsEmpty elt);
     Write ^"elt" <- (Var _ (listEltK ty) (listDeq elt));
     Ret (listFirstElt elt))%kami.

  Definition nativeFirstElt {ty} : ActionT ty dType :=
    (ReadN elt : listEltK ty <- ^"elt";
     Assert !$$(listIsEmpty elt);
     Ret (listFirstElt elt))%kami.

  Definition nativeFifo := MODULE {
    RegisterN ^"elt" : listEltK type <- (NativeConst nil nil)

    with Method ^"enq"(d : dType) : Void := (nativeEnq d)
    with Method ^"deq"() : dType := nativeDeq
    with Method ^"firstElt"() : dType := nativeFirstElt
  }.

  Definition nativeSimpleFifo := MODULE {
    RegisterN ^"elt" : listEltK type <- (NativeConst nil nil)

    with Method ^"enq"(d : dType) : Void := (nativeEnq d)
    with Method ^"deq"() : dType := nativeDeq
  }.

End NativeFifo.

Hint Unfold nativeFifo nativeSimpleFifo : ModuleDefs.
Hint Unfold listEltT listEltK listElt
     listIsEmpty listEnq listDeq listFirstElt
     nativeEnq nativeDeq nativeFirstElt: MethDefs.


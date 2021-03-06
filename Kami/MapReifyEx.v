Require Import Lib.Struct Lib.FMap List Lib.Word Lib.Nomega Arith Kami.ParametricSyntax String
        Lib.Indexer Kami.Syntax Kami.Semantics Program.Equality Lib.CommonTactics
        Kami.Tactics Kami.SymEvalTac Kami.SymEval Omega.

Set Implicit Arguments.
Set Asymmetric Patterns.

Section ConvMakeMap.
  Variable A: Type.
  Variable f1 f2: A -> Type.
  Variable f: forall x, f1 x -> f2 x.

  Variable g: nat -> Attribute (sigT f1).

  Fixpoint repMap n :=
    M.add (attrName (g n))
          (existT _ (projT1 (attrType (g n))) (f (projT2 (attrType (g n)))))
          match n with
            | 0 => M.empty _
            | S m => repMap m
          end.
  Lemma makeMap_fold_eq n:
    makeMap f2 f (map g (getNatListToN n)) = repMap n.
  Proof.
    induction n; simpl in *; auto.
    destruct (g 0); destruct attrType; simpl; auto.
    rewrite <- IHn.
    destruct (g (S n)); destruct attrType; reflexivity.
  Qed.
End ConvMakeMap.

Section MapVar.
  Require Import Lib.StringEq.
  Variable n: nat.
  Variable A: Type.
  Variable f1 f2: A -> Type.
  Variable f: forall x, f1 x -> f2 x.

  Inductive MapVR : M.t (sigT f2) -> Type :=
  | MVParam m: MapVR m
  | MVREmpty: MapVR (M.empty _)
  | MVRAdd:
      forall k (pf: index 0 indexSymbol k = None) v {m},
        MapVR m -> MapVR (M.add k v m)
  | MVRAddV:
      forall k (pf: index 0 indexSymbol k = None) i v {m},
        MapVR m -> MapVR (M.add (addIndexToStr string_of_nat i k) v m)
  | MVRUnion:
      forall {m1 m2},
        MapVR m1 -> MapVR m2 ->
        MapVR (M.union m1 m2)
  | MVRVar s (pf: index 0 indexSymbol s = None) (v: sigT f1) m (mr: MapVR m):
      MapVR
        (M.union (repMap f2 f (fun i => (addIndexToStr string_of_nat
                                                       i s :: v)%struct) n) m).

  Fixpoint findMVR_string k (pf: index 0 indexSymbol k = None)
           {m} (mr : MapVR m): option (sigT f2) :=
    match mr with
      | MVParam m => M.find k m
      | MVREmpty => None
      | MVRAdd k' pf' v _ mr' => if string_eq k k'
                                 then Some v else findMVR_string k pf mr'
      | MVRAddV k' pf' i v _ mr' => findMVR_string k pf mr'
      | MVRUnion _ _ mr1 mr2 =>
        match findMVR_string k pf mr1 with
          | Some v => Some v
          | _ => findMVR_string k pf mr2
        end
      | MVRVar s pf' v m mr => findMVR_string k pf mr
    end.

  Fixpoint findMVR_var k (pf: index 0 indexSymbol k = None)
           i {m} (mr : MapVR m): option (sigT f2) :=
    match mr with
      | MVParam m => M.find (addIndexToStr string_of_nat i k) m
      | MVREmpty => None
      | MVRAdd k' pf' v _ mr' => findMVR_var k pf i mr'
      | MVRAddV k' pf' i' v _ mr' => if string_eq k k'
                                     then if eq_nat_dec i i'
                                          then Some v
                                          else findMVR_var k pf i mr'
                                     else findMVR_var k pf i mr'
      | MVRUnion _ _ mr1 mr2 =>
        match findMVR_var k pf i mr1 with
          | Some v => Some v
          | _ => findMVR_var k pf i mr2
        end
      | MVRVar s pf' v m mr => if string_eq k s
                               then Some (existT _ (projT1 v) (f (projT2 v)))
                               else findMVR_var k pf i mr
    end.

  Lemma not_find_string_rep:
    forall s (pfs: index 0 indexSymbol s = None) k (pf: index 0 indexSymbol k = None) v,
      M.Map.find (elt:=sigT f2) k
                 (repMap f2 f
                         (fun i : nat =>
                            (addIndexToStr string_of_nat i s :: v)%struct) n) = None.
  Proof.
    induction n; simpl in *; auto; intros.
    - rewrite <- (@M.find_empty _ k).
      apply M.find_add_2.
      intro H; subst;
      apply badIndex in pf; auto.
    - rewrite M.find_add_2; auto.
      intro H; subst; apply badIndex in pf; auto.
  Qed.

  Lemma not_find_string_var:
    forall k k0 (pf0: index 0 indexSymbol k0 = None) i v m,
      M.find (elt:=sigT f2) k0 (M.add (addIndexToStr string_of_nat i k) v m) = M.find k0 m.
  Proof.
    induction n; simpl in *; auto; intros.
    rewrite M.find_add_2; auto.
    intro H; subst.
    apply badIndex in pf0.
    auto.
  Qed.

  Lemma findMVR_find_string:
    forall m (mr: MapVR m) k (pf: index 0 indexSymbol k = None),
      findMVR_string k pf mr = M.find k m.
  Proof.
    induction mr; simpl; auto; intros.
    - dest_str; simpl in *.
      specialize (IHmr k pf); simpl in *.
      findeq.
      specialize (IHmr k0 pf0); simpl in *.
      findeq.
    - unfold withIndex.
      rewrite not_find_string_var; auto.
    - specialize (IHmr1 k pf); specialize (IHmr2 k pf); findeq.
    - rewrite IHmr.
      rewrite M.find_union.
      rewrite not_find_string_rep; auto.
  Qed.

  Lemma find_var_rep:
    forall i s v,
      (i <= n)%nat ->
      M.Map.find (addIndexToStr string_of_nat i s)
                 (repMap f2 f
                         (fun i0 : nat =>
                            (addIndexToStr string_of_nat i0 s :: v)%struct) n) =
      Some (existT _ (projT1 v) (f (projT2 v))).
  Proof.
    induction n; simpl in *; auto; intros.
    - assert (i = 0) by omega; subst; apply M.find_add_1.
    - assert (dst: i = S n0 \/ (i <= n0)%nat) by omega.
      destruct dst as [ez | hard]; subst.
      + apply M.find_add_1.
      + rewrite M.find_add_2; auto.
        intro sth.
        pose proof (withIndex_index_eq s s i (S n0) sth) as [_ sth2].
        omega.
  Qed.

  Lemma not_find_var_rep:
    forall i s s' v,
      s <> s' ->
      M.Map.find (elt:=sigT f2) (addIndexToStr string_of_nat i s)
                 (repMap f2 f
                         (fun i0 : nat =>
                            (addIndexToStr string_of_nat i0 s' :: v)%struct) n)
      = None.
  Proof.
    induction n; simpl; auto; intros.
    - rewrite M.find_add_2; auto.
      intro sth;
        pose proof (withIndex_index_eq s s' i 0 sth) as [sth2 _].
      auto.
    - rewrite M.find_add_2; auto.
      intro sth;
        pose proof (withIndex_index_eq s s' i (S n0) sth) as [sth2 _].
      auto.
  Qed.

  Lemma addStrGood si sj i j:
    addIndexToStr string_of_nat i si = addIndexToStr string_of_nat j sj -> si = sj /\ i = j.
  Proof.
    intros.
    unfold addIndexToStr in H.
    apply withIndex_index_eq; auto.
  Qed.

  Lemma findMVR_find_var:
    forall m (mr: MapVR m) k pf i,
      (i <= n)%nat ->
      findMVR_var k pf i mr =
      M.find (addIndexToStr string_of_nat i k) m.
  Proof.
    unfold withIndex.
    induction mr; auto; intros; simpl.
    - rewrite M.find_add_2; auto.
      let H := fresh in intro H; subst; apply badIndex in pf; auto.
    - simpl; dest_str; simpl in *.
      + destruct (eq_nat_dec i0 i); simpl in *; subst.
        * findeq.
        * rewrite M.find_add_2; auto.
          intro sth.
          apply addStrGood in sth. destruct sth; auto.
      + rewrite M.find_add_2; auto.
        intro sth.
        apply addStrGood in sth; destruct sth; auto.
    - rewrite M.find_union.
      simpl.
      rewrite (@IHmr1 _ _ i), (@IHmr2 _ _ i); auto.
    - simpl; dest_str; simpl in *.
      + rewrite M.find_union.
        fold (addIndexToStr string_of_nat i s).
        rewrite find_var_rep; auto.
      + rewrite M.find_union.
        rewrite <- (IHmr k pf0 i); auto.
        fold (addIndexToStr string_of_nat i k).
        rewrite (not_find_var_rep i); auto.
  Qed.
End MapVar.

Lemma mapVec_replicate_commute:
  forall A B (f: A -> B) n v, mapVec f (replicate v n) = replicate (f v) n.
Proof.
  induction n; simpl in *; auto; intros.
  rewrite IHn; reflexivity.
Qed.

Lemma evalVec_replicate:
  forall A n (v: A) i, evalVec (replicate v n) i = v.
Proof.
  induction n; simpl in *; auto; intros.
  dependent destruction i.
  destruct b;
    rewrite IHn; reflexivity.
Qed.

Require Import Lib.Nomega NArith.

Theorem roundTrip_0' : forall sz, wordToN (natToWord sz 0) = 0%N.
  induction sz; simpl; subst; intuition.
  rewrite IHsz.
  auto.
Qed.


Lemma wzero_le:
  forall n (w: word n), wzero n <= w.
Proof.
  unfold wzero, not; intros.
  pre_nomega.
  rewrite roundTrip_0' in H.
  nomega.
Qed.
  
Section makeMapUnion.
  Variable A: Type.
  Variable f1 f2: A -> Type.
  Variable f: forall x, f1 x -> f2 x.

  Theorem makeMapUnion l1 l2:
    (forall i, In i (namesOf l1) -> In i (namesOf l2) -> False) ->
    makeMap f2 f (l1 ++ l2) = M.union (makeMap f2 f l1) (makeMap f2 f l2).
  Proof.
    intros.
    apply makeMap_union.
    unfold DisjList; intros.
    specialize (H e).
    pose proof (in_dec string_dec e (namesOf l1)) as K1.
    pose proof (in_dec string_dec e (namesOf l1)) as K2.
    destruct K1, K2; intuition auto.
  Qed.
End makeMapUnion.
  
Lemma In_getNatListToN: forall n i, In i (getNatListToN n) -> (i <= n)%nat.
Proof.
  induction n; simpl in *; auto; intros.
  - destruct H; omega.
  - destruct H; subst; [ | apply IHn in H]; omega.
Qed.

Ltac doDestruct := (repeat match goal with
                             | H: _ \/ _ |- _ =>
                               destruct H
                             | H: False |- _ => exfalso; auto
                                                       | _ => subst; simpl in *; dest;
                             match goal with
                               | H: In ?i (getNatListToN ?n) |- _ =>
                                 apply In_getNatListToN in H; subst
                             end
                           end
                   ).

Ltac mapVReify f2 f n m :=
  match m with
    | M.union
        (repMap _ _ (fun i => (addIndexToStr _
                                             i ?s :: ?v)%struct) _) ?m
      =>
      let mr := mapVReify f2 f n m in
      constr:(MVRVar s eq_refl v mr)
    | M.empty _ => constr:(MVREmpty n _ f2 f)
    | M.add (addIndexToStr _ ?i ?k) ?v ?m' =>
      let mr' := mapVReify f2 f n m' in
      constr:(MVRAddV k eq_refl i v mr')
    | M.add ?k ?v ?m' =>
      let mr' := mapVReify f2 f n m' in
      constr:(MVRAdd k eq_refl v mr')
    | M.union ?m1 ?m2 =>
      let mr1 := mapVReify f2 f n m1 in
      let mr2 := mapVReify f2 f n m2 in
      constr:(MVRUnion mr1 mr2)
    | _ => constr:(MVParam n _ f m)
  end.

Ltac mapVR_Regs n m := mapVReify (fullType type) evalConstFullT
                                 n m.

Ltac mapVR_Others t n m := mapVReify t (fun k (v: t k) => v)
                                     n m.

Ltac mapVR_Meths n m := mapVReify SignT (fun k (v: SignT k) => v)
                                  n m.

Open Scope fmap.

Definition do_upd_map_key_instance (x: nat) (ls: list (string * sigT (fullType type))): RegsT :=
  fold_right (fun nk (m: RegsT) =>
                m#[(fst nk) __ x |--> snd nk]) (M.empty _) ls.


Ltac mkList_add_key_instance madds :=
  match madds with
    | M.add (addIndexToStr _ ?x ?k) ?v ?m =>
      let ls := mkList_add_key_instance m in
      constr:( (k, v) :: ls)
    | M.empty ?t => constr:(@nil (string * t))
  end.

Close Scope fmap.


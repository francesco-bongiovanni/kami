Require Import Bool List String Structures.Equalities Program.Equality Eqdep Eqdep_dec.
Require Import Lib.Struct Lib.Word Lib.CommonTactics Lib.StringBound Lib.ilist Lib.FMap.
Require Import Syntax.
Require Export SemanticsExprAction.

Set Implicit Arguments.

Inductive UnitLabel :=
| Rle: option string -> UnitLabel
| Meth: option (Attribute (sigT SignT)) -> UnitLabel.

Record LabelT := { annot: option (option string);
                   defs: MethsT;
                   calls: MethsT }.

Definition emptyRuleLabel: LabelT :=
  {| annot := Some None; defs := M.empty _; calls := M.empty _ |}.
Definition emptyMethLabel: LabelT :=
  {| annot := None; defs := M.empty _; calls := M.empty _ |}.

Section GivenModule.
  Variable m: Modules.

  Section GivenOldregs.
    Variable o: RegsT.

    Inductive Substep: UpdatesT -> UnitLabel -> MethsT -> Prop :=
    | EmptyRule:
        Substep (M.empty _) (Rle None) (M.empty _)
    | EmptyMeth:
        Substep (M.empty _) (Meth None) (M.empty _)
    | SingleRule k (a: Action Void)
                 (HInRules: List.In {| attrName := k; attrType := a |} (getRules m))
                 u cs (HAction: SemAction o (a type) u cs WO):
        Substep u (Rle (Some k)) cs
    | SingleMeth (f: DefMethT)
                 (HIn: In f (getDefsBodies m))
                 u cs argV retV
                 (HAction: SemAction o ((projT2 (attrType f)) type argV) u cs retV)
                 sig (Hsig: sig = {| attrName := attrName f;
                                     attrType := (existT _ _ (argV, retV)) |}):
        Substep u (Meth (Some sig)) cs.

    Record SubstepRec :=
      { upd: UpdatesT;
        unitAnnot: UnitLabel;
        cms: MethsT;
        substep: Substep upd unitAnnot cms }.

    Definition Substeps := list SubstepRec.

    Definition canCombine (s1 s2: SubstepRec) :=
      M.Disj (upd s1) (upd s2) /\
      (forall x y, unitAnnot s1 = Meth (Some x) ->
                   unitAnnot s2 = Meth (Some y) -> attrName x <> attrName y) /\
      (exists x, unitAnnot s1 = Meth x \/ unitAnnot s2 = Meth x) /\
      M.Disj (cms s1) (cms s2).

    Inductive substepsComb: Substeps -> Prop :=
    | NilSubsteps: substepsComb nil
    | AddSubstep (s: SubstepRec) (ss: Substeps):
        substepsComb ss -> (forall s', In s' ss -> canCombine s s') ->
        substepsComb (s :: ss).

    Fixpoint foldSSUpds (ss: Substeps) :=
      match ss with
        | x :: xs => M.union (foldSSUpds xs) (upd x)
        | nil => M.empty _
      end.

    Definition getLabel (a: UnitLabel) (cs: MethsT) :=
      {| annot :=
           match a with
             | Rle x => Some x
             | Meth _ => None
           end;
         defs :=
           match a with
             | Meth (Some {| attrName := n; attrType := t |}) =>
               M.add n t (M.empty _)
             | _ => M.empty _
           end;
         calls := cs |}.

    Definition getSLabel (s: SubstepRec) := getLabel (unitAnnot s) (cms s).

    Definition mergeLabel lnew lold :=
      match lnew, lold with
        | {| annot := a'; defs := d'; calls := c' |},
          {| annot := a; defs := d; calls := c |} =>
          {| annot := match a', a with
                        | None, x => x
                        | x, None => x
                        | x, y => x
                      end; defs := M.union d' d; calls := M.union c' c |}
      end.
    
    Definition addLabelLeft lold s := mergeLabel (getSLabel s) lold.

    Fixpoint foldSSLabel (ss: Substeps) :=
      match ss with
        | x :: xs => addLabelLeft (foldSSLabel xs) x
        | nil => {| annot := None; defs := M.empty _; calls := M.empty _ |}
      end.

    
    Theorem foldSSLabelDist: forall s1 s2,
        foldSSLabel (s1 ++ s2) = mergeLabel (foldSSLabel s1) (foldSSLabel s2).
    Proof.
      induction s1; intros; simpl.
      - destruct (foldSSLabel s2).
        repeat rewrite M.union_empty_L.
        reflexivity.
      - specialize (IHs1 s2).
        rewrite IHs1; clear.
        unfold addLabelLeft.
        destruct a, (foldSSLabel s1), (foldSSLabel s2); clear; simpl.
        destruct unitAnnot0, annot0, annot1; repeat rewrite M.union_empty_L;
          repeat rewrite M.union_assoc; try reflexivity.
    Qed.

    Lemma sigT_eq:
      forall {A} (a: A) (B: A -> Type) (v1 v2: B a),
        existT _ a v1 = existT _ a v2 ->
        v1 = v2.
    Proof. intros; inv H; apply Eqdep.EqdepTheory.inj_pair2 in H1; assumption. Qed.

    Theorem signIsEq :
      forall (l1 l2 : sigT SignT), {l1 = l2} + {l1 <> l2}.
    Proof.
      intros. destruct l1, l2.
      destruct (SignatureT_dec x x0).
      - induction e. destruct x, s, s0.
        destruct (isEq arg t t1). induction e.
        destruct (isEq ret t0 t2). induction e. left. reflexivity.
        right. unfold not. intros. apply sigT_eq in H.
        inversion H. apply n in H1. assumption.
        right. unfold not. intros. apply sigT_eq in H.
        inversion H. apply n in H1. assumption.
      - right. unfold not. intros. inversion H. apply n in H1.
        assumption.
    Qed.

    Definition hide (l: LabelT) :=
      Build_LabelT (annot l) (M.subtractKV signIsEq (defs l) (calls l))
                   (M.subtractKV signIsEq (calls l) (defs l)).

    Definition wellHidden (l: LabelT) := M.KeysDisj (defs l) (getCalls m) /\
                                         M.KeysDisj (calls l) (getDefs m).

    Inductive Step: UpdatesT -> LabelT -> Prop :=
      StepIntro ss (HSubsteps: substepsComb ss)
                (HWellHidden: wellHidden (hide (foldSSLabel ss))) :
        Step (foldSSUpds ss) (hide (foldSSLabel ss)).

    (* Another step semantics based on inductive definitions for Substeps *)
    Definition CanCombineUUL u (l: LabelT) (su: UpdatesT) scs sul :=
      M.Disj su u /\
      M.Disj scs (calls l) /\
      match annot l, sul with
        | Some _, Rle _ => False
        | _, Meth (Some a) => ~ M.In (attrName a) (defs l)
        | _, _ => True
      end.

    Definition CanCombineLabel (l1 l2: LabelT) :=
      M.Disj (defs l1) (defs l2) /\
      M.Disj (calls l1) (calls l2) /\
      match annot l1, annot l2 with
      | Some _, Some _ => False
      | _, _ => True
      end.

    Definition CanCombineUL (u1 u2: UpdatesT) (l1 l2: LabelT) :=
      M.Disj u1 u2 /\ CanCombineLabel l1 l2.

    Inductive SubstepsInd: UpdatesT -> LabelT -> Prop :=
    | SubstepsNil: SubstepsInd (M.empty _)
                               {| annot:= None; defs:= M.empty _; calls:= M.empty _ |}
    | SubstepsCons:
        forall u l,
          SubstepsInd u l ->
          forall su scs sul,
            Substep su sul scs ->
            CanCombineUUL u l su scs sul ->
            forall uu ll,
              uu = M.union u su ->
              ll = mergeLabel (getLabel sul scs) l ->
              SubstepsInd uu ll.

    Inductive SubstepsIndAnnot: UpdatesT -> LabelT -> list SubstepRec -> Prop :=
    | SubstepsAnnotNil:
        SubstepsIndAnnot (M.empty _)
                         {| annot:= None; defs:= M.empty _; calls:= M.empty _ |} nil
    | SubstepsAnnotCons:
        forall u l ss,
          SubstepsIndAnnot u l ss ->
          forall su scs sul
                 (Hss: Substep su sul scs),
            CanCombineUUL u l su scs sul ->
            SubstepsIndAnnot (M.union u su)
                             (mergeLabel (getLabel sul scs) l)
                             ({| upd:= su; unitAnnot:= sul; cms:= scs; substep:= Hss |} :: ss).

    Lemma canCombine_consistent_1:
      forall su sul scs (Hss: Substep su sul scs) ss,
        (forall s', In s' ss -> canCombine {| substep := Hss |} s') ->
        CanCombineUUL (foldSSUpds ss) (foldSSLabel ss) su scs sul.
    Proof.
      induction ss; intros; simpl in *.
      - repeat (constructor; simpl in *; try apply M.Disj_empty_2).
        destruct sul; intuition; try destruct a0; try destruct o0; try intros X;
          try (apply M.F.P.F.empty_in_iff in X); intuition.
      - assert (ez: forall s', In s' ss -> canCombine {| substep := Hss |} s') by
            (intros s' ins'; apply H; intuition).
        specialize (IHss ez); clear ez.
        assert (ez: canCombine {| substep := Hss |} a) by
            (apply H; intuition).
        clear H.
        destruct IHss as [condss1 [condss2 condss3]].
        destruct ez as [conda1 [conda2 [conda3 conda4]]].
        simpl in *.
        constructor.
        + apply M.Disj_union; intuition.
        + constructor.
          * unfold addLabelLeft, mergeLabel in *;
            destruct (foldSSLabel ss); simpl in *.
            apply M.Disj_union; intuition.
          * unfold addLabelLeft, mergeLabel in *.
            destruct (foldSSLabel ss); simpl in *.
            destruct a; simpl in *.
            destruct annot0, unitAnnot0, sul; intuition.
            { destruct o2; intuition.
              destruct o1; intuition.
              destruct a0.
              rewrite M.union_add in H.
              rewrite M.union_empty_L in H.
              apply M.F.P.F.add_in_iff in H.
              destruct H; intuition.
              eapply conda2; eauto.
            }
            { destruct o1; intuition; 
              destruct conda3 as [x [y | z]]; discriminate.
            }
            { destruct o1; intuition.
              destruct o0; intuition.
              destruct a0.
              rewrite M.union_add in H.
              rewrite M.union_empty_L in H.
              apply M.F.P.F.add_in_iff in H.
              destruct H; intuition.
              eapply conda2; eauto.
            }
    Qed.

    Lemma unionCanCombineUUL u l su scs sul a:
      CanCombineUUL (M.union u (upd a))
                      (addLabelLeft l a) su scs sul ->
      CanCombineUUL u l su scs sul.
    Proof.
      intros [cond1 [cond2 cond3]].
      apply M.Disj_union_1 in cond1.
      unfold addLabelLeft, mergeLabel in cond2.
      destruct (getSLabel a).
      destruct l; simpl in *.
      apply M.Disj_union_2 in cond2.
      constructor; intuition; simpl in *.
      destruct (unitAnnot a), annot1, sul; intuition.
      destruct o2; intuition.
      destruct o0; intuition.
      destruct a1; intuition.
      rewrite M.union_add, M.union_empty_L, M.F.P.F.add_in_iff in cond3; intuition.
      destruct o1; intuition.
      destruct o0; intuition.
      destruct a1; intuition.
      rewrite M.union_add, M.union_empty_L, M.F.P.F.add_in_iff in cond3; intuition.
    Qed.

    Lemma canCombine_consistent_2:
      forall su sul scs (Hss: Substep su sul scs) ss,
        CanCombineUUL (foldSSUpds ss) (foldSSLabel ss) su scs sul ->
        (forall s', In s' ss -> canCombine {| substep := Hss |} s').
    Proof.
      induction ss; intros; simpl in *.
      - intuition.
      - destruct H0.
        + destruct H as [cond1 [cond2 cond3]].
          subst.
          unfold addLabelLeft, mergeLabel in *; case_eq (foldSSLabel ss); intros.
          rewrite H in *.
          case_eq (getSLabel s'); intros.
          simpl in *.
          apply M.Disj_union_2 in cond1.
          apply M.Disj_union_1 in cond2.
          constructor; intuition; simpl in *.
          * rewrite H1, H2, H3 in *; intuition.
            destruct annot0, y.
            rewrite M.union_add, M.union_empty_L, M.F.P.F.add_in_iff in cond3; intuition.
            rewrite M.union_add, M.union_empty_L, M.F.P.F.add_in_iff in cond3; intuition.
          * destruct annot0, (unitAnnot s'), sul; intuition;
            eexists; intuition.
        + apply (IHss (unionCanCombineUUL _ _ _ H)); intuition.
    Qed.

    Lemma canCombine_consistent:
      forall su sul scs (Hss: Substep su sul scs) ss,
        (forall s', In s' ss -> canCombine {| substep := Hss |} s') <->
        CanCombineUUL (foldSSUpds ss) (foldSSLabel ss) su scs sul.
    Proof.
      intros; constructor.
      apply canCombine_consistent_1; intuition.
      apply canCombine_consistent_2; intuition.
    Qed.

    Lemma substepsComb_substepsInd:
      forall ss,
        substepsComb ss ->
        SubstepsInd (foldSSUpds ss) (foldSSLabel ss).
    Proof.
      induction 1; simpl in *; [constructor|].

      destruct s as [su sul scs Hss]; simpl in *.
      econstructor; eauto.
      eapply canCombine_consistent; eauto.
    Qed.

    Lemma substepsInd_substepsComb:
      forall u l,
        SubstepsInd u l ->
        exists ss, SubstepsIndAnnot u l ss /\
                   substepsComb ss /\
                   u = foldSSUpds ss /\ l = foldSSLabel ss.
    Proof.
      induction 1.
      - eexists; repeat split; constructor.
      - destruct IHSubstepsInd as [ss [? [? [? ?]]]]; subst.
        exists ({| substep:= H0 |} :: ss); split.
        + constructor; auto.
        + repeat split.
          constructor; auto.
          apply canCombine_consistent; auto.
    Qed.

    Inductive StepInd: UpdatesT -> LabelT -> Prop :=
    | StepIndIntro: forall u l (HSubSteps: SubstepsInd u l)
                           (HWellHidden: wellHidden (hide l)),
                      StepInd u (hide l).

    Lemma step_consistent:
      forall u l, Step u l <-> StepInd u l.
    Proof.
      split; intros.
      - inv H; constructor; auto.
        apply substepsComb_substepsInd; auto.
      - inv H.
        apply substepsInd_substepsComb in HSubSteps.
        destruct HSubSteps as [ss [? [? [? ?]]]]; subst.
        econstructor; eauto.
    Qed.

  End GivenOldregs.

  Inductive Multistep: RegsT -> RegsT -> list LabelT -> Prop :=
  | NilMultistep o1 o2: o1 = o2 -> Multistep o1 o2 nil
  | Multi o a n (HMultistep: Multistep o n a)
          u l (HStep: Step n u l):
      Multistep o (M.union u n) (l :: a).

  Definition initRegs (init: list RegInitT): RegsT :=
    makeMap (fullType type) evalConstFullT init.
  Hint Unfold initRegs.

  Lemma initRegs_eq:
    forall r1 r2,
      NoDup (namesOf r1) ->
      NoDup (namesOf r2) ->
      EquivList r1 r2 ->
      initRegs r1 = initRegs r2.
  Proof.
    unfold initRegs; intros; M.ext y.
    do 2 (rewrite makeMap_find; auto).
    remember (getAttribute y r1) as yr1.
    remember (getAttribute y r2) as yr2.
    destruct yr1, yr2.
    - assert (a = a0).
      { pose proof (getAttribute_Some_name _ _ Heqyr1).
        apply getAttribute_Some_body in Heqyr1.
        pose proof (getAttribute_Some_name _ _ Heqyr2).
        apply getAttribute_Some_body in Heqyr2.
        inv H1; apply in_NoDup_attr with (attrs:= r2); auto.
      }
      subst; auto.
    - exfalso.
      apply getAttribute_Some in Heqyr1.
      apply getAttribute_None in Heqyr2.
      elim Heqyr2.
      inv H1; apply SubList_map with (f:= @attrName _) in H2; auto.
    - exfalso.
      apply getAttribute_None in Heqyr1.
      apply getAttribute_Some in Heqyr2.
      elim Heqyr1.
      inv H1; apply SubList_map with (f:= @attrName _) in H3; auto.
    - auto.
  Qed.

  Definition LabelSeqT := list LabelT.

  Inductive Behavior: RegsT -> LabelSeqT -> Prop :=
  | BehaviorIntro a n (HMultistepBeh: Multistep (initRegs (getRegInits m)) n a):
      Behavior n a.
End GivenModule.

Fixpoint CanCombineLabelSeq (ll1 ll2: list LabelT) :=
  match ll1, ll2 with
  | nil, nil => True
  | l1 :: ll1', l2 :: ll2' =>
    CanCombineLabel l1 l2 /\ CanCombineLabelSeq ll1' ll2'
  | _, _ => False (* forces the same length *)
  end.

Definition equivalentLabel p l1 l2 :=
  p (defs l1) = defs l2 /\
  p (calls l1) = calls l2 /\
  match annot l1, annot l2 with
    | Some _, Some _ => True
    | None, None => True
    | _, _ => False
  end.

Inductive equivalentLabelSeq p: LabelSeqT -> LabelSeqT -> Prop :=
| NilEquivalentSeq: equivalentLabelSeq p nil nil
| EquivalentSeq x xs y ys: equivalentLabel p x y -> equivalentLabelSeq p xs ys ->
                           equivalentLabelSeq p (x :: xs) (y :: ys).

Definition reachable o m := exists sigma, Behavior m o sigma.

Definition traceRefines p m1 m2 :=
  forall s1 sig1, Behavior m1 s1 sig1 ->
                  exists s2 sig2, Behavior m2 s2 sig2 /\
                             equivalentLabelSeq p sig1 sig2.

Section MapSet.
  Variable A: Type.
  Variable p: M.key -> A -> option A.

  Definition rmModify k v m := match p k v with
                                 | None => m
                                 | Some v' => M.add k v' m
                               end.
  Definition liftToMap1 s :=
    M.fold rmModify s (M.empty _).

End MapSet.

Definition idElementwise A (k: M.key) (v: A) := Some v.

Notation "ma '<<=[' p ']' mb" :=
  (traceRefines (liftToMap1 p) ma mb) (at level 100, format "ma  <<=[  p  ]  mb").
Notation "ma '<<==' mb" :=
  (ma <<=[@idElementwise _] mb) (at level 100, format "ma  <<==  mb").
Notation "ma '<<==>>' mb" :=
  (ma <<== mb /\ mb <<== ma)
    (at level 100, format "ma  <<==>>  mb").


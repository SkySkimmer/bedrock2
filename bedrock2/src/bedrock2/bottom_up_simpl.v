Require Import coqutil.Ltac2Lib.Ltac2.
Require Import coqutil.Ltac2Lib.Failf coqutil.Ltac2Lib.rdelta.
Require Import Coq.ZArith.ZArith. Local Open Scope Z_scope.
Require Import Coq.micromega.Lia.
Require Import coqutil.Word.Interface coqutil.Word.Properties.
Require Import coqutil.Datatypes.ZList.
Require Import coqutil.Tactics.Tactics.
Require Import coqutil.Tactics.ltac_list_ops.
Require Import coqutil.Tactics.rdelta.
Require Import coqutil.Tactics.foreach_hyp.
Require Import bedrock2.cancel_div.

Ltac2 rec is_positive_literal(e: constr): bool :=
  lazy_match! e with
  | xI ?p => is_positive_literal p
  | xO ?p => is_positive_literal p
  | xH => true
  | _ => false
  end.

(* Note: Not the same as Coq.setoid_ring.InitialRing.isZcst, because
   isZcst considers (Z.of_nat n) and (Z.of_N n) constant if n is constant *)
Ltac2 is_Z_literal(n: constr): bool :=
  lazy_match! n with
  | 0 => true
  | Z.pos ?p => is_positive_literal p
  | Z.neg ?p => is_positive_literal p
  | _ => false
  end.

(* needed for compatibility with simplification strategies that choose not
   to simplify powers of 2 *)
Ltac2 is_Z_const(n: constr): bool :=
  lazy_match! n with
  | 2 ^ ?x => is_Z_literal x
  | _ => is_Z_literal n
  end.

Ltac2 rec is_nat_const(n: constr): bool :=
  lazy_match! n with
  | O => true
  | S ?p => is_nat_const p
  | _ => false
  end.

(* Two aliases of eq_refl, one that means "nothing was simplified", and one that
   means "some conversion to x happened" *)
Definition eq_nop[A: Type](x: A): x = x := eq_refl.
Definition eq_conv[A: Type](x: A): x = x := eq_refl.

(* To be treated opaquely and only manipulated through the API that follows.
   Alternative representations to try out:
   - Ltac2 records
   - uconstr
   - resulting term of simplification as constr, proof term as uconstr or custom type *)
Ltac2 Type res := {
  proof: constr
}.

Ltac2 new_term(r: res): constr :=
  (* extra parentheses needed because of https://github.com/coq/coq/issues/16432 *)
  lazy_match! Constr.type (r.(proof)) with
  | _ = ?x => x
  end.

Ltac2 eq_proof(r: res): constr := r.(proof).

Ltac2 did_something(r: res): bool :=
  lazy_match! r.(proof) with
  | eq_nop _ => false
  | _ => true
  end.

Ltac2 is_convertible(r: res): bool :=
  lazy_match! r.(proof) with
  | eq_nop _ => true
  | eq_conv _ => true
  | _ => false
  end.

Ltac2 res_convertible(new_term: constr): res :=
  { proof := '(eq_conv $new_term) }.

(* new_term must be convertible to the rhs of eq_proof's type *)
Ltac2 res_rewrite_to(new_term: constr)(eq_proof: constr): res :=
  { proof := '(eq_trans $eq_proof (@eq_refl _ $new_term)) }.

Ltac2 res_rewrite(eq_proof: constr): res :=
  { proof := eq_proof }.

Ltac2 res_nothing_to_simpl(original_term: constr): res :=
  { proof := '(eq_nop $original_term) }.

(* original: term of shape (f a)
   f: constr
   r: result whose lhs is a *)
Ltac2 lift_res1(original: constr)(f: constr)(r: res): res :=
  if did_something r then
    let t := new_term r in
    if is_convertible r then
      res_convertible '($f $t)
    else
      let pf := eq_proof r in res_rewrite '(@f_equal _ _ $f _ $t $pf)
  else res_nothing_to_simpl original.

(* If we just used f_equal with f := (fun x => g (h x)), the RHS would be
   ((fun x => g (h x)) a') instead of (g (h a')). *)
Lemma f_equal11[A B C: Type](h: A -> B)(g: B -> C)[a a': A]: a = a' -> g (h a) = g (h a').
Proof. exact (@f_equal A C (fun x => g (h x)) a a'). Qed.

(* original: term of shape (f (g a))
   f: constr
   g: constr
   r: result whose lhs is a *)
Ltac2 lift_res11(original: constr)(f: constr)(g: constr)(r: res): res :=
  if did_something r then
    let t := new_term r in
    if is_convertible r then
      res_convertible '($f ($g $t))
    else
      let pf := eq_proof r in res_rewrite '(f_equal11 $f $g $pf)
  else res_nothing_to_simpl original.

(* original: term of shape (f a1 a2)
   f: constr
   r1: result whose lhs is a1
   r2: result whose lhs is a2 *)
Ltac2 lift_res2(original: constr)(f: constr)(r1: res)(r2: res): res :=
  let t1 := new_term r1 in
  let t2 := new_term r2 in
  if did_something r1 then
    if is_convertible r1 then
      if is_convertible r2 then
        res_convertible '($f $t1 $t2)
      else
        let pf1 := eq_proof r1 in
        let pf2 := eq_proof r2 in
        res_rewrite '(@f_equal2 _ _ _ $f _ $t1 _ $t2 $pf1 $pf2)
    else
      let pf1 := eq_proof r1 in
      let pf2 := eq_proof r2 in
      res_rewrite '(@f_equal2 _ _ _ $f _ $t1 _ $t2 $pf1 $pf2)
  else if did_something r2 then
    if is_convertible r2 then
      res_convertible '($f $t1 $t2)
    else
      let pf2 := eq_proof r2 in
      res_rewrite '(@f_equal _ _ ($f $t1) _ $t2 $pf2)
  else
    res_nothing_to_simpl original.

Lemma app_cong[A B: Type][f g: A -> B][x y: A]: f = g -> x = y -> f x = g y.
Proof. intros. subst. reflexivity. Qed.

(* original: term of shape (f a)
   r1: result whose lhs is f
   r2: result whose lhs is a *)
Ltac2 lift_res_app(original: constr)(r1: res)(r2: res): res :=
  let t1 := new_term r1 in
  let t2 := new_term r2 in
  if did_something r1 then
    if is_convertible r1 then
      if is_convertible r2 then
        res_convertible '($t1 $t2)
      else
        let pf1 := eq_proof r1 in
        let pf2 := eq_proof r2 in
        res_rewrite '(@app_cong _ _ _ $t1 _ $t2 $pf1 $pf2)
    else
      let pf1 := eq_proof r1 in
      let pf2 := eq_proof r2 in
      res_rewrite '(@app_cong _ _ _ $t1 _ $t2 $pf1 $pf2)
  else if did_something r2 then
    if is_convertible r2 then
      res_convertible '($t1 $t2)
    else
      let pf2 := eq_proof r2 in
      res_rewrite '(@f_equal _ _ $t1 _ $t2 $pf2)
  else
    res_nothing_to_simpl original.

Ltac2 chain_rewrite_res(r1: res)(r2: res): res :=
  let t1 := new_term r1 in
  let pf1 := eq_proof r1 in
  let t2 := new_term r2 in
  let pf2 := eq_proof r2 in
  res_rewrite '(@eq_trans _ _ $t1 $t2 $pf1 $pf2).

(* assumes rhs of r1 equals lhs of r2 *)
Ltac2 chain_res(r1: res)(r2: res): res :=
  if did_something r1 then
    if did_something r2 then
      if is_convertible r1 then r2
      else
        if is_convertible r2
        then res_rewrite_to (new_term r2) (eq_proof r1)
        else chain_rewrite_res r1 r2
    else r1
  else r2.

(* marker to make proof terms more readable *)
Definition xlia(P: Prop){pf: P}: P := pf.

Ltac2 mutable bottom_up_simpl_sidecond_hook () :=
  ltac1:(lia). (* OR xlia zchecker if already zified *)

(* local_X_simpl tactics:
   Given a term with already simplified subterms, produce new simplified term and
   equality proof (or set flag indicating that it's convertible).
   Failing means no simplification opportunity. *)

(* inh: inhabited instance
   l:   any number of cons followed by nil or an abstract tail
   i:   fully simplified Z literal
   Returns an element or a List.get with a smaller index *)
Ltac2 rec convertible_list_get inh l i :=
  lazy_match! l with
  | nil => '(@Inhabited.default _ $inh)
  | cons ?h ?t =>
      lazy_match! i with
      | Z0 => h
      | Zpos _ => let j := eval cbv in (Z.pred $i) in convertible_list_get inh t j
      | Zneg _ => '(@Inhabited.default _ $inh)
      end
  | _ => '(@List.get _ $inh $l $i)
  end.

(* l:   any number of cons followed by nil or an abstract tail
   i:   fully simplified Z literal
   Returns a prefix of l or a few cons followed by a List.upto with a smaller index,
   eg (a :: b :: c :: l)[:5] --> a :: b :: c :: (l[:2]) *)
Ltac2 rec convertible_list_upto(i: constr)(l: constr): constr :=
  lazy_match! l with
  | nil => l
  | @cons ?tp ?h ?t =>
      lazy_match! i with
      | Zpos _ => let j := eval cbv in (Z.pred $i) in
                  let r := convertible_list_upto j t in
                  '(@cons $tp $h $r)
      | _ => '(@nil $tp)
      end
  | _ => lazy_match! i with
         | Zpos _ => '(List.upto $i $l)
         | Z0 => '(@nil _)
         | Zneg _ => '(@nil _)
         end
  end.

(* l:   any number of cons followed by nil or an abstract tail
   i:   fully simplified Z literal
   Returns a suffix of l or a List.from with a smaller index *)
Ltac2 rec convertible_list_from i l :=
  lazy_match! l with
  | nil => l
  | @cons ?tp ?h ?t =>
      lazy_match! i with
      | Zpos _ => let j := eval cbv in (Z.pred $i) in convertible_list_from j t
      | _ => l
      end
  | _ => lazy_match! i with
         | Zpos _ => '(List.from $i $l)
         | Z0 => l
         | Zneg _ => l
         end
  end.

(* only works if l1 is made up of just cons and nil *)
Ltac2 rec prepend_concrete_list l1 l2 :=
  lazy_match! l1 with
  | cons ?h ?t => let r := prepend_concrete_list t l2 in '(cons $h $r)
  | nil => l2
  end.

Ltac2 is_concrete_enough(i: constr)(l: constr)(is_nonpos_concrete_enough: bool): bool :=
  lazy_match! l with
  | nil => is_Z_literal i
  | cons _ _ => is_Z_literal i
  | _ => lazy_match! i with
         | Z0 => is_nonpos_concrete_enough
         | Zneg _ => is_nonpos_concrete_enough
         | _ => false
         end
  end.

Ltac2 non_ring_expr_size(e: constr): int :=
  lazy_match! e with
  | Zneg _ => 2
  | _ => if is_Z_const e then 1 else 2
  end.

Ltac2 rec ring_expr_size(e: constr): int :=
  let r1 x :=
    let s := ring_expr_size x in Int.add 1 s in
  let r2 x y :=
    let s1 := ring_expr_size x in let s2 := ring_expr_size y in Int.add 1 (Int.add s1 s2) in
  lazy_match! e with
  | Z.add ?x ?y => r2 x y
  | Z.sub ?x ?y => r2 x y
  | Z.mul ?x ?y => r2 x y
  | Z.opp ?x => r1 x
  | word.add ?x ?y => r2 x y
  | word.sub ?x ?y => r2 x y
  | word.mul ?x ?y => r2 x y
  | word.opp ?x => r1 x
  | word.of_Z ?x => non_ring_expr_size x
  | _ => non_ring_expr_size e
  end.

Ltac2 Type expr_kind := [ WordRingExpr | ZRingExpr | OtherExpr ].

Ltac2 expr_kind_eq k1 k2 :=
  match k1 with
  | WordRingExpr => match k2 with WordRingExpr => true | _ => false end
  | ZRingExpr    => match k2 with ZRingExpr    => true | _ => false end
  | OtherExpr    => match k2 with OtherExpr    => true | _ => false end
  end.

Ltac2 get_expr_kind(e: constr): expr_kind :=
  lazy_match! e with
  | Z.add _ _ => ZRingExpr
  | Z.sub _ _ => ZRingExpr
  | Z.mul _ _ => ZRingExpr
  | Z.opp _ => ZRingExpr
  | word.add _ _ => WordRingExpr
  | word.sub _ _ => WordRingExpr
  | word.mul _ _ => WordRingExpr
  | word.opp _ => WordRingExpr
  | _ => OtherExpr
  end.

(* To hide the ring_simplify proof when printing the proof term, and
   to provide a let so that the preprocessing of ring_simplify doesn't mess with
   the evar, while also making sure that the type as seen from the outside is a
   (_ = _) rather than a let. *)
Lemma ring_simplify_proof[A: Type](lhs rhs: A){pf: let x := rhs in lhs = x}: lhs = rhs.
Proof. exact pf. Qed.

Ltac2 ring_simplify_res_forcing_progress(e: constr): res :=
  let rhs := '(_) in
  res_rewrite '(@ring_simplify_proof _ $e $rhs
    (* to invoke ring_simplify, we need to switch to Ltac1 anyways, so we just do this
       whole line in Ltac1 *)
    ltac:(let x := fresh "x" in intro x; progress ring_simplify; subst x; reflexivity)).

Ltac2 ring_simplify_res_or_nothing_to_simpl(e: constr): res :=
  first_val [ ring_simplify_res_forcing_progress e
            | res_nothing_to_simpl e ].

Ltac2 local_ring_simplify(parent: expr_kind)(e: constr): res :=
  if expr_kind_eq (get_expr_kind e) parent then
    gfail "nothing to do here because parent will be ring_simplified too"
  else
    let r := ring_simplify_res_forcing_progress e in
    if Int.lt (ring_expr_size (new_term r)) (ring_expr_size e) then r
    else gfail "ring_simplify does not shrink the expression size".

(* TODO move *)
Ltac2 lia0 () := ltac1:(lia).
Ltac2 Notation lia := lia0 ().

Ltac2 eassumption0 () := ltac1:(eassumption).
Ltac2 Notation eassumption := eassumption0 ().

Module List.
  Import List.ZIndexNotations. Local Open Scope zlist_scope.

  (* Given `e` of type `list A`, returns `xss` of type `list (list A)` such that
     `List.apps xss` is convertible to `e`, and as long as possible.
     (Side question: What would it take to prove such a spec?) *)
  Ltac2 rec reify_apps e :=
    lazy_match! e with
    | List.app ?xs ?ys => let r := reify_apps ys in '(cons $xs $r)
    | _ => '([|$e|])
    end.

  Goal forall l: list Z, True.
    intros.
    lazy_match! reify_apps '([|1; 2|] ++ ([|3|] ++ [|4|]) ++ (l ++ [|5|])) with
    | [|[|1; 2|]; [|3|] ++ [|4|]; l; [|5|]|] => ()
    end.
  Abort.

  Section WithA.
    Context [A: Type].

    (* TODO begin move *)
    Lemma upto_app: forall (i: Z) (l1 l2 : list A),
        List.upto i (l1 ++ l2) = List.upto i l1 ++ List.upto (i - len l1) l2.
    Proof. unfold List.upto. intros. rewrite List.firstn_app. f_equal. f_equal. lia. Qed.

    (* Note: the symmetric version of this lemma, ie
         forall (i j: Z) (l: list A), i <= j -> l[:i][:j] = l[:i]
       is a special case of List.upto_pastend *)
    Lemma upto_upto_subsume: forall (i j: Z) (l: list A), j <= i -> l[:i][:j] = l[:j].
    Proof. unfold List.upto. intros. rewrite List.firstn_firstn. f_equal. lia. Qed.
    (* TODO end move *)

    (* Same as List.concat, but does not result in a trailing `++ nil` when unfolded *)
    Fixpoint apps(xss: list (list A)): list A :=
      match xss with
      | nil => nil
      | ys :: nil => ys
      | h :: t => h ++ apps t
      end.

    Lemma apps_concat: forall (xss: list (list A)), apps xss = List.concat xss.
    Proof.
      induction xss. 1: reflexivity.
      simpl. rewrite <- IHxss.
      destruct xss; try reflexivity.
      simpl. symmetry. apply List.app_nil_r.
    Qed.

    Definition cbn_app: list (list A) -> list (list A) -> list (list A) :=
      Eval unfold List.app in @List.app (list A).

    Lemma reassoc_app: forall (xss yss: list (list A)) (xs ys zs: list A),
        apps xss = xs ->
        apps yss = ys ->
        apps (cbn_app xss yss) = zs ->
        List.app xs ys = zs.
    Proof.
      intros. subst. rewrite 3apps_concat. change cbn_app with (@List.app (list A)).
      symmetry. apply List.concat_app.
    Qed.

    Definition cbn_firstn: nat -> list (list A) -> list (list A) :=
      Eval unfold List.firstn in @List.firstn (list A).

    Definition cbn_dropRight(n: nat)(ls: list (list A)): list (list A) :=
      Eval unfold List.length, Nat.sub, List.firstn in
        List.firstn (Nat.sub (List.length ls) n) ls.

    Definition cbn_skipn: nat -> list (list A) -> list (list A) :=
      Eval unfold List.skipn in @List.skipn (list A).

    Fixpoint cbn_len_sum(xss: list (list A)): Z :=
      match xss with
      | nil => 0
      | h :: t => len h + cbn_len_sum t
      end.

    (* alternative to try out: zipper style: reversed left list of lists *)

    Lemma upto_apps0: forall n i (xs: list A) (xss: list (list A))
                            (ys: list A) (yss: list (list A)),
        i <= cbn_len_sum (cbn_firstn n xss) ->
        cbn_firstn n xss = yss ->
        apps xss = xs ->
        apps yss = ys ->
        List.upto i xs = List.upto i ys.
    Proof.
      intros. subst. rewrite 2apps_concat. revert i xss H.
      induction n; intros; simpl in *.
      - rewrite 2List.upto_beginning; trivial.
      - destruct xss. 1: reflexivity.
        simpl in *.
        rewrite 2upto_app. f_equal. apply IHn. lia.
    Qed.

    Lemma upto_apps: forall n i (xs: list A) (xss: list (list A))
                            (ys: list A) (yss: list (list A)),
        i <= cbn_len_sum (cbn_dropRight n xss) ->
        cbn_dropRight n xss = yss ->
        apps xss = xs ->
        apps yss = ys ->
        List.upto i xs = List.upto i ys.
    Proof. unfold cbn_dropRight. intros. eapply upto_apps0; eassumption. Qed.
  End WithA.
End List.

Section SimplListLemmas.
  Import List.ZIndexNotations. Local Open Scope zlist_scope.
  Context [A: Type].

  (* A list slice can be expressed in two ways:
     - indexed: xs[i:j], which is shorthand for xs[:j][i:]
     - sized: xs[i:][:n]
     Which one we prefer depends on the AST size of the second number:
     Sometimes, it's easier to express the end index, but sometimes, it's
     easier to express the size. *)

  Lemma indexed_slice_to_sized_slice: forall (l: list A) i j n,
      0 <= i <= j ->
      j - i = n ->
      l[i:j] = l[i:][:n].
  Proof.
    intros. subst. rewrite List.from_upto_comm by lia. f_equal. f_equal. lia.
  Qed.

  Lemma sized_slice_to_indexed_slice: forall (l: list A) i n j,
      0 <= i /\ 0 <= n ->
      i + n = j ->
      l[i:][:n] = l[i:j].
  Proof.
    intros * [? ?] **. subst. apply List.from_upto_comm; assumption.
  Qed.
End SimplListLemmas.

(* Sometimes, `gfirst [ t1 | t2 ]` is not quite what we want because if both t1 and t2
   fail, it swallows the error of t2 and just returns `Tactic_failure (None)`.
   We want a fallback/orelse/try-catch/single-success plus/|/try-else.
   Experimental syntax: `try t1 else t2`. *)

(* Like orelse, but t2 ignores the exception of t1 *)
Ltac2 try_else t1 t2 := orelse t1 (fun _ => t2 ()).

(* if-then-else also uses tactic(5) *)
Ltac2 Notation "try" t1(thunk(tactic(5))) "else" t2(thunk(tactic(5))) := try_else t1 t2.

Ltac2 Notation "try" t1(thunk(tactic(5))) := try0 t1.

Goal True.
  try fail "nope".
  try fail "ooh" else pose 1.
  try (pose 2; fail) else pose 3.
  try () else pose 1; pose 2.
  let r := try '(1%nat + 1%Z) else '(tt) in pose $r.
  Fail let r := try '(1%nat + 1%Z) else 2 in pose $r.
  Fail try fail "msg1" else fail "msg2". (* msg2 *)
  Fail first [ fail "msg1" | fail "msg2" ]. (* Tactic_failure (None) *)
Abort.

(* gen_stmt: ltac function taking a nat and returning a Prop
   tac: tactic to prove stmt, takes a dummy unit
   lower: min n to try
   upper: one more than max n to try
   Returns the proof term for the biggest possible n. *)
Ltac2 max_n_st(gen_stmt: constr -> constr)(tac: unit -> unit)
              (lower: constr)(upper: constr): constr :=
  let rec loop n :=
    let stmt := gen_stmt n in
    try '(ltac2:(tac ()) : $stmt)
    else if Constr.equal n lower then
           gfail "stmt does not hold for any n within the bounds"
         else
           lazy_match! n with
           | S ?m => loop m
           | _ => anomaly "expected a nat above %t, got %t" lower n
           end in
  lazy_match! upper with
  | S ?n => loop n
  | _ => anomaly "upper should be a nonzero nat"
  end.

Goal forall (b: nat), b = 12%nat -> (3 * 3 < b)%nat.
  intros.
  let tac := (fun _ =>
    lazy_match! goal with
    | [ |- ?g ] => () (* printf "goal: %t" g *)
    end;
    cbn; lia) in
  let pf := max_n_st (fun n => '(($n * $n < b)%nat)) tac '2%nat '7%nat in
  pose $pf as A.
  exact A.
Succeed Qed. Abort.

Ltac2 rec list_length_as_nat(l: constr): constr :=
  lazy_match! l with
  | nil => '(0%nat)
  | cons _ ?tail => let r := list_length_as_nat tail in '((S $r))
  end.

(* returns a proof whose LHS is (List.upto i l) and an RHS where the upto has been
   pushed down as far as nicely possible *)
Ltac2 rec push_down_upto(force_progress: bool)(treat_app: bool)
                        (tp: constr)(i: constr)(l: constr): res :=
  (*non-lazy*)match! l with
  | List.app _ _ =>
      if treat_app then
        let xss := List.reify_apps l in
        let le_pf := max_n_st (* might fail *)
          (fun n => '($i <= List.cbn_len_sum (List.cbn_dropRight $n $xss)))
          (fun _ => cbn [List.cbn_len_sum List.cbn_dropRight];
                         bottom_up_simpl_sidecond_hook ())
          '1%nat
          (list_length_as_nat xss) in
        (* n=0 (nothing to do) and n=list_length xss (result is nil) not handled here *)
        let upto_apps_pf := '(List.upto_apps _ $i $l $xss _ _ $le_pf
                                      ltac2:(cbn [List.cbn_dropRight]; reflexivity)
                                      eq_refl
                                      ltac2:(cbn [List.apps]; reflexivity)) in
        let res_upto_apps := res_rewrite upto_apps_pf in
        let res_rec := push_down_upto false false tp i (new_term res_upto_apps) in
        chain_res res_upto_apps res_rec
      else gfail "try next match branch"
    | List.from ?j ?l =>
      let n := i in (* sized slice of size n: l[j:][:n] *)
      let r_sum := ring_simplify_res_or_nothing_to_simpl '(Z.add $j $n) in
      let sum := new_term r_sum in
      if Int.lt (ring_expr_size sum) (ring_expr_size n) then
        let pf_sum := eq_proof r_sum in
        res_rewrite '(sized_slice_to_indexed_slice $l $j $n $sum
                              ltac2:(bottom_up_simpl_sidecond_hook) $pf_sum)
      else gfail "ring_simplify does not shrink the expression size"
  | List.upto ?j ?l =>
      let r1 := res_rewrite '(List.upto_upto_subsume $j $i $l
                                      ltac2:(bottom_up_simpl_sidecond_hook ())) in
      let r2 := push_down_upto false true tp i l in
      chain_res r1 r2
  | _ => if is_concrete_enough i l true then
           let l' := convertible_list_upto i l in res_convertible l'
         else
           try res_rewrite '(List.upto_beginning $l $i
                                  ltac2:(bottom_up_simpl_sidecond_hook ()))
           else res_rewrite '(List.upto_pastend $l $i
                                      ltac2:(bottom_up_simpl_sidecond_hook ()))
  | _ => if force_progress
         then gfail "no progress"
         else res_nothing_to_simpl '(@List.upto $tp $i $l)
  end.

Ltac2 local_zlist_simpl(e: constr): res :=
  match! e with
  | @List.upto ?tp ?i ?l => push_down_upto true true tp i l
  | @List.get _ ?inh ?l ?i =>
      if is_concrete_enough i l false then
        res_convertible (convertible_list_get inh l i)
      else gfail "try next branch"
  | @List.repeatz ?tp _ Z0 => res_convertible '(@nil $tp)
  | List.app ?xs nil => res_rewrite '(List.app_nil_r $xs)
  | List.app ?l1 ?l2 => res_convertible (prepend_concrete_list l1 l2)
  | List.app ?xs ?ys =>
      (* TODO also check if rightmost list in xss can be merged with leftmost list in yss *)
      let xss := List.reify_apps xs in
      lazy_match! xss with
      | cons _ nil => gfail "no need to reassoc"
      | cons _ (cons _ _) =>
          let yss := List.reify_apps ys in
          let zs := eval cbn [List.apps List.cbn_app] in
                             (List.apps (List.cbn_app $xss $yss)) in
          res_rewrite '(List.reassoc_app $xss $yss $xs $ys $zs eq_refl eq_refl eq_refl)
      | _ => anomaly "List.reify_apps returned result of unexpected shape %t" xss
      end
  (* TODO Doesn't do anything for ((xs ++ ys) ++ zs)[i:] if i points into ys,
     and the subtraction created by from_app_discard_l should be simplified
     immediately rather than only in the next outermost iteration *)
  | List.from ?i (List.app ?l1 ?l2) =>
      res_rewrite '(List.from_app_discard_l $l1 $l2 $i
                            ltac2:(bottom_up_simpl_sidecond_hook ()))
  | List.from ?i (List.upto ?j ?l) =>
      let r_diff := ring_simplify_res_or_nothing_to_simpl '(Z.sub $j $i) in
      let diff := new_term r_diff in
      if Int.lt (ring_expr_size diff) (ring_expr_size j) then
        let pf_diff := eq_proof r_diff in
        let rhs := '(List.upto $diff (List.from $i $l)) in
        let lem1 := '(indexed_slice_to_sized_slice $l $i $j $diff) in
        res_rewrite '(indexed_slice_to_sized_slice $l $i $j $diff
                              ltac2:(bottom_up_simpl_sidecond_hook ()) $pf_diff)
      else gfail "ring_simplify does not shrink the expression size"
  | List.from ?i ?l =>
      if is_concrete_enough i l true then
        res_convertible (convertible_list_from i l)
      else
        match! l with
          | List.from ?j ?ll =>
              res_rewrite '(List.from_from $ll $j $i
                                    ltac2:(bottom_up_simpl_sidecond_hook ())
                                    ltac2:(bottom_up_simpl_sidecond_hook ()))
          | _ => res_rewrite '(List.from_beginning $l $i
                                       ltac2:(bottom_up_simpl_sidecond_hook ()))
          | _ => res_rewrite '(List.from_pastend $l $i
                                       ltac2:(bottom_up_simpl_sidecond_hook ()))
        end
  end.

Ltac2 is_unary_Z_op(op: constr): bool :=
  lazy_match! op with
  | Z.of_nat => true
  | Z.to_nat => true
  | Z.succ => true
  | Z.pred => true
  | Z.opp => true
  | Z.log2 => true
  | Z.log2_up => true
  | _ => false
  end.

Ltac2 is_unary_nat_op(op: constr): bool :=
  lazy_match! op with
  | Nat.succ => true
  | Nat.pred => true
  | _ => false
  end.

Ltac2 is_binary_Z_op(op: constr): bool :=
  lazy_match! op with
  | Z.add => true
  | Z.sub => true
  | Z.mul => true
  | Z.div => true
  | Z.modulo => true
  | Z.quot => true
  | Z.rem => true
  | Z.pow => true
  | Z.shiftl => true
  | Z.shiftr => true
  | Z.land => true
  | Z.lor => true
  | Z.lxor => true
  | Z.ldiff => true
  | Z.clearbit => true
  | Z.setbit => true
  | Z.min => true
  | Z.max => true
  | _ => false
  end.

Ltac2 is_binary_nat_op(op: constr): bool :=
  lazy_match! op with
  | Nat.add => true
  | Nat.sub => true
  | Nat.mul => true
  | Nat.div => true
  | Nat.min => true
  | Nat.max => true
  | _ => false
  end.

Ltac2 local_ground_number_simpl(e: constr): res :=
  lazy_match! e with
  | ?f ?x ?y =>
      if Constr.is_const f then
        if is_binary_Z_op f then
          lazy_match! e with
          | Z.pow 2 _ => gfail "not simplifying powers of 2"
          | _ => if is_Z_const x && is_Z_const y
                 then res_convertible (eval cbv in $e)
                 else gfail "not constant"
          end
        else if is_binary_nat_op f && is_nat_const x && is_nat_const y
             then res_convertible (eval cbv in $e)
             else gfail "not constant"
      else gfail "not constant"
  | ?f ?x =>
      if Constr.is_const f &&
           (is_unary_Z_op f && is_Z_const x || is_unary_nat_op f && is_nat_const x)
      then res_convertible (eval cbv in $e)
      else gfail "not constant"
  end.

Goal forall (a b c: Z), a + b - 2 * a = c -> -a + b = c.
Proof.
  intros.
  lazy_match! Constr.type 'H with
  | ?e = _ =>
      let r := local_ring_simplify OtherExpr e in
      let n := new_term r in
      let pf := eq_proof r in
      eassert ($n = c) as H' by (etransitivity > [symmetry; exact $pf | exact H])
  end.
  exact H'.
Succeed Qed. Abort.

Goal forall (a b: Z), True.
Proof.
  intros.
  Fail let e := '(a + b) in let r := local_ring_simplify OtherExpr e in ().
  (* nothing to simplify (progress fails) *)
Abort.

Ltac2 mutable rec is_substitutable_rhs(rhs: constr): bool :=
  Constr.is_var rhs ||
  Constr.is_const rhs ||
  is_Z_const rhs ||
  lazy_match! rhs with
  | word.of_Z ?x => is_substitutable_rhs x
  | word.unsigned ?x => is_substitutable_rhs x
  | _ => false
  end.

Ltac2 local_subst_small_rhs(e: constr): res :=
  let rhs := progress_rdelta_var e in
  if is_substitutable_rhs rhs then res_convertible rhs else gfail "not substitutable".

Ltac2 local_nonring_nonground_Z_simpl e :=
  lazy_match! e with
  | Z.div ?x 1 => res_rewrite '(Z.div_1_r $x)
  | Z.div ?x ?d =>
      let x_eq_prod_pf := cancel_div_rec d x in
      res_rewrite '(cancel_div_done $d $x _
                            ltac2:(bottom_up_simpl_sidecond_hook ()) $x_eq_prod_pf)
  end.

Module word.
  Section WithWord.
    Context [width] [word : word.word width] [word_ok : word.ok word].

    (* Pushing down word.unsigned: *)

    Lemma unsigned_of_Z_modwrap: forall (z: Z),
        word.unsigned (word.of_Z (word := word) z) = z mod 2 ^ width.
    Proof. apply word.unsigned_of_Z. Qed.

    Lemma unsigned_opp_eq_nowrap: forall [a: word] [ua: Z],
        word.unsigned a = ua ->
        ua <> 0 ->
        word.unsigned (word.opp a) = 2 ^ width - ua.
    Proof. intros. subst. apply word.unsigned_opp_nowrap. assumption. Qed.
    (* and lemma word.unsigned_opp_0 can be used as-is *)

    Lemma unsigned_add_eq_nowrap: forall [a b: word] [ua ub: Z],
        word.unsigned a = ua ->
        word.unsigned b = ub ->
        ua + ub < 2 ^ width ->
        word.unsigned (word.add a b) = ua + ub.
    Proof. intros. subst. apply word.unsigned_add_nowrap. assumption. Qed.

    Lemma unsigned_sub_eq_nowrap: forall [a b: word] [ua ub: Z],
        word.unsigned a = ua ->
        word.unsigned b = ub ->
        0 <= ua - ub ->
        word.unsigned (word.sub a b) = ua - ub.
    Proof. intros. subst. apply word.unsigned_sub_nowrap. assumption. Qed.

    Lemma unsigned_mul_eq_nowrap: forall [a b: word] [ua ub: Z],
        word.unsigned a = ua ->
        word.unsigned b = ub ->
        ua * ub < 2 ^ width ->
        word.unsigned (word.mul a b) = ua * ub.
    Proof. intros. subst. apply word.unsigned_mul_nowrap. assumption. Qed.

    (* Pushing down word.of_Z: *)

    (* lemma word.of_Z_unsigned can be used as-is *)

    Lemma of_Z_mod: forall (z: Z),
        word.of_Z (word := word) (z mod 2 ^ width) = word.of_Z (word := word) z.
    Proof.
      intros. change (z mod 2 ^ width) with (word.wrap z).
      rewrite <- word.unsigned_of_Z. apply word.of_Z_unsigned.
    Qed.

    Lemma of_Z_mod_eq: forall [z: Z] [w: word],
        word.of_Z z = w ->
        word.of_Z (z mod 2 ^ width) = w.
    Proof. intros. subst. apply of_Z_mod. Qed.

    Lemma of_Z_opp_eq: forall [z: Z] [w: word],
        word.of_Z z = w ->
        word.of_Z (- z) = word.opp w.
    Proof. intros. subst. apply word.ring_morph_opp. Qed.

    Lemma of_Z_add_eq: forall [z1 z2: Z] [w1 w2: word],
        word.of_Z z1 = w1 ->
        word.of_Z z2 = w2 ->
        word.of_Z (z1 + z2) = word.add w1 w2.
    Proof. intros. subst. apply word.ring_morph_add. Qed.

    Lemma of_Z_sub_eq: forall [z1 z2: Z] [w1 w2: word],
        word.of_Z z1 = w1 ->
        word.of_Z z2 = w2 ->
        word.of_Z (z1 - z2) = word.sub w1 w2.
    Proof. intros. subst. apply word.ring_morph_sub. Qed.

    Lemma of_Z_mul_eq: forall [z1 z2: Z] [w1 w2: word],
        word.of_Z z1 = w1 ->
        word.of_Z z2 = w2 ->
        word.of_Z (z1 * z2) = word.mul w1 w2.
    Proof. intros. subst. apply word.ring_morph_mul. Qed.

  End WithWord.
End word.

Ltac2 rec push_down_unsigned(w: constr): res :=
  lazy_match! w with
  | ?f1 ?a0 =>
      lazy_match! f1 with
      | @word.of_Z ?width ?word =>
          first_val
            [ res_rewrite '(word.unsigned_of_Z_nowrap $a0
                              ltac2:(bottom_up_simpl_sidecond_hook ()))
            | res_rewrite '(word.unsigned_of_Z_modwrap $a0) ]
      | @word.opp ?width ?word =>
          let r_a0 := push_down_unsigned a0 in
          let pf0 := eq_proof r_a0 in
          lazy_match! new_term r_a0 with
          | 0 => res_rewrite '(word.unsigned_opp_0 $a0 $pf0)
          | _ => first_val [ res_rewrite '(word.unsigned_opp_eq_nowrap $pf0
                                             ltac2:(bottom_up_simpl_sidecond_hook ()))
                           | res_nothing_to_simpl '(word.unsigned $w) ]
          end
      | ?f2 ?a1 =>
          lazy_match! f2 with
          | word.add => push_down_unsigned_app2 w 'word.unsigned_add_eq_nowrap a1 a0
          | word.sub => push_down_unsigned_app2 w 'word.unsigned_sub_eq_nowrap a1 a0
          | word.mul => push_down_unsigned_app2 w 'word.unsigned_mul_eq_nowrap a1 a0
          | _ => res_nothing_to_simpl '(word.unsigned $w)
          end
      | _ => res_nothing_to_simpl '(word.unsigned $w)
      end
  | _ => res_nothing_to_simpl '(word.unsigned $w)
  end
with push_down_unsigned_app2(w: constr)(lem: constr)(a1: constr)(a0: constr): res :=
  let pf0 := eq_proof (push_down_unsigned a0) in
  let pf1 := eq_proof (push_down_unsigned a1) in
  first_val
    [ res_rewrite '($lem _ _ _ _ _ _ _ $pf1 $pf0 ltac2:(bottom_up_simpl_sidecond_hook ()))
    | res_nothing_to_simpl '(word.unsigned $w) ].

Ltac2 local_word_simpl(e: constr): res :=
  lazy_match! e with
  | word.unsigned ?w => push_down_unsigned w
  (* Not sure if we want this one:
     It's useful as a preprocessing step for ring_simplify on words, but if we have
     \[/[z1 + z2]] where 0 <= z1 + z2 < 2^32, we don't want to push down the of_Z,
     so we can do the unsigned_of_Z rewrite.
     --> TODO maybe reactivate, but then, also, in (word.of_Z (word.unsigned (a ^+ b))),
         prevent push_down of word.unsigned! (because here, we don't even need a
         sidecondition to get rid of the roundtrip
  | @word.of_Z ?width ?word ?z => push_down_of_Z width word z *)
  (* Strictly local subset of the above push_down_of_Z: *)
  | @word.of_Z ?width ?word (?z mod 2 ^ ?width) =>
      res_rewrite '(@word.of_Z_mod $width $word _ $z)
  end.

Ltac2 local_simpl_hook(parent_kind: expr_kind)(e: constr): res :=
  first_val
    [ local_subst_small_rhs e
    | local_zlist_simpl e
    | local_ring_simplify parent_kind e
    | local_ground_number_simpl e
    | local_word_simpl e (* <-- not strictly local, might do a whole traversal *)
    | local_nonring_nonground_Z_simpl e
    | res_nothing_to_simpl e ].

(* Nodes like eg (List.length (cons a (cons b (app (cons c xs) ys)))) can
   require an arbitrary number of simplification steps at the same node.

   ---> but that's more of a "push down List.length" algorithm, because once
   we have (len (cons c xs) + len ys), we need to recurse not at the current
   node, but down into the args of + !
Ltac2 saturate_local_simpl parent_kind e :=
  let r := local_simpl_hook parent_kind e in
  lazy_match! r SimplAgain with
  | true => saturate_local_simpl parent_kind e'
  | false => r
  end.

-->
treat push-down separately:
- List.length/len
- word.unsigned
and don't treat them as push-down, but as "compute len/unsigned of given expression
in a bottom-up way"

OR treat them as "local_simpl has access to an API to indicate how/where to continue
simplifying the new term"?

(would also work for (xs ++ ys)[i:] = xs[i:] ++ ys[i - len xs :],
where we have to indicate that (i - len xs) might need further simplification

set, app, repeatz, from, upto

    Lemma len_set: forall (l: list A) i x, 0 <= i < len l -> len (set l i x) = len l.
    Lemma len_app: forall (l1 l2: list A), len (l1 ++ l2) = len l1 + len l2.
    Lemma len_repeatz: forall (x: A) (n: Z), 0 <= n -> len (repeatz x n) = n.
    Lemma len_from: forall (l: list A) i, 0 <= i <= len l -> len (from i l) = len l - i.
    Lemma len_upto: forall (l: list A) i, 0 <= i <= len l -> len (upto i l) = i.

pre-order vs post-order traversal:
len lemmas need to be applied before descending recursively, while others
need to be applied after descending recursively

some need intertwined application:
len_from should first simplify i (so that it's already simplified in the sidecond solving),
then simplify (len l) in a reusable way so that it appears simplified in the sidecondition
and in the rhs, and then apply len_from, and then simplify locally the rhs
(simplified_len_l - simplified_i)

*)

Section PushDownLen.
  Import List.ZIndexNotations. Local Open Scope zlist_scope.
  Context [A: Type].

  Lemma push_down_len_from: forall (l: list A) i n r,
      len l = n ->
      0 <= i <= n ->
      n - i = r ->
      len l[i:] = r.
  Proof. intros. subst. eapply List.len_from. assumption. Qed.

  Lemma push_down_len_from_pastend: forall (l: list A) i n,
      len l = n ->
      n <= i ->
      len l[i:] = 0.
  Proof. intros. subst. rewrite List.from_pastend by assumption. reflexivity. Qed.

  Lemma push_down_len_from_negative: forall (l: list A) i n,
      len l = n ->
      i <= 0 ->
      len l[i:] = n.
  Proof.
    intros. subst. unfold List.from. replace (Z.to_nat i) with O by lia. reflexivity.
  Qed.

  Lemma push_down_len_upto: forall (l: list A) i n,
      len l = n ->
      0 <= i <= n ->
      len l[:i] = i.
  Proof. intros. subst. eapply List.len_upto. assumption. Qed.

  Lemma push_down_len_upto_pastend: forall (l: list A) i n,
      len l = n ->
      n <= i ->
      len l[:i] = n.
  Proof. intros. subst. rewrite List.upto_pastend by assumption. reflexivity. Qed.

  Lemma push_down_len_upto_negative: forall (l: list A) i n,
      len l = n ->
      i <= 0 ->
      len l[:i] = 0.
  Proof.
    intros. subst. unfold List.upto. replace (Z.to_nat i) with O by lia. reflexivity.
  Qed.

  Lemma push_down_len_cons: forall a (l: list A) n,
      1 + len l = n ->
      len (cons a l) = n.
  Proof. intros. subst. rewrite List.length_cons. lia. Qed.

  Lemma push_down_len_app: forall (l1 l2: list A) n1 n2 n,
      len l1 = n1 ->
      len l2 = n2 ->
      n1 + n2 = n ->
      len (l1 ++ l2) = n.
  Proof. intros. subst. eapply List.len_app. Qed.

  Lemma push_down_len_set: forall (l: list A) i n x,
      len l = n ->
      0 <= i < n ->
      len l[i := x] = n.
  Proof. intros. subst. eapply List.len_set. assumption. Qed.

  Lemma push_down_len_repeatz: forall (x: A) (n: Z),
      0 <= n ->
      len (List.repeatz x n) = n.
  Proof. intros. subst. eapply List.len_repeatz. assumption. Qed.

  Lemma push_down_len_repeatz_max: forall (x: A) (n: Z),
      len (List.repeatz x n) = Z.max n 0.
  Proof.
    intros. assert (n < 0 \/ 0 <= n) as C by lia. destruct C.
    - unfold List.repeatz. replace (Z.to_nat n) with O by lia. simpl. lia.
    - replace (Z.max n 0) with n by lia. eapply List.len_repeatz. assumption.
  Qed.
End PushDownLen.

Ltac2 rec concrete_list_length_err(l: constr): constr option :=
  lazy_match! l with
  | nil => Some 'O
  | cons _ ?t =>
      match concrete_list_length_err t with
      | Some r => Some '(S $r)
      | None => None
      end
  | _ => None
  end.

Ltac2 rec push_down_len(x: constr): res :=
  lazy_match! x with
  | List.from ?i ?l =>
      let r_len_l := push_down_len l in
      let len_l := new_term r_len_l in
      let pf_len_l := eq_proof r_len_l in
      first_val
        [ (* Case: index i is within bounds *)
          let sidecond := '(ltac2:(bottom_up_simpl_sidecond_hook ()): 0 <= $i <= $len_l) in
          let r_diff := ring_simplify_res_or_nothing_to_simpl '(Z.sub $len_l $i) in
          let diff := new_term r_diff in
          let pf_diff := eq_proof r_diff in
          res_rewrite
            '(push_down_len_from $l $i $len_l $diff $pf_len_l $sidecond $pf_diff)
        | (* Case: index i is too big *)
          let sidecond := '(ltac2:(bottom_up_simpl_sidecond_hook ()): $len_l <= $i) in
          res_rewrite '(push_down_len_from_pastend $l $i $len_l $pf_len_l $sidecond)
        | (* Case: index i is too small *)
          let sidecond := '(ltac2:(bottom_up_simpl_sidecond_hook ()): $i <= 0) in
          res_rewrite '(push_down_len_from_negative $l $i $len_l $pf_len_l $sidecond)
        | (* Case: unknown whether index is is within bounds, so the List.from remains *)
          res_nothing_to_simpl '(Z.of_nat (List.length $x)) ]
  | @List.upto ?tp ?i ?l =>
      let r_len_l := push_down_len l in
      let len_l := new_term r_len_l in
      let pf_len_l := eq_proof r_len_l in
      first_val
        [ (* Case: index i is within bounds *)
          let sidecond := '(ltac2:(bottom_up_simpl_sidecond_hook ()): 0 <= $i <= $len_l) in
          res_rewrite '(push_down_len_upto $l $i $len_l $pf_len_l $sidecond)
        | (* Case: index i is too big *)
          let sidecond := '(ltac2:(bottom_up_simpl_sidecond_hook ()): $len_l <= $i) in
          res_rewrite '(push_down_len_upto_pastend $i $len_l $pf_len_l $sidecond)
        | (* Case: index i is too small *)
          let sidecond := '(ltac2:(bottom_up_simpl_sidecond_hook ()): $i <= 0) in
          res_rewrite '(push_down_len_upto_negative $l $i $len_l $pf_len_l $sidecond)
        | (* Case: unknown whether index is is within bounds, so the List.upto remains *)
          res_nothing_to_simpl '(Z.of_nat (List.length $x)) ]
  | nil => res_convertible 'Z0
  | cons ?h ?t =>
      match concrete_list_length_err t with
      | Some n => let z := eval cbv in (Z.of_nat (S $n)) in res_convertible z
      | None =>
          let r_len_t := push_down_len t in
          let len_t := new_term r_len_t in
          let pf_len_t := eq_proof r_len_t in
          let r_oneplus := ring_simplify_res_or_nothing_to_simpl '(Z.add 1 $len_t) in
          let oneplus := new_term r_oneplus in
          let pf_oneplus := eq_proof r_oneplus in
          res_rewrite '(push_down_len_cons $h $t $oneplus $pf_oneplus)
      end
  | @List.app ?tp ?l1 ?l2 =>
      let r_len_l1 := push_down_len l1 in
      let r_len_l2 := push_down_len l2 in
      let len_l1 := new_term r_len_l1 in
      let len_l2 := new_term r_len_l2 in
      let r_sum_lens := ring_simplify_res_or_nothing_to_simpl '(Z.add $len_l1 $len_l2) in
      let sum_lens := new_term r_sum_lens in
      let pf_len_l1 := eq_proof r_len_l1 in
      let pf_len_l2 := eq_proof r_len_l2 in
      let pf_sum_lens := eq_proof r_sum_lens in
      res_rewrite '(push_down_len_app $l1 $l2 $len_l1 $len_l2 $sum_lens
                                      $pf_len_l1 $pf_len_l2 $pf_sum_lens)
  | @List.set ?tp ?l ?i ?x =>
      let r_len_l := push_down_len l in
      let len_l := new_term r_len_l in
      let pf_len_l := eq_proof r_len_l in
      let g := '(0 <= $i < $len_l) in
      first_val
        [ let s := '(ltac2:(bottom_up_simpl_sidecond_hook ()) : $g) in
          res_rewrite '(push_down_len_set $l $i $len_l $x $pf_len_l $s)
        | (* TODO Should we fail here (and in more places)? *)
          res_nothing_to_simpl '(Z.of_nat (List.length $x)) ]
  | List.repeatz ?a ?n =>
      first_val
        [ (* Case: n is provably nonnegative *)
          let sidecond := '(ltac2:(bottom_up_simpl_sidecond_hook ()): 0 <= $n) in
          res_rewrite '(push_down_len_repeatz $a $n $sidecond)
        | (* Case: n might be negative *)
          res_rewrite '(push_down_len_repeatz_max $a $n) ]
  | _ => res_nothing_to_simpl '(Z.of_nat (List.length $x))
  end.

(*
Ltac2 bottom_up_simpl parent_kind e :=
  lazy_match! e with
  | Z.add ?x ?y => bottom_up_simpl_app2 e parent_kind ZRingExpr Z.add x y
  | Z.sub ?x ?y => bottom_up_simpl_app2 e parent_kind ZRingExpr Z.sub x y
  | Z.mul ?x ?y => bottom_up_simpl_app2 e parent_kind ZRingExpr Z.mul x y
  | Z.opp ?x    => bottom_up_simpl_app1 e parent_kind ZRingExpr Z.opp x
  | @word.add ?wi ?wo ?x ?y =>
      bottom_up_simpl_app2 e parent_kind WordRingExpr (@word.add wi wo) x y
  | @word.sub ?wi ?wo ?x ?y =>
      bottom_up_simpl_app2 e parent_kind WordRingExpr (@word.sub wi wo) x y
  | @word.mul ?wi ?wo ?x ?y =>
      bottom_up_simpl_app2 e parent_kind WordRingExpr (@word.mul wi wo) x y
  | @word.opp ?wi ?wo ?x    =>
      bottom_up_simpl_app1 e parent_kind WordRingExpr (@word.opp wi wo) x
  | Z.of_nat (@List.length ?A ?l) => push_down_len e A l
  | ?f1 ?a1 =>
      lazy_match! f1 with
      | ?f2 ?a2 =>
          lazy_match! f2 with
          | _ _ => bottom_up_simpl_app e parent_kind f1 a1
          | _ => bottom_up_simpl_app2 e parent_kind OtherExpr f2 a2 a1
          end
      | _ => bottom_up_simpl_app1 e parent_kind OtherExpr f1 a1
      end
  | _ => local_simpl_hook parent_kind e
  end
with bottom_up_simpl_app1 e parent_kind current_kind f a1 :=
  let r1 := bottom_up_simpl current_kind a1 in
  let r := lift_res1 e f r1 in
  let e' := r NewTerm in
  let r' := local_simpl_hook parent_kind e' in
  chain_res r r'
with bottom_up_simpl_app2 e parent_kind current_kind f a1 a2 :=
  let r1 := bottom_up_simpl current_kind a1 in
  let r2 := bottom_up_simpl current_kind a2 in
  let r := lift_res2 e f r1 r2 in
  let e' := r NewTerm in
  let r' := local_simpl_hook parent_kind e' in
  chain_res r r'
with bottom_up_simpl_app e parent_kind f a :=
  let r1 := bottom_up_simpl OtherExpr f in
  let r2 := bottom_up_simpl OtherExpr a in
  let r := lift_res_app e r1 r2 in
  let e' := r NewTerm in
  let r' := local_simpl_hook parent_kind e' in
  chain_res r r'.

(* Consider `word.unsigned (foo (a + 0) ^+ x ^- foo a ^+ y)`:
   The argument of word.unsigned needs a first full bottom-up traversal to simplify
   it into `x ^+ y`, and after that, another push-down-word.unsigned traversal to
   obtain `word.unsigned x + word.unsigned y` (if no overflow).

   On the other hand, if you start pushing down len too early, not a problem,
   because list operations don't cancel like word.sub does.

   Therefore, pushing down len could be integrated into bottom_up_simpl, whereas
   pushing down word.unsigned runs *after* it in local_simpl_hook *)

Lemma rew_Prop_hyp: forall (P1 P2: Prop) (pf: P1 = P2), P1 -> P2.
Proof. intros. subst. assumption. Qed.

Lemma rew_Prop_goal: forall (P1 P2: Prop) (pf: P1 = P2), P2 -> P1.
Proof. intros. subst. assumption. Qed.

Ltac2 bottom_up_simpl_in_hyp H :=
  let t := type of H in
  lazy_match! type of t with
  | Prop => idtac
  | _ => fail "not a Prop"
  end;
  let r := bottom_up_simpl OtherExpr t in
  lazy_match! r DidSomething with
  | false => fail "nothing to simplify"
  | true =>
      let pf := r EqProof in
      let t' := r NewTerm in
      eapply (rew_Prop_hyp t t' pf) in H
  end.

Ltac2 bottom_up_simpl_in_hyp_of_type H t :=
  lazy_match! type of t with
  | Prop =>
      let r := bottom_up_simpl OtherExpr t in
      lazy_match! r DidSomething with
      | false => idtac (* don't force progress *)
      | true =>
          let pf := r EqProof in
          let t' := r NewTerm in
          eapply (rew_Prop_hyp t t' pf) in H
      end
  | _ =>  idtac (* don't force progress *)
  end.

Ltac2 bottom_up_simpl_in_hyp_of_type_if test H t :=
  tryif test H t then bottom_up_simpl_in_hyp_of_type H t else idtac.

Ltac2 bottom_up_simpl_in_letbound_var x b _t :=
  let r := bottom_up_simpl OtherExpr b in
  match r DidSomething with
  | true =>
      let pf := r EqProof in
      let b' := r NewTerm in
      let y := fresh in rename x into y;
      pose (x := b');
      move x after y;
      replace y with x in * by (subst x y; symmetry; exact pf);
      clear y
  | _ => idtac (* might get here because `r DidSomething = false` or because
                  x appears in the type of other expressions and rewriting in the body of x
                  would lead to ill-typed terms *)
  end.

Ltac2 bottom_up_simpl_in_letbound_var_if test x b t :=
  tryif test x b t then bottom_up_simpl_in_letbound_var x b t else idtac.

Ltac2 bottom_up_simpl_in_goal :=
  let t := lazy_match! goal with |- ?g => g end in
  lazy_match! type of t with
  | Prop => idtac
  | _ => fail "not a Prop"
  end;
  let r := bottom_up_simpl OtherExpr t in
  lazy_match! r DidSomething with
  | false => fail "nothing to simplify"
  | true =>
      let pf := r EqProof in
      let t' := r NewTerm in
      eapply (rew_Prop_goal t t' pf)
  end.

Ltac2 bottom_up_simpl_in_hyps :=
  foreach_hyp bottom_up_simpl_in_hyp_of_type.
Ltac2 bottom_up_simpl_in_hyps_if test :=
  foreach_hyp (bottom_up_simpl_in_hyp_of_type_if test).

Ltac2 bottom_up_simpl_in_vars :=
  foreach_var bottom_up_simpl_in_letbound_var.
Ltac2 bottom_up_simpl_in_vars_if test :=
  foreach_var (bottom_up_simpl_in_letbound_var_if test).

Ltac2 bottom_up_simpl_in_hyps_and_vars :=
  bottom_up_simpl_in_hyps; bottom_up_simpl_in_vars.

Ltac2 bottom_up_simpl_in_all :=
  bottom_up_simpl_in_hyps; bottom_up_simpl_in_vars;
  try bottom_up_simpl_in_goal.

Local Hint Mode Word.Interface.word - : typeclass_instances.

Section Tests.
  Set Ltac2 Backtrace.

  Goal forall a: Z, a = a + 0 -> a = a + 0 -> True.
    intros ? E_nosimpl E.
    bottom_up_simpl_in_hyps_if
      ltac:(fun h t => tryif unify h E_nosimpl then fail else idtac).
  Abort.

  Context {word: word.word 32} {word_ok: word.ok word}.

  Add Ring wring : (Properties.word.ring_theory (word := word))
      ((* too expensive: preprocess [autorewrite with rew_word_morphism], *)
       morphism (Properties.word.ring_morph (word := word)),
       constants [Properties.word_cst]).

  Hypothesis P: Z -> Prop.
  Hypothesis Q: list Z -> Prop.

  Import ZList.List.ZIndexNotations. Local Open Scope zlist_scope.

  Ltac2 refl :=
    lazy_match! goal with
    | |- ?x = ?x => reflexivity
    end.

  Goal forall (n b: Z) (bs: list Z),
      Q (List.repeatz b (n - n) ++ bs[2/4:] ++
           List.repeatz b (word.unsigned (word.of_Z 0))) = Q bs.
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Qed.

  Goal forall (byte_of_Z: Z -> Byte.byte) (b: word) (bs: list Byte.byte),
      List.repeatz (byte_of_Z \[b]) \[/[0]] ++ bs[\[/[0]]:] = bs.
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Qed.

  Goal forall a: word, P (word.unsigned (a ^+ word.of_Z 8 ^- a) / 4) -> P 2.
  Proof.
    intros. bottom_up_simpl_in_hyp H. exact H.
  Qed.

  Goal forall a b: Z, (a + a, a + 1) = (2 * a, 1 + b) -> (2 * a, a + 1) = (2 * a, 1 + b).
  Proof.
    (* should not do simplifications that only reorder / don't decrease the size *)
    intros. bottom_up_simpl_in_hyp H.
    exact H.
  Abort.

  Goal forall a b c: Z, a + a + a = b -> a + a + a = c -> b = c.
  Proof.
    intros. bottom_up_simpl_in_hyps. rewrite <- H, H0. refl.
  Abort.

  Goal forall mtvec_base: Z,
      (word.add (word.add (word.mul (word.of_Z 4) (word.of_Z mtvec_base)) (word.of_Z 144))
         (word.of_Z (4 * Z.of_nat (S (Z.to_nat (word.unsigned (word.sub (word.add
            (word.mul (word.of_Z 4) (word.of_Z (Z.of_nat 29))) (word.add
               (word.mul (word.of_Z 4) (word.of_Z mtvec_base)) (word.of_Z 28)))
                  (word.add (word.mul (word.of_Z 4) (word.of_Z mtvec_base))
                     (word.of_Z 144))) / 4)))))) = /[4] ^* /[mtvec_base] ^+ /[148].
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Qed.

  Goal forall (stack_hi: Z) (f: word -> Z),
      f (word.add (word.of_Z stack_hi) (word.of_Z (-128))) =
      f (word.sub (word.of_Z stack_hi) (word.of_Z 128)).
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Qed.

  Goal forall (T: Type) (l: list T) (a b c: T),
      (a :: b :: c :: l)[:5] = a :: b :: c :: l[:2].
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Abort.

  Goal forall (A: Type) (l: list A) (x y z: A),
      ([|x; y|] ++ l)[:2] ++ ([|x; y; z|] ++ l)[2:] = x :: y :: z :: l.
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Abort.

  Goal forall (a b: Z),
      0 <= a + b < 2 ^ 32 ->
      word.unsigned (word.of_Z (a + b)) - b = a.
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Abort.

  Goal forall (foo: Z -> word) (a: Z) (x y: word),
       word.unsigned x + word.unsigned y < 2 ^ 32 ->
       word.unsigned (foo (a + 0) ^+ x ^- foo a ^+ y) = word.unsigned x + word.unsigned y.
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Abort.

  Goal forall (z: Z), word.of_Z (word.unsigned (word.of_Z z)) = word.of_Z z.
  Proof.
    intros. bottom_up_simpl_in_goal. refl.
  Abort.

  Goal forall (i j k count d: Z),
      d <> 0 ->
      (d * j - i * d + k * d * count) / d - count * k = j - i.
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Goal forall (A: Type) (xs ys: list A) i j,
      0 <= i <= 3 + j + i ->
      xs[i : 3 + i + j] = ys ->
      xs[i:][: j + 3] = ys.
  Proof. intros. bottom_up_simpl_in_hyps. assumption. Abort.

  Goal forall (A: Type) (xs ys: list A) i j,
      0 <= i <= j ->
      xs[i:][: j - i] = ys ->
      xs[i : j] = ys.
  Proof. intros. bottom_up_simpl_in_hyps. assumption. Abort.

  Goal forall (A: Type) (xs ys: list A),
      len (xs ++ ys) = len xs + len ys.
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Goal forall (A: Type) (xs ys: list A) (x: A) (i: Z),
      0 <= i < len ys ->
      len (xs ++ ys ++ xs) = 2 * len xs + len ys.
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Goal forall (A: Type) (xs ys: list A) (x: A) (i: Z) (j: Z),
      0 <= i < len ys ->
      0 <= j < i ->
      len (ys[j := x][i := x]) = len ys.
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Goal forall (A: Type) (xs ys: list A) (x: A) (i: Z),
      0 <= i < len ys ->
      len (xs ++ ys[i := x] ++ xs) = 2 * len xs + len ys.
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Goal forall (A: Type) (xs1 xs2 xs3 xs4 xs5 xs6: list A),
      (xs1 ++ xs2) ++ (xs3 ++ xs4 ++ xs5) ++ xs6 = xs1 ++ xs2 ++ xs3 ++ xs4 ++ xs5 ++ xs6.
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Goal forall (A: Type) (l1 l2: list A) (i: Z),
      len l1 = i ->
      (l1 ++ l2)[:i] = l1.
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Goal forall (A: Type) (l1 l2: list A) (i: Z),
      len l1 = i ->
      (l1 ++ l2)[0:][:i] = l1.
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Goal forall (A: Type) (l1 l2: list A) (i: Z),
      0 <= i <= len l1 ->
      (l1 ++ l2)[:i] = l1[:i].
  Proof. intros. bottom_up_simpl_in_goal. refl. Abort.

  Ltac2 bottom_up_simpl_sidecond_hook ::=
    rewrite ?List.len_app, ?List.len_upto, ?List.len_from by lia; lia (*debug_sidecond*).

  Goal forall (A: Type) (xs1 xs2 xs3 xs4 xs5 xs6: list A) i j k s,
      0 <= j <= len xs3 ->
      s = len xs1 + len xs2 + len xs3 - j ->
      s <= i <= s + k ->
      k <= len xs4 ->
      ((xs1 ++ xs2) ++ (xs3[j:] ++ xs4[:k] ++ xs5) ++ xs6)[:i] =
      (xs1 ++ xs2 ++ xs3[j:] ++ xs4[:k])[:i].
  Proof.
    intros. bottom_up_simpl_in_goal.
    (* TODO heuristics to decide whether it's worth pushing it down further to obtain
       xs1 ++ xs2 ++ xs3[j:] ++ xs4[:k][:i - len xs1 - len xs2 - len x3 + j] *)
    refl.
  Abort.


  (** ** Not supported yet: *)

  Goal forall (A: Type) (l1 l2: list A) (x: A) (i: Z),
      len l1 = i ->
      (l1 ++ [|x|] ++ l2)[:i + 1] = l1 ++ [|x|].
  Proof. intros. bottom_up_simpl_in_goal. Fail refl. Abort.

  Goal forall (A: Type) (l1 l2: list A) (x: A) (i: Z),
      len l1 = i ->
      (l1 ++ x :: l2)[:i + 1] = l1 ++ [|x|].
  Proof. intros. Fail bottom_up_simpl_in_goal. Abort.

  Goal forall (z1 z2: Z) (y: word),
      word.of_Z (z1 + z2) ^- word.of_Z z1 = y ->
      word.of_Z z2 = y.
  Proof.
    intros.
    bottom_up_simpl_in_hyps.
    ring_simplify in H.
    (* TODO push_down_of_Z? *)
    (* only simplifies with preprocess [autorewrite with rew_word_morphism] *)
    autorewrite with rew_word_morphism in H.
    ring_simplify in H.
    exact H.
  Abort.

  Context (f: Z -> Z).

  Goal forall x y z1 z2: Z, x = f (z1 + z2) + y - f (z2 + z1) -> x = y.
  Proof.
    intros.
    (* no effect: *)
    ring_simplify (z1 + z2) in H.
    ring_simplify (z2 + z1) in H.
    (* has effect: *)
    ring_simplify (z1 + z2) (z2 + z1) in H.
    ring_simplify in H.
    assumption.
  Abort.

End Tests.
*)
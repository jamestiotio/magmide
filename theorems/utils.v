Add LoadPath "/home/blaine/lab/cpdtlib" as Cpdt.
Set Implicit Arguments. Set Asymmetric Patterns.
Require Import List Cpdt.CpdtTactics.
From stdpp Require Import base fin vector options.
Import ListNotations.

Ltac solve_crush := try solve [crush].
Ltac solve_assumption := try solve [assumption].
Ltac subst_injection H := injection H; intros; subst; clear H.

Notation impossible := (False_rect _ _).
Notation this item := (exist _ item _).
Notation use item := (proj1_sig item).

Section convert_subset.
	Variable T: Type.
	Variable P Q: T -> Prop.
	Theorem convert_subset: {t | P t} -> (forall t: T, P t -> Q t) -> {t | Q t}.
	Proof. intros []; eauto. Qed.
End convert_subset.
Arguments convert_subset {T} {P} {Q} _ _.

Notation convert item := (convert_subset item _).

Notation Yes := (left _ _).
Notation No := (right _ _).
Notation Reduce x := (if x then Yes else No).

Theorem append_single_cons {T: Type}: forall (t: T) l, t :: l = [t] ++ l.
Proof. induction l; auto. Qed.

Theorem valid_index_not_None {T} (l: list T) index:
	index < (length l) -> (lookup index l) <> None.
Proof.
	intros ??%lookup_ge_None; lia.
Qed.
Theorem valid_index_Some {T} (l: list T) index:
	index < (length l) -> exists t, (lookup index l) = Some t.
Proof.
	intros ?%(lookup_lt_is_Some_2 l index);
	unfold is_Some in *; assumption.
Qed.
(*lookup_lt_Some*)
Definition safe_lookup {T} index (l: list T):
	index < (length l) -> {t | (lookup index l) = Some t}
.
	intros ?%valid_index_not_None;
	destruct (lookup index l) eqn:Hlook; try contradiction;
	rewrite <- Hlook; apply (exist _ t Hlook).
Defined.

Theorem safe_lookup_In {T} index (l: list T) (H: index < length l):
	In (use (safe_lookup l H)) l.
Proof.
	apply elem_of_list_In; destruct (safe_lookup l H); simpl;
	apply elem_of_list_lookup; exists index; assumption.
Qed.

Theorem Forall_safe_lookup {T} (P: T -> Prop) l:
	Forall P l <-> forall index (H: index < length l), P (use (safe_lookup l H)).
Proof.
	split.
	-
		intros; destruct (safe_lookup l _); simpl;
		apply (Forall_lookup_1 P l index); assumption.
	-
		intros ?Hfunc; apply Forall_lookup; intros index item Hlookup;
		specialize (lookup_lt_Some l index item Hlookup) as Hindex;
		specialize (Hfunc index Hindex);
		destruct (safe_lookup l _) as [item' Hitem'] in Hfunc; simpl in Hfunc;
		rewrite Hlookup in Hitem'; subst_injection Hitem'; assumption.
Qed.

Definition closer_to target: nat -> nat -> Prop :=
	fun next cur => (target - next) < (target - cur).
(*Hint Unfold closer_to: core.*)

Theorem closer_to_well_founded target: well_founded (closer_to target).
Proof.
	apply (well_founded_lt_compat nat (fun a => target - a)); intros; assumption.
Defined.

Theorem closer_to_reverse: forall target cur next,
	(target - next) < (target - cur) -> cur < next.
Proof. lia. Qed.

Theorem closer_to_bounded_reverse: forall target cur next,
	cur < next -> cur < target -> (target - next) < (target - cur).
Proof. lia. Qed.

Definition closer_to_end {T} (arr: list T) := closer_to (length arr).

Theorem closer_to_end_well_founded {T} (arr: list T): well_founded (closer_to_end arr).
Proof. apply closer_to_well_founded. Qed.

Theorem numeric_capped_incr_safe total begin cap index:
	total = begin + cap
	-> 0 < cap
	-> index < begin
	-> S index < total.
Proof. lia. Qed.

Theorem capped_incr_safe {T} (total begin cap: list T) index:
	total = begin ++ cap
	-> 0 < length cap
	-> index < length begin
	-> S index < length total.
Proof.
	intros Htotal Hcap Hindex;
	assert (Hlen: length total = (length begin) + (length cap))
		by solve [rewrite Htotal; apply app_length];
	apply (numeric_capped_incr_safe Hlen Hcap Hindex).
Qed.


Inductive partial (P: Prop): Type :=
	| Found: P -> partial P
	| NotFound: partial P
.
(*Inductive partial (P: Prop): Type :=
	| Proven: P -> partial P
	| Falsified: ~P -> partial P
	| Unknown: partial P
.*)

Notation found := (Found _).
Notation notfound := (NotFound _).

Section find_obligations.
	Context {T: Type}.
	Variable P: T -> Prop.

	Theorem forall_done_undone items done undone:
		Permutation items (done ++ undone)
		-> Forall P done -> Forall P undone
		-> Forall P items.
	Proof.
		intros Hpermutation??; assert (Happ: Forall P (done ++ undone))
			by solve [apply Forall_app_2; assumption];
		setoid_rewrite Hpermutation; assumption.
	Qed.

	Variable compute_partial: forall t: T, partial (P t).

	Definition split_by_maybe: forall items: list T, {
		pair | Permutation items (pair.1 ++ pair.2) /\ Forall P pair.1
	}.
		refine (fix split_by_maybe items :=
			match items with
			| [] => this ([], [])
			| item :: items' =>
				let (pair, H) := split_by_maybe items' in
				match (compute_partial item) with
				| Found _ => this ((item :: pair.1), pair.2)
				| NotFound => this (pair.1, (item :: pair.2))
				end
			end
		);
		intros; split; simpl in *; try destruct H;
		try solve [setoid_rewrite H; apply Permutation_middle]; auto.
	Defined.

	Definition find_obligations_function: forall items, {
		obligations | Forall P obligations -> Forall P items
	}.
		refine (fun items =>
			let (pair, H) := split_by_maybe items in
			this pair.2
		);
		destruct H; apply (forall_done_undone H); assumption.
	Defined.

	Theorem verify__find_obligations_function:
		forall items found, found = find_obligations_function items
		-> Forall P (use found) -> Forall P items.
	Proof. intros ?[]; auto. Qed.

End find_obligations.

Ltac find_obligations__helper P compute_partial items :=
	let found := eval compute in (find_obligations_function P compute_partial items) in
	let pf := eval compute in (proj2_sig found) in
	apply pf; apply Forall_fold_right; simpl; repeat split
.

Ltac find_obligations P compute_partial items :=
	match goal with
	| |- Forall P items =>
		find_obligations__helper P compute_partial items

	| |- forall item, In item items -> P item =>
		apply Coq.Lists.List.Forall_forall;
		find_obligations__helper P compute_partial items

	| |- forall item, elem_of item items -> P item =>
		apply Forall_forall;
		find_obligations__helper P compute_partial items

	| |- forall index def, index < length items -> P (nth index items def) =>
		apply Coq.Lists.List.Forall_nth;
		find_obligations__helper P compute_partial items

	| |- forall index item, (lookup index items) = Some item -> P item =>
		apply Forall_lookup;
		find_obligations__helper P compute_partial items

	| |- forall index, index < length items -> P (items !!! index) =>
		apply Forall_lookup_total;
		find_obligations__helper P compute_partial items

	| |- forall index (H: index < length items), P (use (safe_lookup items H)) =>
		apply Forall_safe_lookup;
		find_obligations__helper P compute_partial items
	end
.

Module test__find_obligations.
	Definition P n := (n < 4 \/ n < 6).
	Definition compute_partial: forall n, partial (P n).
		refine (fun n => if (lt_dec n 4) then found else notfound); unfold P; lia.
	Defined.

	Definition items := [0; 1; 2; 4; 3; 2; 5].
	Theorem find_obligations__Forall: Forall P items.
	Proof. find_obligations P compute_partial items; lia. Qed.
	Theorem find_obligations__forall_In: forall item, In item items -> P item.
	Proof. find_obligations P compute_partial items; lia. Qed.
	Theorem find_obligations__forall_elem_of: forall item, elem_of item items -> P item.
	Proof. find_obligations P compute_partial items; lia. Qed.
	Theorem find_obligations__forall_nth: forall index def, index < length items -> P (nth index items def).
	Proof. find_obligations P compute_partial items; lia. Qed.
	Theorem find_obligations__forall_lookup: forall index item, (lookup index items) = Some item -> P item.
	Proof. find_obligations P compute_partial items; lia. Qed.
	Theorem find_obligations__forall_lookup_total: forall index, index < length items -> P (items !!! index).
	Proof. find_obligations P compute_partial items; lia. Qed.
	Theorem find_obligations__forall_safe_lookup:
		forall index (H: index < length items), P (use (safe_lookup items H)).
	Proof. find_obligations P compute_partial items; lia. Qed.
End test__find_obligations.

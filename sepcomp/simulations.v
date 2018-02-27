Require Import Coq.Bool.Bool.

Require Import compcert.common.Values.
Require Import compcert.common.Memory.
Require Import compcert.lib.Coqlib.
Require Import compcert.common.Events.
Require Import compcert.lib.Maps.
Require Import compcert.lib.Integers.
Require Import compcert.common.AST.
Require Import compcert.common.Globalenvs.
Require Import compcert.lib.Axioms.

Require Import VST.sepcomp.mem_lemmas.
Require Import VST.sepcomp.semantics.
Require Import VST.sepcomp.effect_semantics.
Require Import VST.sepcomp.structured_injections.
Require Import VST.sepcomp.reach.
Require Export VST.sepcomp.globalSep.
Require Import VST.sepcomp.semantics_lemmas.

Goal forall F1 V1 C1 (Sem1 : @EffectSem (Genv.t F1 V1) C1)
     ge1 U1 st1 m1 st1' m1' b1 z,
     effstep Sem1 ge1 U1 st1 m1 st1' m1' -> U1 b1 z = true ->
     Mem.perm m1 b1 z Max Nonempty.
Proof. intros. eapply Mem.perm_implies. 
  - apply Mem.perm_cur. eapply (effstep_perm Sem1); eassumption.
  - constructor.
Qed.

(*In case we decide to eliminate MS_Div we can simplify the following 
2 definitions to 
MSR_locally_allocated mu mu' m1 m2 A1 A2 := SM_locally_allocated mu mu' m1 m2 (mem_of A1) (mem_of A2)
and
MSR_mem_unchanged_on P m A := Mem.unchanged_on P m (mem_of A)
where mem_of is the obvious projection function*)
Definition MSR_locally_allocated {C1 C2} (mu mu' : SM_Injection) (m1 m2 : mem) 
           (A1: @MidStepResult C1 mem) (A2: @MidStepResult C2 mem):=
match A1, A2 with
  MS_Ext _ m1' _ _, MS_Ext _ m2' _ _ => sm_locally_allocated mu mu' m1 m2 m1' m2'
| MS_Ret _ m1' _,  MS_Ret _ m2' _ => sm_locally_allocated mu mu' m1 m2 m1' m2'
| _, _ => True
end.

Definition MSR_unchanged_on {C} P m (A: @MidStepResult C mem) :=
  match A with
    MS_Ext _ m' _ _ => Mem.unchanged_on P m m'
  | MS_Ret _ m' _ => Mem.unchanged_on P m m'
  | _ => True
  end.

(*This definition aims to be the mirrored version of local_out_of_reach.
  In particular, including mem_unchange_on (extern_out_of_reach nu m1) m2 m2' in 
  match_midstep should (fingers crossed) suffice for establishing the caller's
  condition mem_unchanged_on (local_out_of_reach nu m1) m2 m2' 
  of clause matchafter_external*)
Definition extern_out_of_reach mu (m : mem) (b : block) (ofs : Z): Prop :=
  extBlocksTgt mu b = true /\
  forall b0 delta, extern_of mu b0 = Some (b, delta) ->
                  (~ Mem.perm m b0 (ofs - delta) Max Nonempty \/
                   frgnBlocksSrc mu b0 = false).

(** * Structured Simulations *)

Module SM_simulation. Section SharedMemory_simulation_inject.

(** Structured simulations are parameterized by a source interaction semantics
    [Sem1] and by a target interaction semantics [Sem2]. *)

(** [ge1] and [ge2] are the global environments associated with [Sem1] and
    [Sem2] respectively. *)

Context
  {F1 V1 C1 F2 V2 C2 : Type}
  (Sem1 : @EffectSem (Genv.t F1 V1) C1)
  (Sem2 : @EffectSem (Genv.t F2 V2) C2)
  (ge1 : Genv.t F1 V1)
  (ge2 : Genv.t F2 V2).
 (* (CS1_RDO: forall c m c' m', corestep Sem1 ge1 c m c' m' ->
                  (*mem_respects_readonly ge1 m ->*)
                  (forall b, isGlobalBlock ge1 b = true -> Mem.valid_block m b) ->
                  RDOnly_fwd m m' (ReadOnlyBlocks ge1))
  (CS2_RDO: forall c m c' m', corestep Sem2 ge2 c m c' m' ->
                  (*mem_respects_readonly ge2 m ->*)
                  (forall b, isGlobalBlock ge2 b = true -> Mem.valid_block m b) ->
                  RDOnly_fwd m m' (ReadOnlyBlocks ge2)).

Require Import VST.sepcomp.semantics_lemmas.
Lemma CS1_RDO_N: forall n c m c' m', corestepN Sem1 ge1 n c m c' m' ->
                  (*mem_respects_readonly ge1 m ->*)
                  (forall b, isGlobalBlock ge1 b = true -> Mem.valid_block m b) ->
                  RDOnly_fwd m m' (ReadOnlyBlocks ge1).
Proof.
  induction n; simpl; intros; red; intros.
  inv H. apply readonly_refl.
  destruct H as [cc [mm [CS CSN]]].
  specialize (corestep_fwd _ _ _ _ _ _ CS). intros.
  apply CS1_RDO in CS; trivial.
  eapply readonly_trans. eapply CS. eassumption.
  eapply IHn; try eassumption.
  intros. apply H. eauto.
  (*eapply mem_respects_readonly_forward'; eassumption.*)
Qed.

Lemma CS1_RDO_plus: forall c m c' m', corestep_plus Sem1 ge1 c m c' m' ->
                  (forall b, isGlobalBlock ge1 b = true -> Mem.valid_block m b) ->
                  RDOnly_fwd m m' (ReadOnlyBlocks ge1).
Proof. intros. destruct H. eapply CS1_RDO_N; eassumption. Qed.

Lemma CS1_RDO_star: forall c m c' m', corestep_star Sem1 ge1 c m c' m' ->
                  (forall b, isGlobalBlock ge1 b = true -> Mem.valid_block m b) ->
                  RDOnly_fwd m m' (ReadOnlyBlocks ge1).
Proof. intros. destruct H. eapply CS1_RDO_N; eassumption. Qed.

Lemma CS2_RDO_N: forall n c m c' m', corestepN Sem2 ge2 n c m c' m' ->
                  (forall b, isGlobalBlock ge2 b = true -> Mem.valid_block m b) ->
                  RDOnly_fwd m m' (ReadOnlyBlocks ge2).
Proof.
  induction n; simpl; intros; red; intros.
  inv H. apply readonly_refl.
  destruct H as [cc [mm [CS CSN]]].
  specialize (corestep_fwd _ _ _ _ _ _ CS). intros.
  apply CS2_RDO in CS; trivial.
  eapply readonly_trans. eapply CS. eassumption.
  eapply IHn; try eassumption.
  intros. apply H. eauto.
  (*eapply mem_respects_readonly_forward'; eassumption.*)
Qed.

Lemma CS2_RDO_plus: forall c m c' m', corestep_plus Sem2 ge2 c m c' m' ->
                  (forall b, isGlobalBlock ge2 b = true -> Mem.valid_block m b) ->
                  RDOnly_fwd m m' (ReadOnlyBlocks ge2).
Proof. intros. destruct H. eapply CS2_RDO_N; eassumption. Qed.

Lemma CS2_RDO_star: forall c m c' m', corestep_star Sem2 ge2 c m c' m' ->
                  (forall b, isGlobalBlock ge2 b = true -> Mem.valid_block m b) ->
                  RDOnly_fwd m m' (ReadOnlyBlocks ge2).
Proof. intros. destruct H. eapply CS2_RDO_N; eassumption. Qed.
*)

(*matchstate to be instantiated by match_state cd below*)
Definition MSR_relate matchstate mu (A: @MidStepResult C1 mem)
    (B: @MidStepResult C2 mem):=
match A, B with
  MS_Ext c1 m1 f1 vals1, MS_Ext c2 m2 f2 vals2 =>
       Mem.inject (as_inj mu) m1 m2 /\ f1=f2
       /\ mem_respects_readonly ge1 m1 /\ mem_respects_readonly ge2 m2
       /\ Forall2 (val_inject (restrict (as_inj mu) (vis mu))) vals1 vals2
       /\ forall
       (pubSrc' pubTgt' : block -> bool)
       (pubSrcHyp : pubSrc' =
                  (fun b : block =>
                  locBlocksSrc mu b && REACH m1 (exportedSrc mu vals1) b))
       (pubTgtHyp: pubTgt' =
                  (fun b : block =>
                  locBlocksTgt mu b && REACH m2 (exportedTgt mu vals2) b))
       nu (Hnu: nu = (replace_locals mu pubSrc' pubTgt')),
       (*MSR_relate nu (MS_Ext c1 m1 f1 vals1) (MS_Ext c2 m2 f2 vals2)*)
       matchstate nu c1 m1 c2 m2
       /\ Mem.inject (shared_of nu) m1 m2
| MS_Ret c1 m1 v1, MS_Ret c2 m2 v2 => 
        Mem.inject (as_inj mu) m1 m2
        /\ mem_respects_readonly ge1 m1 /\ mem_respects_readonly ge2 m2
        /\ val_inject (restrict (as_inj mu) (vis mu)) v1 v2
| MS_Div, MS_Div => True 
| _, _ => False
end.

Record SM_simulation_inject := {
  (** The type of auxiliary data used to model stuttering. *)
  core_data : Type

  (** The (existentially quantified) match-state relation of the simulation. *)
; match_state : core_data -> SM_Injection -> C1 -> mem -> C2 -> mem -> Prop

  (** A well-founded order on values of type [core_data]. *)
; core_ord : core_data -> core_data -> Prop
; core_ord_wf : well_founded core_ord

  (** The match relation implies that [mu] is well-defined. *)
; match_sm_wd :
    forall d mu c1 m1 c2 m2,
    match_state d mu c1 m1 c2 m2 -> SM_wd mu

  (** The global environments have equal domain. *)
; genvs_dom_eq : genvs_domain_eq ge1 ge2

  (** The global environments also associate same info with global blocks and
      preserve find_var. These conditions are used for in the transitivity proof,
      to establish mem_respects_readonly for the intermediate memory and globalenv. *)
; ginfo_preserved : gvar_infos_eq ge1 ge2 /\ findsymbols_preserved ge1 ge2

  (** The injection [mu] preserves global blocks. *)
; match_genv :
    forall d mu c1 m1 c2 m2 (MC : match_state d mu c1 m1 c2 m2),
    meminj_preserves_globals ge1 (extern_of mu) /\
    (forall b, isGlobalBlock ge1 b = true -> frgnBlocksSrc mu b = true)

  (** The set of visible blocks is [REACH]-closed. *)
; match_visible :
    forall d mu c1 m1 c2 m2,
    match_state d mu c1 m1 c2 m2 ->
    REACH_closed m1 (vis mu)

  (** [match_state] is closed under restriction to reach-closed supersets of
      the visible blocks. REMOVED in jan. 2015*)
(*; match_restrict:
    forall d mu c1 m1 c2 m2,
      match_state d mu c1 m1 c2 m2 ->
      forall X, (forall b, vis mu b = true -> X b = true) ->
                REACH_closed m1 X ->
      match_state d (restrict_sm mu X) c1 m1 c2 m2*)


  (** The blocks in the domain/range of [mu] are valid in [m1]/[m2]. *)
; match_validblocks :
    forall d mu c1 m1 c2 m2,
    match_state d mu c1 m1 c2 m2 ->
    sm_valid mu m1 m2

(*Unifies corestep_diagram (incl step-star stuff), core_atExternal, and core_halted*)
; match_midstep :
    forall d mu c1 m1 c2 m2 A1,
    match_state d mu c1 m1 c2 m2 ->
    midstep Sem1 ge1 c1 m1 A1 ->
    exists A2 cd' mu', 
      midstep Sem2 ge2 c2 m2 A2
      /\ intern_incr mu mu'
      /\ globals_separate ge2 mu mu'
      /\ MSR_locally_allocated mu mu' m1 m2 A1 A2 (*replaces sm_locally_allocated mu mu' m1 m2 m1' m2'*)
      /\ MSR_relate (match_state cd') mu' A1 A2
      /\ (MSR_unchanged_on (fun b z => vis mu b = false) m1 A1 ->
          MSR_unchanged_on (extern_out_of_reach mu m1) m2 A2)
      (*TODO: do we actually still need the indices cd/cd'? If yes, probably insert core_ord cd' cd clause*)

(*TODO: reformulate afterExtcall*)
}.

End SharedMemory_simulation_inject.

Module TRANSITIVITY. Section TRANS.

Inductive sem_compose_ord_eq_eq {D12 D23:Type}
  (ord12: D12 -> D12 -> Prop) (ord23: D23 -> D23 -> Prop) (C2:Type):
  (D12 * option C2 * D23) ->  (D12 * option C2 * D23) ->  Prop :=
| sem_compose_ord1 :
  forall (d12 d12':D12) (c2:C2) (d23:D23),
    ord12 d12 d12' -> sem_compose_ord_eq_eq ord12 ord23 C2 (d12,Some c2,d23) (d12',Some c2,d23)
| sem_compose_ord2 :
  forall (d12 d12':D12) (c2 c2':C2) (d23 d23':D23),
    ord23 d23 d23' -> sem_compose_ord_eq_eq ord12 ord23 C2 (d12,Some c2,d23) (d12',Some c2',d23').

Lemma well_founded_sem_compose_ord_eq_eq: forall {D12 D23:Type}
  (ord12: D12 -> D12 -> Prop) (ord23: D23 -> D23 -> Prop)  (C2:Type)
  (WF12: well_founded ord12) (WF23: well_founded ord23),
  well_founded (sem_compose_ord_eq_eq ord12 ord23 C2).
Proof.
  intros. intro. destruct a as [[d12 c2] d23].
  revert d12.
  destruct c2.
  2: constructor; intros. 2: inv H.
  revert c.
  induction d23 using (well_founded_induction WF23).
  intros.
  induction d12 using (well_founded_induction WF12).
  constructor; intros. inv H1.
  generalize (H0 d0). simpl. intros.
  apply H1. auto.
  generalize (H d1).
  intros.
  specialize H1. auto.
Qed.

Definition compose_sm (mu1 mu2 : SM_Injection) : SM_Injection :=
 Build_SM_Injection
   (locBlocksSrc mu1) (locBlocksTgt mu2)
   (pubBlocksSrc mu1) (pubBlocksTgt mu2)
   (compose_meminj (local_of mu1) (local_of mu2))
   (extBlocksSrc mu1) (extBlocksTgt mu2)
   (frgnBlocksSrc mu1) (frgnBlocksTgt mu2)
   (compose_meminj (extern_of mu1) (extern_of mu2)).

Context
  {F1 V1 C1 F2 V2 C2 F3 V3 C3: Type}
  (Sem1 : @EffectSem (Genv.t F1 V1) C1)
  (Sem2 : @EffectSem (Genv.t F2 V2) C2)
  (Sem3 : @EffectSem (Genv.t F3 V3) C3)
  (ge1 : Genv.t F1 V1)
  (ge2 : Genv.t F2 V2)
  (ge3 : Genv.t F3 V3).

Variable SIM12:SM_simulation_inject Sem1 Sem2 ge1 ge2.
Definition CoreData12:= core_data _ _ _ _ SIM12.
Definition CoreOrd12:= core_ord _ _ _ _ SIM12.
Definition MatchState12:= match_state _ _ _ _ SIM12.

Variable SIM23:SM_simulation_inject Sem2 Sem3 ge2 ge3.
Definition CoreData23:= core_data _ _ _ _ SIM23.
Definition CoreOrd23:= core_ord _ _ _ _ SIM23.
Definition MatchState23:= match_state _ _ _ _ SIM23.

Definition coreData:Type  :=
       core_data Sem1 Sem2 ge1 ge2 SIM12 * option C2 *
       core_data Sem2 Sem3 ge2 ge3 SIM23.

Definition CoreOrd:= Relation_Operators.clos_trans _ (sem_compose_ord_eq_eq CoreOrd12 CoreOrd23 C2).

Check (sem_compose_ord_eq_eq CoreOrd12 CoreOrd23 C2).

Definition MatchState (d:coreData) (mu: SM_Injection) (c1:C1)(m1:mem)(c3:C3)(m3:mem): Prop :=
      match d with (d1,X,d2) =>
        exists c2, exists m2, exists mu1, exists mu2,
          X=Some c2 /\ mu = compose_sm mu1 mu2 /\
          MatchState12 d1 mu1 c1 m1 c2 m2 /\ MatchState23 d2 mu2 c2 m2 c3 m3
      end.

Lemma Transitivity: SM_simulation_inject Sem1 Sem3 ge1 ge3.
Proof.
eapply (Build_SM_simulation_inject Sem1 Sem3 ge1 ge3 coreData MatchState).
+ eapply well_founded_sem_compose_ord_eq_eq.
  apply (core_ord_wf Sem1 Sem2 ge1 ge2 SIM12).
  apply (core_ord_wf Sem2 Sem3 ge2 ge3 SIM23).
+ admit.
+ admit.
+ admit.
+ admit.
+ admit.
+ admit.
+ (*corediagram*) intros. rename c2 into c3. rename m2 into m3.
  destruct d as [[d12 X] d23]. simpl in H.
  destruct H as [c2 [m2 [mu12 [mu23 [? [? [MS12 MS23]]]]]]]; subst.
  destruct (match_midstep _ _ _ _ SIM12 _ _ _ _ _ _ _ MS12 H0)
   as [A2 [cd2 [mu12' [STEP2 [INC12 [SEP12 [LOCALLOC12 [REL12 UNCH2]]]]]]]].
  simpl in *.
  destruct (match_midstep _ _ _ _ SIM23 _ _ _ _ _ _ _ MS23 STEP2)
   as [A3 [cd3 [mu23' [STEP3 [INC23 [SEP23 [LOCALLOC23 [REL23 UNCH3]]]]]]]].
  exists A3, (cd2, Some c2, cd3), (compose_sm mu12' mu23'). split; trivial.
  split. admit.
  split. admit.
  split. admit.
  split. admit.
  intros. clear - REL12 REL23 UNCH2 UNCH3 H.
  unfold extern_out_of_reach; simpl.
  destruct A3; simpl in *; trivial.
  - destruct A2; try contradiction. destruct A1; try contradiction.
    simpl in *. clear REL12 REL23.
    exploit UNCH2; clear UNCH2.
    * eapply mem_unchanged_on_sub; [ eassumption | intros; simpl ].
      unfold vis in *; simpl in *; trivial.
    * intros. exploit UNCH3; clear UNCH3.
      ++ eapply mem_unchanged_on_sub; [ eassumption | intros; simpl ].
         unfold vis in *; simpl in *. red; intros. ; trivial.
         red; intros.
Search Mem.unchanged_on.

  - admit. - admit.
  - admit. (* destruct A1; destruct A2; destruct A3; simpl in *; try contradiction.
    * rename c into c1'. rename m into m1'. rename m0 into m2'. 
      rename c4 into c3'. rename m4 into m3'. 
      red in LOCALLOC12. red in LOCALLOC23.
      destruct mu12; destruct mu12'; simpl in *.
      destruct REL12 as [INJ12' [E12 [MRR1 [MRR2 [VINJ12 X12]]]]].
      destruct REL23 as [INJ23' [E23 [MRR2' [MRR3 [VINJ23 X23]]]]]. red.*)
  - admit. (* clear - REL12 REL23. destruct A1; destruct A2; destruct A3; simpl in *; try contradiction.
    * rename c into c1'. rename m into m1'. rename m0 into m2'. 
      rename c4 into c3'. rename m4 into m3'. *)
  - clear - UNCH3 H H1.

econstructor.


Definition WP_trans:
        Wholeprog_sim.Wholeprog_sim Sem1 Sem3 g1 g3 Main GeInv13 (InitInv13 g2) (HaltInv13 g2).


  (** The clause that relates initial states. *)
; core_initial :
    forall v vals1 c1 m1 j vals2 m2 DomS DomT,
    initial_core Sem1 0 ge1 v vals1 = Some c1 ->
    Mem.inject j m1 m2 ->
    Forall2 (val_inject j) vals1 vals2 ->
    meminj_preserves_globals ge1 j ->
    globalfunction_ptr_inject ge1 j ->

    (*the next two conditions are required to guarantee initialSM_wd*)
    (forall b1 b2 d, j b1 = Some (b2, d) ->
      DomS b1 = true /\ DomT b2 = true) ->
    (forall b,
      REACH m2 (fun b' => isGlobalBlock ge2 b' || getBlocks vals2 b') b=true ->
      DomT b = true) ->

    mem_respects_readonly ge1 m1 -> mem_respects_readonly ge2 m2 ->

    (*the next two conditions ensure the initialSM satisfies sm_valid*)
    (forall b, DomS b = true -> Mem.valid_block m1 b) ->
    (forall b, DomT b = true -> Mem.valid_block m2 b) ->

    exists cd, exists c2,
    initial_core Sem2 0 ge2 v vals2 = Some c2
    /\ match_state cd
         (initial_SM DomS DomT
           (REACH m1 (fun b => isGlobalBlock ge1 b || getBlocks vals1 b))
           (REACH m2 (fun b => isGlobalBlock ge2 b || getBlocks vals2 b)) j)
         c1 m1 c2 m2

  (** The diagram for internal steps. *)
; effcore_diagram :
    forall st1 m1 st1' m1' U1,
    effstep Sem1 ge1 U1 st1 m1 st1' m1' ->
    forall cd st2 mu m2,
    match_state cd mu st1 m1 st2 m2 ->
    exists st2', exists m2', exists cd', exists mu',
      intern_incr mu mu'
      /\ globals_separate ge2 mu mu'
      /\ sm_locally_allocated mu mu' m1 m2 m1' m2'
      /\ match_state cd' mu' st1' m1' st2' m2'
      /\ exists U2,
          ((effstep_plus Sem2 ge2 U2 st2 m2 st2' m2' \/
            (effstep_star Sem2 ge2 U2 st2 m2 st2' m2' /\
             core_ord cd' cd)) /\
          ( forall
            (UHyp: forall b1 z, U1 b1 z = true -> vis mu b1 = true)
            b ofs (Ub: U2 b ofs = true),
            visTgt mu b = true
            /\ (locBlocksTgt mu b = false ->
               exists b1 delta1,
                 foreign_of mu b1 = Some(b,delta1)
                 /\ U1 b1 (ofs-delta1) = true
                 /\ (*in fact, other properties of effstep already 
                      imply this conjunct:*) Mem.perm m1 b1 (ofs-delta1) Max Nonempty)))

  (** The clause that relates halted states. *)
; core_halted :
    forall cd mu c1 m1 c2 m2 v1,
    match_state cd mu c1 m1 c2 m2 ->
    halted Sem1 c1 = Some v1 ->
    exists v2,
    Mem.inject (as_inj mu) m1 m2
    /\ mem_respects_readonly ge1 m1 /\ mem_respects_readonly ge2 m2
    /\ val_inject (restrict (as_inj mu) (vis mu)) v1 v2
    /\ halted Sem2 c2 = Some v2

  (** The clause that relates [at_external] call points. *)
; core_at_external :
    forall cd mu c1 m1 c2 m2 e vals1,
    match_state cd mu c1 m1 c2 m2 ->
    at_external Sem1 c1 = Some (e,vals1) ->
    Mem.inject (as_inj mu) m1 m2
    /\ mem_respects_readonly ge1 m1 /\ mem_respects_readonly ge2 m2
    /\ exists vals2,
       Forall2 (val_inject (restrict (as_inj mu) (vis mu))) vals1 vals2
       /\ at_external Sem2 c2 = Some (e,vals2)

    /\ forall
       (pubSrc' pubTgt' : block -> bool)
       (pubSrcHyp : pubSrc' =
                  (fun b : block =>
                  locBlocksSrc mu b && REACH m1 (exportedSrc mu vals1) b))
       (pubTgtHyp: pubTgt' =
                  (fun b : block =>
                  locBlocksTgt mu b && REACH m2 (exportedTgt mu vals2) b))
       nu (Hnu: nu = (replace_locals mu pubSrc' pubTgt')),
       match_state cd nu c1 m1 c2 m2
       /\ Mem.inject (shared_of nu) m1 m2

  (** The diagram for external steps. *)
; eff_after_external:
    forall cd mu st1 st2 m1 e vals1 m2 vals2 e'
      (MemInjMu: Mem.inject (as_inj mu) m1 m2)
      (MatchMu: match_state cd mu st1 m1 st2 m2)
      (AtExtSrc: at_external Sem1 st1 = Some (e,vals1))

        (** We include the clause [AtExtTgt] to ensure that [vals2] is uniquely
         determined. We have [e=e'] and [ef_sig=ef_sig'] by the [at_external]
         clause, but omitting the hypothesis [AtExtTgt] would result in two not
         necesssarily equal target argument lists in language three in the
         transitivity proof, as [val_inject] is not functional in the case in
         which the left value is [Vundef] ([Vundef]s can be refined under memory
         injections to arbitrary values). *)

      (AtExtTgt: at_external Sem2 st2 = Some (e',vals2))
      (ValInjMu: Forall2 (val_inject (restrict (as_inj mu) (vis mu))) vals1 vals2)

      pubSrc'
      (pubSrcHyp:
         pubSrc'
         = (fun b => locBlocksSrc mu b && REACH m1 (exportedSrc mu vals1) b))

      pubTgt'
      (pubTgtHyp:
         pubTgt'
         = fun b => locBlocksTgt mu b && REACH m2 (exportedTgt mu vals2) b)

      nu (NuHyp: nu = replace_locals mu pubSrc' pubTgt'),

      forall nu' ret1 m1' ret2 m2'
        (HasTy1: Val.has_type ret1 (proj_sig_res (AST.ef_sig e)))
        (HasTy2: Val.has_type ret2 (proj_sig_res (AST.ef_sig e')))
        (INC: extern_incr nu nu')
        (GSep: globals_separate ge2 nu nu')

        (WDnu': SM_wd nu') (SMvalNu': sm_valid nu' m1' m2')

        (MemInjNu': Mem.inject (as_inj nu') m1' m2')
        (RValInjNu': val_inject (as_inj nu') ret1 ret2)

        (FwdSrc: mem_forward m1 m1') (FwdTgt: mem_forward m2 m2')
        (RDO1: RDOnly_fwd m1 m1' (ReadOnlyBlocks ge1))
        (RDO2: RDOnly_fwd m2 m2' (ReadOnlyBlocks ge2))

        frgnSrc'
        (frgnSrcHyp:
           frgnSrc'
           = fun b => DomSrc nu' b &&
                      (negb (locBlocksSrc nu' b) &&
                       REACH m1' (exportedSrc nu' (ret1::nil)) b))

        frgnTgt'
        (frgnTgtHyp:
           frgnTgt'
           = fun b => DomTgt nu' b &&
                      (negb (locBlocksTgt nu' b) &&
                       REACH m2' (exportedTgt nu' (ret2::nil)) b))

        mu' (Mu'Hyp: mu' = replace_externs nu' frgnSrc' frgnTgt')

         (UnchPrivSrc:
            Mem.unchanged_on (fun b ofs =>
              locBlocksSrc nu b = true /\
              pubBlocksSrc nu b = false) m1 m1')

         (UnchLOOR: Mem.unchanged_on (local_out_of_reach nu m1) m2 m2'),

        exists cd', exists st1', exists st2',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' mu' st1' m1' st2' m2' }.

(** Derive an effectless internal step diagram clause from the effectful diagram
  above. *)

Lemma core_diagram (SMI: SM_simulation_inject):
      forall st1 m1 st1' m1',
        corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 mu m2,
        match_state SMI cd mu st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists mu',
          intern_incr mu mu' /\
          globals_separate ge2 mu mu' /\
          sm_locally_allocated mu mu' m1 m2 m1' m2' /\
          match_state SMI cd' mu' st1' m1' st2' m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord SMI cd' cd).
Proof. intros.
apply effax2 in H. destruct H as [U1 H].
exploit (effcore_diagram SMI); eauto.
intros [st2' [m2' [cd' [mu' [INC [GSEP [LOCALLOC
  [MST [U2 [STEP _]]]]]]]]]].
exists st2', m2', cd', mu'.
split; try assumption.
split; try assumption.
split; try assumption.
split; try assumption.
destruct STEP as [[n STEP] | [[n STEP] CO]];
  apply effstepN_corestepN in STEP.
left. exists n. assumption.
right; split; trivial. exists n. assumption.
Qed.

(** Derive an internal step diagram with RDO_fwd property. *)
Lemma effcore_diagram_RDO_fwd (SMI: SM_simulation_inject):
    forall st1 m1 st1' m1' U1,
    effstep Sem1 ge1 U1 st1 m1 st1' m1' ->
    forall cd st2 mu m2,
    match_state SMI cd mu st1 m1 st2 m2 ->
    exists st2', exists m2', exists cd', exists mu',
      intern_incr mu mu'
      /\ globals_separate ge2 mu mu'
      /\ sm_locally_allocated mu mu' m1 m2 m1' m2'
      /\ match_state SMI cd' mu' st1' m1' st2' m2'
      /\ exists U2,
          ((effstep_plus Sem2 ge2 U2 st2 m2 st2' m2' \/
            (effstep_star Sem2 ge2 U2 st2 m2 st2' m2' /\
             core_ord SMI cd' cd)) /\
          ( forall
            (UHyp: forall b1 z, U1 b1 z = true -> vis mu b1 = true)
            b ofs (Ub: U2 b ofs = true),
            visTgt mu b = true
            /\ (locBlocksTgt mu b = false ->
               exists b1 delta1,
                 foreign_of mu b1 = Some(b,delta1)
                 /\ U1 b1 (ofs-delta1) = true
                 /\ Mem.perm m1 b1 (ofs-delta1) Max Nonempty))
         /\ (forall b, Mem.valid_block m1 b -> readonly m1 b m1')
         /\ (forall b, Mem.valid_block m2 b -> readonly m2 b m2')).
Proof. intros.
  exploit effcore_diagram; eauto.
  intros [st2' [m2' [cd' [mu' [INC [LOCALLOC [GSEP [MTCH' [U2 [Steps2 VIS]]]]]]]]]].
  exists st2', m2', cd', mu'.
  split; trivial.
  split; trivial.
  split; trivial.
  split; trivial.
  exists U2.
  split; trivial.
  split; trivial.
  destruct (match_genv SMI _ _ _ _ _ _ H0).
  specialize (match_sm_wd SMI _ _ _ _ _ _ H0). intros WD.
  apply match_validblocks in H0.
  split; intros. eapply corestep_rdonly; trivial. eapply effstep_corestep. eassumption.
  destruct Steps2 as [Steps2 | [Steps2 _]].
    apply effstep_plus_corestep_plus in Steps2.
    eapply corestep_plus_rdonly; eassumption.
  apply effstep_star_corestep_star in Steps2.
    eapply corestep_star_rdonly; eassumption.
Qed.

End SharedMemory_simulation_inject.

End SM_simulation.


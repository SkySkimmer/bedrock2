Require Import Coq.ZArith.ZArith.
Require Import bedrock2.Syntax bedrock2.Semantics.
Require coqutil.Datatypes.String coqutil.Map.SortedList coqutil.Map.SortedListString.
Require Import coqutil.Word.Interface coqutil.Word.Bitwidth32 coqutil.Map.SortedListWord.
Require coqutil.Word.Naive.

Instance word: word.word 32 := Naive.word32.
Instance mem: Interface.map.map word Byte.byte := SortedListWord.map _ _.
Instance locals: Interface.map.map String.string word := SortedListString.map _.
Instance env: Interface.map.map String.string (list String.string * list String.string * cmd) :=
  SortedListString.map _.
Instance ext_spec: ExtSpec := fun _ _ _ _ _ => False.

Arguments word: simpl never.
Arguments mem: simpl never.
Arguments locals: simpl never.
Arguments env: simpl never.

Instance weaken_ext_spec trace m0 act args :
  Morphisms.Proper
    (Morphisms.respectful
       (Morphisms.pointwise_relation Interface.map.rep
          (Morphisms.pointwise_relation (list word) Basics.impl))
       Basics.impl) (ext_spec trace m0 act args).
Proof.
  cbn in *.
  unfold Morphisms.Proper, Morphisms.respectful, Morphisms.pointwise_relation, Basics.impl.
  intros.
  assumption.
Qed.

Instance localsok: coqutil.Map.Interface.map.ok locals := SortedListString.ok _.
Instance envok: coqutil.Map.Interface.map.ok env := SortedListString.ok _.
Instance mapok: coqutil.Map.Interface.map.ok mem := SortedListWord.ok Naive.word32 _.
Instance wordok: coqutil.Word.Interface.word.ok word := Naive.word32_ok.
Add Ring wring : (Properties.word.ring_theory (word := word))
      (preprocess [autorewrite with rew_word_morphism],
       morphism (Properties.word.ring_morph (word := word)),
       constants [Properties.word_cst]).

Instance ext_spec_ok : ext_spec.ok ext_spec.
Proof.
  constructor; intros; try contradiction.
  apply weaken_ext_spec.
Qed.

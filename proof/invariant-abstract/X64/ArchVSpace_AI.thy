(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

(*
ARM-specific VSpace invariants
*)

theory ArchVSpace_AI
imports "../VSpacePre_AI"
begin

context Arch begin global_naming X64

abbreviation "canonicalise x \<equiv> (scast ((ucast x) :: 48 word)) :: 64 word"

(* FIXME x64: this needs canonical_address shenanigans *)
lemma pptr_base_shift_cast_le:
  fixes x :: "9 word"
  shows  "((pptr_base >> pml4_shift_bits) && mask ptTranslationBits \<le> ucast x) =
        (ucast (pptr_base >> pml4_shift_bits) \<le> x)"
  apply (subgoal_tac "((pptr_base >> pml4_shift_bits) && mask ptTranslationBits) = ucast (ucast (pptr_base >> pml4_shift_bits) :: 9 word)")
   prefer 2
   apply (simp add: ucast_ucast_mask ptTranslationBits_def)
  apply (simp add: ucast_le_ucast)
  done

(* FIXME: move to Invariant_AI *)
definition
  glob_vs_refs_arch :: "arch_kernel_obj \<Rightarrow> (vs_ref \<times> obj_ref) set"
  where  "glob_vs_refs_arch \<equiv> \<lambda>ko. case ko of
    ASIDPool pool \<Rightarrow>
      (\<lambda>(r,p). (VSRef (ucast r) (Some AASIDPool), p)) ` graph_of pool
  | PageMapL4 pm \<Rightarrow>
      (\<lambda>(r,p). (VSRef (ucast r) (Some APageMapL4), p)) ` graph_of (pml4e_ref \<circ> pm)
  | PDPointerTable pdpt \<Rightarrow>
      (\<lambda>(r,p). (VSRef (ucast r) (Some APDPointerTable), p)) ` graph_of (pdpte_ref \<circ> pdpt)
  | PageDirectory pd \<Rightarrow>
      (\<lambda>(r,p). (VSRef (ucast r) (Some APageDirectory), p)) ` graph_of (pde_ref \<circ> pd)
  | _ \<Rightarrow> {}"

declare glob_vs_refs_arch_def[simp]

definition
  "glob_vs_refs \<equiv> arch_obj_fun_lift glob_vs_refs_arch {}"

crunch pspace_in_kernel_window[wp]: unmap_page, perform_page_invocation "pspace_in_kernel_window"
  (simp: crunch_simps wp: crunch_wps)

definition
  "vspace_at_uniq asid pd \<equiv> \<lambda>s. pd \<notin> ran (x64_asid_map (arch_state s) |` (- {asid}))"

crunch inv[wp]: find_vspace_for_asid_assert "P"
  (simp: crunch_simps)

lemma asid_word_bits [simp]: "asid_bits < word_bits"
  by (simp add: asid_bits_def word_bits_def)


lemma asid_low_high_bits:
  "\<lbrakk> x && mask asid_low_bits = y && mask asid_low_bits;
    ucast (asid_high_bits_of x) = (ucast (asid_high_bits_of y)::machine_word);
    x \<le> 2 ^ asid_bits - 1; y \<le> 2 ^ asid_bits - 1 \<rbrakk>
  \<Longrightarrow> x = y"
  apply (rule word_eqI)
  apply (simp add: upper_bits_unset_is_l2p_64 [symmetric] bang_eq nth_ucast word_size)
  apply (clarsimp simp: asid_high_bits_of_def nth_ucast nth_shiftr)
  apply (simp add: asid_high_bits_def asid_bits_def asid_low_bits_def word_bits_def)
  subgoal premises prems[rule_format] for n
  apply (cases "n < 9")
   using prems(1)
   apply fastforce
  apply (cases "n < 12")
   using prems(2)[where n="n - 9"]
   apply fastforce
  using prems(3-)
  by (simp add: linorder_not_less)
  done

lemma asid_low_high_bits':
  "\<lbrakk> ucast x = (ucast y :: 9 word);
    asid_high_bits_of x = asid_high_bits_of y;
    x \<le> 2 ^ asid_bits - 1; y \<le> 2 ^ asid_bits - 1 \<rbrakk>
  \<Longrightarrow> x = y"
  apply (rule asid_low_high_bits)
     apply (rule word_eqI)
     apply (subst (asm) bang_eq)
     apply (simp add: nth_ucast asid_low_bits_def word_size)
    apply (rule word_eqI)
    apply (subst (asm) bang_eq)+
    apply (simp add: nth_ucast asid_low_bits_def)
   apply assumption+
  done

lemma table_cap_ref_at_eq:
  "table_cap_ref c = Some [x] \<longleftrightarrow> vs_cap_ref c = Some [x]"
  by (auto simp: table_cap_ref_def vs_cap_ref_simps vs_cap_ref_def
          split: cap.splits arch_cap.splits vmpage_size.splits option.splits)

lemma table_cap_ref_ap_eq:
  "table_cap_ref c = Some [x,y] \<longleftrightarrow> vs_cap_ref c = Some [x,y]"
  by (auto simp: table_cap_ref_def vs_cap_ref_simps vs_cap_ref_def
          split: cap.splits arch_cap.splits vmpage_size.splits option.splits)

lemma vspace_at_asid_unique:
  "\<lbrakk> vspace_at_asid asid pm s; vspace_at_asid asid' pm s;
     unique_table_refs (caps_of_state s);
     valid_vs_lookup s; valid_arch_objs s; valid_global_objs s;
     valid_arch_state s; asid < 2 ^ asid_bits; asid' < 2 ^ asid_bits \<rbrakk>
       \<Longrightarrow> asid = asid'"
  apply (clarsimp simp: vspace_at_asid_def)
  apply (drule(1) valid_vs_lookupD[OF vs_lookup_pages_vs_lookupI])+
  apply (clarsimp simp: table_cap_ref_ap_eq[symmetric])
  apply (clarsimp simp: table_cap_ref_def
                 split: cap.split_asm arch_cap.split_asm option.split_asm)
  apply (drule(2) unique_table_refsD,
         simp+, clarsimp simp: table_cap_ref_def,
         erule(1) asid_low_high_bits)
   apply simp+
  done

lemma vspace_at_asid_unique2:
  "\<lbrakk> vspace_at_asid asid pm s; vspace_at_asid asid pm' s \<rbrakk>
         \<Longrightarrow> pm = pm'"
  apply (clarsimp simp: vspace_at_asid_def vs_asid_refs_def
                 dest!: graph_ofD vs_lookup_2ConsD vs_lookup_atD
                        vs_lookup1D)
  apply (clarsimp simp: obj_at_def vs_refs_def
                 split: kernel_object.splits
                        arch_kernel_obj.splits
                 dest!: graph_ofD)
  done


lemma vspace_at_asid_uniq:
  "\<lbrakk> vspace_at_asid asid pml4 s; asid \<le> mask asid_bits; valid_asid_map s;
      unique_table_refs (caps_of_state s); valid_vs_lookup s;
      valid_arch_objs s; valid_global_objs s; valid_arch_state s \<rbrakk>
       \<Longrightarrow> vspace_at_uniq asid pml4 s"
  apply (clarsimp simp: vspace_at_uniq_def ran_option_map
                 dest!: ran_restrictD)
  apply (clarsimp simp: valid_asid_map_def)
  apply (drule bspec, erule graph_ofI)
  apply clarsimp
  apply (rule vspace_at_asid_unique, assumption+)
   apply (drule subsetD, erule domI)
   apply (simp add: mask_def)
  apply (simp add: mask_def)
  done


lemma valid_vs_lookupE:
  "\<lbrakk> valid_vs_lookup s; \<And>ref p. (ref \<unrhd> p) s' \<Longrightarrow> (ref \<unrhd> p) s;
           set (x64_global_pdpts (arch_state s)) \<subseteq> set (x64_global_pdpts (arch_state s'));
           caps_of_state s = caps_of_state s' \<rbrakk>
     \<Longrightarrow> valid_vs_lookup s'"
  by (simp add: valid_vs_lookup_def, blast)


lemma dmo_vspace_at_asid [wp]:
  "\<lbrace>vspace_at_asid a pd\<rbrace> do_machine_op f \<lbrace>\<lambda>_. vspace_at_asid a pd\<rbrace>"
  apply (simp add: do_machine_op_def split_def)
  apply wp
  apply (simp add: vspace_at_asid_def)
  done

crunch inv: find_vspace_for_asid "P"
  (simp: assertE_def whenE_def wp: crunch_wps)


lemma find_vspace_for_asid_vspace_at_asid [wp]:
  "\<lbrace>\<top>\<rbrace> find_vspace_for_asid asid \<lbrace>\<lambda>pd. vspace_at_asid asid pd\<rbrace>, -"
  apply (simp add: find_vspace_for_asid_def assertE_def split del: if_split)
  apply (rule hoare_pre)
   apply (wp|wpc)+
  apply (clarsimp simp: vspace_at_asid_def)
  apply (rule vs_lookupI)
   apply (simp add: vs_asid_refs_def graph_of_def)
   apply fastforce
  apply (rule r_into_rtrancl)
  apply (erule vs_lookup1I)
   prefer 2
   apply (rule refl)
  apply (simp add: vs_refs_def graph_of_def mask_asid_low_bits_ucast_ucast)
  apply fastforce
  done

crunch valid_vs_lookup[wp]: do_machine_op "valid_vs_lookup"

lemma valid_asid_mapD:
  "\<lbrakk> x64_asid_map (arch_state s) asid = Some pml4; valid_asid_map s \<rbrakk>
      \<Longrightarrow> vspace_at_asid asid pml4 s \<and> asid \<le> mask asid_bits"
  by (auto simp add: valid_asid_map_def graph_of_def)


lemma pml4_cap_vspace_at_uniq:
  "\<lbrakk> cte_wp_at (op = (ArchObjectCap (PML4Cap pml4 (Some asid)))) slot s;
     valid_asid_map s; valid_vs_lookup s; unique_table_refs (caps_of_state s);
     valid_arch_state s; valid_global_objs s; valid_objs s \<rbrakk>
          \<Longrightarrow> vspace_at_uniq asid pml4 s"
  apply (frule(1) cte_wp_at_valid_objs_valid_cap)
  apply (clarsimp simp: vspace_at_uniq_def restrict_map_def valid_cap_def
                        elim!: ranE split: if_split_asm)
  apply (drule(1) valid_asid_mapD)
  apply (clarsimp simp: vspace_at_asid_def)
  apply (frule(1) valid_vs_lookupD[OF vs_lookup_pages_vs_lookupI])
  apply (clarsimp simp: cte_wp_at_caps_of_state dest!: obj_ref_elemD)
  apply (drule(1) unique_table_refsD[rotated, where cps="caps_of_state s"],
         simp+)
  apply (clarsimp simp: table_cap_ref_ap_eq[symmetric] table_cap_ref_def
                 split: cap.splits arch_cap.splits option.splits)
  apply (drule(1) asid_low_high_bits, simp_all add: mask_def)
  done

lemma invalidateTLB_underlying_memory:
  "\<lbrace>\<lambda>m'. underlying_memory m' p = um\<rbrace>
   invalidateTLB
   \<lbrace>\<lambda>_ m'. underlying_memory m' p = um\<rbrace>"
  by (clarsimp simp: invalidateTLB_def machine_op_lift_def
                     machine_rest_lift_def split_def | wp)+


lemma vspace_at_asid_arch_up':
  "x64_asid_table (f (arch_state s)) = x64_asid_table (arch_state s)
    \<Longrightarrow> vspace_at_asid asid pml4 (arch_state_update f s) = vspace_at_asid asid pml4 s"
  by (clarsimp simp add: vspace_at_asid_def vs_lookup_def vs_lookup1_def)


lemma vspace_at_asid_arch_up:
  "vspace_at_asid asid pml4 (s\<lparr>arch_state := arch_state s \<lparr>x64_asid_map := a\<rparr>\<rparr>) =
  vspace_at_asid asid pml4 s"
  by (simp add: vspace_at_asid_arch_up')


lemmas ackInterrupt_irq_masks = no_irq[OF no_irq_ackInterrupt]


lemma ucast_ucast_low_bits:
  fixes x :: machine_word
  shows "x \<le> 2^asid_low_bits - 1 \<Longrightarrow> ucast (ucast x:: 9 word) = x"
  apply (simp add: ucast_ucast_mask)
  apply (rule less_mask_eq)
  apply (subst (asm) word_less_sub_le)
   apply (simp add: asid_low_bits_def word_bits_def)
  apply (simp add: asid_low_bits_def)
  done


lemma asid_high_bits_of_or:
 "x \<le> 2^asid_low_bits - 1 \<Longrightarrow> asid_high_bits_of (base || x) = asid_high_bits_of base"
  apply (rule word_eqI)
  apply (drule le_2p_upper_bits)
   apply (simp add: asid_low_bits_def word_bits_def)
  apply (simp add: asid_high_bits_of_def word_size nth_ucast nth_shiftr asid_low_bits_def word_bits_def)
  done


lemma vs_lookup_clear_asid_table:
  "(rf \<rhd> p) (s\<lparr>arch_state := arch_state s
                \<lparr>x64_asid_table := (x64_asid_table (arch_state s))
                   (pptr := None)\<rparr>\<rparr>)
        \<longrightarrow> (rf \<rhd> p) s"
  apply (simp add: vs_lookup_def vs_lookup1_def)
  apply (rule impI, erule subsetD[rotated])
  apply (rule Image_mono[OF order_refl])
  apply (simp add: vs_asid_refs_def graph_of_def)
  apply (rule image_mono)
  apply (clarsimp split: if_split_asm)
  done


lemma vs_lookup_pages_clear_asid_table:
  "(rf \<unrhd> p) (s\<lparr>arch_state := arch_state s
                \<lparr>x64_asid_table := (x64_asid_table (arch_state s))
                   (pptr := None)\<rparr>\<rparr>)
   \<Longrightarrow> (rf \<unrhd> p) s"
  apply (simp add: vs_lookup_pages_def vs_lookup_pages1_def)
  apply (erule subsetD[rotated])
  apply (rule Image_mono[OF order_refl])
  apply (simp add: vs_asid_refs_def graph_of_def)
  apply (rule image_mono)
  apply (clarsimp split: if_split_asm)
  done


lemma valid_arch_state_unmap_strg:
  "valid_arch_state s \<longrightarrow>
   valid_arch_state(s\<lparr>arch_state := arch_state s\<lparr>x64_asid_table := (x64_asid_table (arch_state s))(ptr := None)\<rparr>\<rparr>)"
  apply (clarsimp simp: valid_arch_state_def valid_asid_table_def)
  apply (rule conjI)
   apply (clarsimp simp add: ran_def)
   apply blast
  apply (clarsimp simp: inj_on_def)
  done


lemma valid_arch_objs_unmap_strg:
  "valid_arch_objs s \<longrightarrow>
   valid_arch_objs(s\<lparr>arch_state := arch_state s\<lparr>x64_asid_table := (x64_asid_table (arch_state s))(ptr := None)\<rparr>\<rparr>)"
  apply (clarsimp simp: valid_arch_objs_def)
  apply (drule vs_lookup_clear_asid_table [rule_format])
  apply blast
  done


lemma valid_vs_lookup_unmap_strg:
  "valid_vs_lookup s \<longrightarrow>
   valid_vs_lookup(s\<lparr>arch_state := arch_state s\<lparr>x64_asid_table := (x64_asid_table (arch_state s))(ptr := None)\<rparr>\<rparr>)"
  apply (clarsimp simp: valid_vs_lookup_def)
  apply (drule vs_lookup_pages_clear_asid_table)
  apply blast
  done


lemma ex_asid_high_bits_plus:
  "asid \<le> mask asid_bits \<Longrightarrow> \<exists>x \<le> 2^asid_low_bits - 1. asid = (ucast (asid_high_bits_of asid) << asid_low_bits) + x"
  apply (rule_tac x="asid && mask asid_low_bits" in exI)
  apply (rule conjI)
   apply (simp add: mask_def)
   apply (rule word_and_le1)
  apply (subst (asm) mask_def)
  apply (simp add: upper_bits_unset_is_l2p_64 [symmetric])
  apply (subst word_plus_and_or_coroll)
   apply (rule word_eqI)
   apply (clarsimp simp: word_size nth_ucast nth_shiftl)
  apply (rule word_eqI)
  apply (clarsimp simp: word_size nth_ucast nth_shiftl nth_shiftr asid_high_bits_of_def
                        asid_low_bits_def word_bits_def asid_bits_def)
  apply (rule iffI)
   prefer 2
   apply fastforce
  apply (clarsimp simp: linorder_not_less)
  apply (rule conjI)
   prefer 2
   apply arith
  apply (subgoal_tac "n < 12", simp)
  apply (clarsimp simp add: linorder_not_le [symmetric])
  done


lemma asid_high_bits_shl:
  "\<lbrakk> is_aligned base asid_low_bits; base \<le> mask asid_bits \<rbrakk> \<Longrightarrow> ucast (asid_high_bits_of base) << asid_low_bits = base"
  apply (simp add: mask_def upper_bits_unset_is_l2p_64 [symmetric])
  apply (rule word_eqI)
  apply (simp add: is_aligned_nth nth_ucast nth_shiftl nth_shiftr asid_low_bits_def
                   asid_high_bits_of_def word_size asid_bits_def word_bits_def)
  apply (rule iffI, clarsimp)
  apply (rule context_conjI)
   apply (clarsimp simp add: linorder_not_less [symmetric])
  apply simp
  apply (rule conjI)
   prefer 2
   apply simp
  apply (subgoal_tac "n < 12", simp)
  apply (clarsimp simp add: linorder_not_le [symmetric])
  done


lemma valid_asid_map_unmap:
  "valid_asid_map s \<and> is_aligned base asid_low_bits \<and> base \<le> mask asid_bits \<and>
   (\<forall>x \<in> set [0.e.2^asid_low_bits - 1]. x64_asid_map (arch_state s) (base + x) = None) \<longrightarrow>
   valid_asid_map(s\<lparr>arch_state := arch_state s\<lparr>x64_asid_table := (x64_asid_table (arch_state s))(asid_high_bits_of base := None)\<rparr>\<rparr>)"
  apply (clarsimp simp: valid_asid_map_def vspace_at_asid_def)
  apply (drule bspec, blast)
  apply clarsimp
  apply (erule vs_lookupE)
  apply (clarsimp simp: vs_asid_refs_def dest!: graph_ofD)
  apply (frule vs_lookup1_trans_is_append, clarsimp)
  apply (drule ucast_up_inj, simp)
  apply clarsimp
  apply (rule_tac ref'="([VSRef (ucast (asid_high_bits_of a)) None],ba)" in vs_lookupI)
   apply (simp add: vs_asid_refs_def)
   apply (simp add: graph_of_def)
   apply (rule_tac x="(asid_high_bits_of a, ba)" in image_eqI)
    apply simp
   apply clarsimp
   apply (subgoal_tac "a \<le> mask asid_bits")
    prefer 2
    apply fastforce
   apply (drule_tac asid=a in ex_asid_high_bits_plus)
   apply (clarsimp simp: asid_high_bits_shl)
  apply (drule rtranclD, simp)
  apply (drule tranclD)
  apply clarsimp
  apply (drule vs_lookup1D)
  apply clarsimp
  apply (frule vs_lookup1_trans_is_append, clarsimp)
  apply (drule vs_lookup_trans_ptr_eq, clarsimp)
  apply (rule r_into_rtrancl)
  apply (rule vs_lookup1I)
    apply simp
   apply assumption
  apply simp
  done


lemma asid_low_bits_word_bits:
  "asid_low_bits < word_bits"
  by (simp add: asid_low_bits_def word_bits_def)


lemma valid_global_objs_arch_update:
  "x64_global_pml4 (f (arch_state s)) = x64_global_pml4 (arch_state s)
    \<and> x64_global_pdpts (f (arch_state s)) = x64_global_pdpts (arch_state s)
    \<and> x64_global_pds (f (arch_state s)) = x64_global_pds (arch_state s)
    \<and> x64_global_pts (f (arch_state s)) = x64_global_pts (arch_state s)
     \<Longrightarrow> valid_global_objs (arch_state_update f s) = valid_global_objs s"
  by (simp add: valid_global_objs_def)


crunch pred_tcb_at [wp]: find_vspace_for_asid "\<lambda>s. P (pred_tcb_at proj Q p s)"
  (simp: crunch_simps)


lemma find_vspace_for_asid_assert_wp:
  "\<lbrace>\<lambda>s. \<forall>pd. vspace_at_asid asid pd s \<and> asid \<noteq> 0 \<longrightarrow> P pd s\<rbrace> find_vspace_for_asid_assert asid \<lbrace>P\<rbrace>"
  apply (simp add: find_vspace_for_asid_assert_def
                   find_vspace_for_asid_def assertE_def
                 split del: if_split)
  apply (rule hoare_pre)
   apply (wp get_pde_wp get_asid_pool_wp | wpc)+
  apply clarsimp
  apply (drule spec, erule mp)
  apply (clarsimp simp: vspace_at_asid_def word_neq_0_conv)
  apply (rule vs_lookupI)
   apply (simp add: vs_asid_refs_def)
   apply (rule image_eqI[OF refl])
   apply (erule graph_ofI)
  apply (rule r_into_rtrancl, simp)
  apply (erule vs_lookup1I)
   apply (simp add: vs_refs_def)
   apply (rule image_eqI[rotated])
    apply (erule graph_ofI)
   apply simp
  apply (simp add: mask_asid_low_bits_ucast_ucast)
  done

lemma valid_vs_lookup_arch_update:
  "x64_asid_table (f (arch_state s)) = x64_asid_table (arch_state s)
     \<Longrightarrow> valid_vs_lookup (arch_state_update f s) = valid_vs_lookup s"
  by (simp add: valid_vs_lookup_def vs_lookup_pages_arch_update)

crunch typ_at [wp]: find_vspace_for_asid "\<lambda>s. P (typ_at T p s)"

lemmas find_vspace_for_asid_typ_ats [wp] = abs_typ_at_lifts [OF find_vspace_for_asid_typ_at]

lemma find_vspace_for_asid_page_map_l4 [wp]:
  "\<lbrace>valid_arch_objs\<rbrace>
  find_vspace_for_asid asid
  \<lbrace>\<lambda>pd. page_map_l4_at pd\<rbrace>, -"
  apply (simp add: find_vspace_for_asid_def assertE_def whenE_def split del: if_split)
  apply (wp|wpc|clarsimp|rule conjI)+
  apply (drule vs_lookup_atI)
  apply (drule (2) valid_arch_objsD)
  apply clarsimp
  apply (drule bspec, blast)
  apply (clarsimp simp: obj_at_def)
  done


lemma find_vspace_for_asid_lookup_ref:
  "\<lbrace>\<top>\<rbrace> find_vspace_for_asid asid \<lbrace>\<lambda>pd. ([VSRef (asid && mask asid_low_bits) (Some AASIDPool),
                                      VSRef (ucast (asid_high_bits_of asid)) None] \<rhd> pd)\<rbrace>, -"
  apply (simp add: find_vspace_for_asid_def assertE_def whenE_def split del: if_split)
  apply (wp|wpc|clarsimp|rule conjI)+
  apply (drule vs_lookup_atI)
  apply (erule vs_lookup_step)
  apply (erule vs_lookup1I [OF _ _ refl])
  apply (simp add: vs_refs_def)
  apply (rule image_eqI[rotated], erule graph_ofI)
  apply (simp add: mask_asid_low_bits_ucast_ucast)
  done


lemma find_vspace_for_asid_lookup[wp]:
  "\<lbrace>\<top>\<rbrace> find_vspace_for_asid asid \<lbrace>\<lambda>pd. \<exists>\<rhd> pd\<rbrace>,-"
  apply (rule hoare_post_imp_R, rule find_vspace_for_asid_lookup_ref)
  apply auto
  done


lemma find_vspace_for_asid_pde [wp]:
  "\<lbrace>valid_arch_objs and pspace_aligned\<rbrace>
  find_vspace_for_asid asid
  \<lbrace>\<lambda>pd. pml4e_at (pd + (get_pml4_index vptr << word_size_bits))\<rbrace>, -"
proof -
  have x:
    "\<lbrace>valid_arch_objs and pspace_aligned\<rbrace> find_vspace_for_asid asid
     \<lbrace>\<lambda>pd. pspace_aligned and page_map_l4_at pd\<rbrace>, -"
    by (rule hoare_pre) (wp, simp)
  show ?thesis
    apply (rule hoare_post_imp_R, rule x)
    apply clarsimp
    apply (erule page_map_l4_pml4e_atI)
     prefer 2
     apply assumption
    apply (rule vptr_shiftr_le_2p)
    done
qed

lemma vs_lookup1_rtrancl_iterations:
  "(tup, tup') \<in> (vs_lookup1 s)\<^sup>*
    \<Longrightarrow> (length (fst tup) \<le> length (fst tup')) \<and>
       (tup, tup') \<in> ((vs_lookup1 s)
           ^^ (length (fst tup') - length (fst tup)))"
  apply (erule rtrancl_induct)
   apply simp
  apply (elim conjE)
  apply (subgoal_tac "length (fst z) = Suc (length (fst y))")
   apply (simp add: Suc_diff_le)
   apply (erule(1) relcompI)
  apply (clarsimp simp: vs_lookup1_def)
  done


lemma find_vspace_for_asid_lookup_none:
  "\<lbrace>\<top>\<rbrace>
    find_vspace_for_asid asid
   -, \<lbrace>\<lambda>e s. \<forall>p. \<not> ([VSRef (asid && mask asid_low_bits) (Some AASIDPool),
   VSRef (ucast (asid_high_bits_of asid)) None] \<rhd> p) s\<rbrace>"
  apply (simp add: find_vspace_for_asid_def assertE_def
                 split del: if_split)
  apply (rule hoare_pre)
   apply (wp | wpc)+
  apply clarsimp
  apply (intro allI conjI impI)
   apply (clarsimp simp: vs_lookup_def vs_asid_refs_def up_ucast_inj_eq
                  dest!: vs_lookup1_rtrancl_iterations
                         graph_ofD vs_lookup1D)
  apply (clarsimp simp: vs_lookup_def vs_asid_refs_def
                 dest!: vs_lookup1_rtrancl_iterations
                        graph_ofD vs_lookup1D)
  apply (clarsimp simp: obj_at_def vs_refs_def up_ucast_inj_eq
                        mask_asid_low_bits_ucast_ucast
                 dest!: graph_ofD)
  done


lemma find_vspace_for_asid_aligned_pm [wp]:
  "\<lbrace>pspace_aligned and valid_arch_objs\<rbrace> find_vspace_for_asid asid \<lbrace>\<lambda>rv s. is_aligned rv table_size\<rbrace>,-"
  apply (simp add: find_vspace_for_asid_def assertE_def split del: if_split)
  apply (rule hoare_pre)
   apply (wp|wpc)+
  apply clarsimp
  apply (drule vs_lookup_atI)
  apply (drule (2) valid_arch_objsD)
  apply clarsimp
  apply (drule bspec, blast)
  apply (thin_tac "ko_at ko p s" for ko p)
  apply (clarsimp simp: pspace_aligned_def obj_at_def)
  apply (drule bspec, blast)
  apply (clarsimp simp: a_type_def bit_simps
                  split: Structures_A.kernel_object.splits arch_kernel_obj.splits if_split_asm)
  done

lemma find_vspace_for_asid_aligned_pm_bits[wp]:
  "\<lbrace>pspace_aligned and valid_arch_objs\<rbrace>
      find_vspace_for_asid asid
   \<lbrace>\<lambda>rv s. is_aligned rv pml4_bits\<rbrace>, -"
  by (simp add: pml4_bits_def pageBits_def, rule find_vspace_for_asid_aligned_pm)

lemma find_vspace_for_asid_lots:
  "\<lbrace>\<lambda>s. (\<forall>rv. ([VSRef (asid && mask asid_low_bits) (Some AASIDPool),
   VSRef (ucast (asid_high_bits_of asid)) None] \<rhd> rv) s
           \<longrightarrow> (valid_arch_objs s \<longrightarrow> page_map_l4_at rv s)
           \<longrightarrow> Q rv s)
       \<and> ((\<forall>rv. \<not> ([VSRef (asid && mask asid_low_bits) (Some AASIDPool),
   VSRef (ucast (asid_high_bits_of asid)) None] \<rhd> rv) s) \<longrightarrow> (\<forall>e. E e s))\<rbrace>
    find_vspace_for_asid asid
  \<lbrace>Q\<rbrace>,\<lbrace>E\<rbrace>"
  apply (clarsimp simp: validE_def valid_def)
  apply (frule in_inv_by_hoareD [OF find_vspace_for_asid_inv])
  apply (frule use_valid [OF _ find_vspace_for_asid_lookup_none
                                [unfolded validE_E_def validE_def]])
   apply simp
  apply (frule use_valid [OF _ find_vspace_for_asid_lookup_ref
                                [unfolded validE_R_def validE_def]])
   apply simp
  apply (clarsimp split: sum.split_asm)
  apply (drule spec, drule uncurry, erule mp)
  apply clarsimp
  apply (frule use_valid [OF _ find_vspace_for_asid_page_map_l4
                                [unfolded validE_R_def validE_def]])
   apply simp
  apply simp
  done

lemma vs_lookup1_inj:
  "\<lbrakk> ((ref, p), (ref', p')) \<in> vs_lookup1 s ^^ n;
     ((ref, p), (ref', p'')) \<in> vs_lookup1 s ^^ n \<rbrakk>
       \<Longrightarrow> p' = p''"
  apply (induct n arbitrary: ref ref' p p' p'')
   apply simp
  apply (clarsimp dest!: vs_lookup1D)
  apply (subgoal_tac "pa = pb", simp_all)
  apply (simp add: obj_at_def)
  apply (auto simp: vs_refs_def up_ucast_inj_eq dest!: graph_ofD
             split: Structures_A.kernel_object.split_asm arch_kernel_obj.split_asm)
  done

lemma vs_lookup_Cons_eq:
  "(ref \<rhd> p) s \<Longrightarrow> ((v # ref) \<rhd> p') s = ((ref, p) \<rhd>1 (v # ref, p')) s"
  apply (rule iffI)
   apply (clarsimp simp: vs_lookup_def vs_asid_refs_def
                  dest!: graph_ofD)
   apply (frule vs_lookup1_trans_is_append[where ys=ref])
   apply (frule vs_lookup1_trans_is_append[where ys="v # ref"])
   apply (clarsimp dest!: vs_lookup1_rtrancl_iterations vs_lookup1D)
   apply (clarsimp simp add: up_ucast_inj_eq)
   apply (drule(1) vs_lookup1_inj)
   apply (simp add: vs_lookup1I)
  apply (erule vs_lookup_trancl_step)
  apply simp
  done

definition
  valid_unmap :: "vmpage_size \<Rightarrow> asid * vspace_ref \<Rightarrow> bool"
where
  "valid_unmap sz \<equiv> \<lambda>(asid, vptr). 0 < asid \<and> is_aligned vptr (pageBitsForSize sz)"

lemma lookup_pdpt_slot_is_aligned:
  "\<lbrace>(\<exists>\<rhd> pm) and K (vmsz_aligned vptr sz) and K (is_aligned pm pml4_bits)
    and valid_arch_state and valid_arch_objs and equal_kernel_mappings
    and pspace_aligned and valid_global_objs\<rbrace>
     lookup_pdpt_slot pm vptr
   \<lbrace>\<lambda>rv s. is_aligned rv word_size_bits\<rbrace>,-"
  apply (simp add: lookup_pdpt_slot_def)
  apply (wp get_pml4e_wp | wpc)+
  apply (clarsimp simp: lookup_pml4_slot_eq)
  apply (frule(2) valid_arch_objsD[rotated])
  apply simp
  apply (rule is_aligned_add)
   apply (case_tac "ucast (lookup_pml4_slot pm vptr && mask pml4_bits >> word_size_bits) \<in> kernel_mapping_slots")
    apply (frule kernel_mapping_slots_empty_pml4eI)
     apply (simp add: obj_at_def)+
    apply (erule_tac x="ptrFromPAddr x" in allE)
    apply (simp add: pml4e_ref_def)
    apply (erule is_aligned_weaken[OF is_aligned_global_pdpt])
      apply ((simp add: invs_psp_aligned invs_arch_objs invs_arch_state
                        pdpt_bits_def pageBits_def bit_simps
                 split: vmpage_size.split)+)[3]
   apply (drule_tac x="ucast (lookup_pml4_slot pm vptr && mask pml4_bits >> word_size_bits)" in bspec, simp)
   apply (clarsimp simp: obj_at_def a_type_def)
   apply (simp split: Structures_A.kernel_object.split_asm if_split_asm
                     arch_kernel_obj.split_asm)
   apply (erule is_aligned_weaken[OF pspace_alignedD], simp)
   apply (simp add: obj_bits_def bit_simps  split: vmpage_size.splits)
  apply (rule is_aligned_shiftl)
  apply (simp add: bit_simps)
  done

(* FIXME x64: need pd, pt versions of this *)
lemma lookup_pd_slot_is_aligned:
  "\<lbrace>(\<exists>\<rhd> pm) and K (vmsz_aligned vptr sz) and K (is_aligned pm pml4_bits)
    and valid_arch_state and valid_arch_objs and equal_kernel_mappings
    and pspace_aligned and valid_global_objs\<rbrace>
     lookup_pd_slot pm vptr
   \<lbrace>\<lambda>rv s. is_aligned rv word_size_bits\<rbrace>,-"
  oops (*
  apply (simp add: lookup_pd_slot_def)
  apply (rule hoare_pre)
   apply (wp get_pdpte_wp hoare_vcg_all_lift_R | wpc | simp)+
   apply (wp_once hoare_drop_imps)
   apply (wp hoare_vcg_all_lift_R hoare_vcg_ex_lift_R)
  apply (clarsimp simp: get_pd_index_def bit_simps)
  apply (subgoal_tac "is_aligned (ptrFromPAddr x) word_size_bits")
  apply (clarsimp simp: lookup_pml4_slot_eq)
  apply (frule(2) valid_arch_objsD[rotated])
  apply simp
  apply (rule is_aligned_add)
   apply (case_tac "ucast (lookup_pml4_slot pm vptr && mask pml4_bits >> word_size_bits) \<in> kernel_mapping_slots")
    apply (frule kernel_mapping_slots_empty_pml4eI)
     apply (simp add: obj_at_def)+
    apply (erule_tac x="ptrFromPAddr x" in allE)
    apply (simp add: pml4e_ref_def)
    apply (erule is_aligned_weaken[OF is_aligned_global_pdpt])
      apply ((simp add: invs_psp_aligned invs_arch_objs invs_arch_state
                        pdpt_bits_def pageBits_def bit_simps
                 split: vmpage_size.split)+)[3]
   apply (drule_tac x="ucast (lookup_pml4_slot pm vptr && mask pml4_bits >> word_size_bits)" in bspec, simp)
   apply (clarsimp simp: obj_at_def a_type_def)
   apply (simp split: Structures_A.kernel_object.split_asm if_split_asm
                     arch_kernel_obj.split_asm)
   apply (erule is_aligned_weaken[OF pspace_alignedD], simp)
   apply (simp add: obj_bits_def bit_simps  split: vmpage_size.splits)
  apply (rule is_aligned_shiftl)
  apply (simp add: bit_simps)
  done *)

lemma pd_pointer_table_at_aligned_pdpt_bits:
  "\<lbrakk>pd_pointer_table_at pdpt s;pspace_aligned s\<rbrakk>
       \<Longrightarrow> is_aligned pdpt pdpt_bits"
  apply (clarsimp simp:obj_at_def)
  apply (drule(1) pspace_alignedD)
  apply (simp add:pdpt_bits_def pageBits_def)
  done

lemma page_directory_at_aligned_pd_bits:
  "\<lbrakk>page_directory_at pd s;pspace_aligned s\<rbrakk>
       \<Longrightarrow> is_aligned pd pd_bits"
  apply (clarsimp simp:obj_at_def)
  apply (drule(1) pspace_alignedD)
  apply (simp add:pd_bits_def pageBits_def)
  done

lemma page_map_l4_at_aligned_pml4_bits:
  "\<lbrakk>page_map_l4_at pm s;pspace_aligned s\<rbrakk>
       \<Longrightarrow> is_aligned pm pml4_bits"
  apply (clarsimp simp:obj_at_def)
  apply (drule(1) pspace_alignedD)
  apply (simp add:pml4_bits_def pageBits_def)
  done

(* FIXME x64: check *)
definition
  "empty_refs m \<equiv> case m of (VMPDE pde, _) \<Rightarrow> pde_ref pde = None
                          | (VMPDPTE pdpte, _) \<Rightarrow> pdpte_ref pdpte = None
                      | _ \<Rightarrow> True"

definition
  "parent_for_refs entry \<equiv> \<lambda>cap.
     case entry of (VMPTE _, slot)
        \<Rightarrow> slot \<in> obj_refs cap \<and> is_pt_cap cap \<and> cap_asid cap \<noteq> None
      | (VMPDE _, slot)
        \<Rightarrow> slot \<in> obj_refs cap \<and> is_pd_cap cap \<and> cap_asid cap \<noteq> None
      | (VMPDPTE _, slot)
        \<Rightarrow> slot \<in> obj_refs cap \<and> is_pdpt_cap cap \<and> cap_asid cap \<noteq> None
      | (VMPML4E _, _) \<Rightarrow> True"

(* FIXME x64: check *)
definition
  "same_refs m cap s \<equiv>
      case m of
       (VMPTE pte, slot) \<Rightarrow>
         (\<exists>p. pte_ref_pages pte = Some p \<and> p \<in> obj_refs cap) \<and>
         (\<forall>ref. (ref \<rhd> (slot && ~~ mask pt_bits)) s \<longrightarrow>
           vs_cap_ref cap = Some (VSRef ((slot && mask table_size >> word_size_bits) && mask ptTranslationBits) (Some APageTable) # ref))
     | (VMPDE pde, slot) \<Rightarrow>
         (\<exists>p. pde_ref_pages pde = Some p \<and> p \<in> obj_refs cap) \<and>
         (\<forall>ref. (ref \<rhd> (slot && ~~ mask pd_bits)) s \<longrightarrow>
           vs_cap_ref cap = Some (VSRef ((slot && mask pd_bits >> word_size_bits) && mask ptTranslationBits) (Some APageDirectory) # ref))
     | (VMPDPTE pdpte, slot) \<Rightarrow>
         (\<exists>p. pdpte_ref_pages pdpte = Some p \<and> p \<in> obj_refs cap) \<and>
         (\<forall>ref. (ref \<rhd> (slot && ~~ mask pdpt_bits)) s \<longrightarrow>
           vs_cap_ref cap = Some (VSRef ((slot && mask pdpt_bits >> word_size_bits)&& mask ptTranslationBits) (Some APDPointerTable) # ref))
     | (VMPML4E _, _) \<Rightarrow> True"

definition
  "valid_page_inv page_inv \<equiv> case page_inv of
    PageMap cap ptr m vspace \<Rightarrow>
      cte_wp_at (is_arch_update cap and (op = None \<circ> vs_cap_ref)) ptr
      and cte_wp_at is_pg_cap ptr
      and (\<lambda>s. same_refs m cap s)
      and valid_slots m
      and valid_cap cap
      and K (is_pg_cap cap \<and> empty_refs m)
      and (\<lambda>s. \<exists>slot. cte_wp_at (parent_for_refs m) slot s)
  | PageRemap m asid vspace\<Rightarrow>
      valid_slots m and K (empty_refs m)
      and (\<lambda>s. \<exists>slot. cte_wp_at (parent_for_refs m) slot s)
      and (\<lambda>s. \<exists>slot. cte_wp_at (\<lambda>cap. same_refs m cap s) slot s)
  | PageUnmap cap ptr \<Rightarrow>
     \<lambda>s. \<exists>d r R maptyp sz m. cap = PageCap d r R maptyp sz m \<and>
         case_option True (valid_unmap sz) m \<and>
         cte_wp_at (is_arch_diminished (cap.ArchObjectCap cap)) ptr s \<and>
         s \<turnstile> (cap.ArchObjectCap cap)
  | PageGetAddr ptr \<Rightarrow> \<top>"

crunch aligned [wp]: unmap_page pspace_aligned
  (wp: crunch_wps simp: crunch_simps)


crunch "distinct" [wp]: unmap_page pspace_distinct
  (wp: crunch_wps simp: crunch_simps)


crunch valid_objs[wp]: unmap_page "valid_objs"
  (wp: crunch_wps simp: crunch_simps)


crunch caps_of_state [wp]: unmap_page "\<lambda>s. P (caps_of_state s)"
  (wp: crunch_wps simp: crunch_simps)

lemma set_cap_valid_slots[wp]:
  "\<lbrace>valid_slots x2\<rbrace> set_cap cap (a, b)
          \<lbrace>\<lambda>rv s. valid_slots x2 s \<rbrace>"
   apply (case_tac x2)
   apply (simp only:)
   apply (case_tac aa; clarsimp simp: valid_slots_def)
    by (wp hoare_vcg_ball_lift)+

definition
  empty_pde_at :: "obj_ref \<Rightarrow> 'z::state_ext state \<Rightarrow> bool"
where
  "empty_pde_at p \<equiv> \<lambda>s.
  \<exists>pd. ko_at (ArchObj (PageDirectory pd)) (p && ~~ mask pd_bits) s \<and>
       pd (ucast (p && mask pd_bits >> word_size_bits)) = InvalidPDE"

definition
  empty_pdpte_at :: "obj_ref \<Rightarrow> 'z::state_ext state \<Rightarrow> bool"
where
  "empty_pdpte_at p \<equiv> \<lambda>s.
  \<exists>pdpt. ko_at (ArchObj (PDPointerTable pdpt)) (p && ~~ mask pdpt_bits) s \<and>
       pdpt (ucast (p && mask pdpt_bits >> word_size_bits)) = InvalidPDPTE"

definition
  empty_pml4e_at :: "obj_ref \<Rightarrow> 'z::state_ext state \<Rightarrow> bool"
where
  "empty_pml4e_at p \<equiv> \<lambda>s.
  \<exists>pml4. ko_at (ArchObj (PageMapL4 pml4)) (p && ~~ mask pml4_bits) s \<and>
       pml4 (ucast (p && mask pml4_bits >> word_size_bits)) = InvalidPML4E"

definition
  kernel_vsrefs :: "vs_ref set"
where
 "kernel_vsrefs \<equiv> {r. case r of VSRef x y \<Rightarrow>  (pptr_base >> pml4_shift_bits) && mask ptTranslationBits \<le> x}"

definition
  "valid_pti pti \<equiv> case pti of
     PageTableMap cap cptr pde p vspace\<Rightarrow>
        (\<lambda>s. p && ~~ mask pd_bits \<notin> global_refs s)
        and K(wellformed_pde pde)
        and valid_cap cap
        and valid_pde pde
        and cte_wp_at (\<lambda>c. is_arch_update cap c \<and> cap_asid c = None) cptr
        and (\<lambda>s. \<exists>x ref. (pde_ref_pages pde = Some x)
                 \<and> x \<in> obj_refs cap
                 \<and> obj_at (empty_table (set (x64_global_pdpts (arch_state s)))) x s
                 \<and> (ref \<rhd> (p && ~~ mask pd_bits)) s
                 \<and> vs_cap_ref cap = Some (VSRef ((p && mask pd_bits >> word_size_bits) && mask ptTranslationBits) (Some APageDirectory) # ref))
        and K (is_pt_cap cap)
   | PageTableUnmap cap ptr \<Rightarrow>
     cte_wp_at (\<lambda>c. is_arch_diminished cap c) ptr and valid_cap cap
       and is_final_cap' cap
       and K (is_pt_cap cap)"

definition
  "valid_pdi pdi \<equiv> case pdi of
      PageDirectoryMap cap cptr pdpte p vspace\<Rightarrow>
        (\<lambda>s. p && ~~ mask pdpt_bits \<notin> global_refs s)
        and K(wellformed_pdpte pdpte)
        and valid_cap cap
        and valid_pdpte pdpte
        and cte_wp_at (\<lambda>c. is_arch_update cap c \<and> cap_asid c = None) cptr
        and (\<lambda>s. \<exists>x ref. (pdpte_ref_pages pdpte = Some x)
                 \<and> x \<in> obj_refs cap
                 \<and> obj_at (empty_table (set (x64_global_pdpts (arch_state s)))) x s
                 \<and> (ref \<rhd> (p && ~~ mask pdpt_bits)) s
                 \<and> vs_cap_ref cap =
                       Some (VSRef ((p && mask pdpt_bits >> word_size_bits) && mask ptTranslationBits)
                       (Some APDPointerTable) # ref))
        and K (is_pd_cap cap)
    | PageDirectoryUnmap cap cptr \<Rightarrow>
      cte_wp_at (\<lambda>c. is_arch_diminished cap c) cptr and valid_cap cap and is_final_cap' cap and K (is_pd_cap cap)"

lemmas mapM_x_wp_inv_weak = mapM_x_wp_inv[OF hoare_weaken_pre]

crunch aligned [wp]: unmap_page_table pspace_aligned
  (wp: mapM_x_wp_inv_weak crunch_wps dmo_aligned simp: crunch_simps)
crunch aligned [wp]: unmap_pd pspace_aligned
  (wp: mapM_x_wp_inv_weak crunch_wps dmo_aligned simp: crunch_simps)
crunch aligned [wp]: unmap_pdpt pspace_aligned
  (wp: mapM_x_wp_inv_weak crunch_wps dmo_aligned simp: crunch_simps)

crunch valid_objs [wp]: unmap_page_table valid_objs
  (wp: mapM_x_wp_inv_weak crunch_wps simp: crunch_simps)

crunch "distinct" [wp]: unmap_page_table pspace_distinct
  (wp: mapM_x_wp_inv_weak crunch_wps simp: crunch_simps)

crunch caps_of_state [wp]: unmap_page_table "\<lambda>s. P (caps_of_state s)"
  (wp: mapM_x_wp_inv_weak crunch_wps simp: crunch_simps)

crunch typ_at [wp]: unmap_page_table "\<lambda>s. P (typ_at T p s)"
  (wp: mapM_x_wp_inv_weak crunch_wps hoare_drop_imps)

crunch typ_at [wp]: unmap_pd "\<lambda>s. P (typ_at T p s)"
  (wp: mapM_x_wp_inv_weak crunch_wps hoare_drop_imps)

crunch caps_of_state [wp]: unmap_pd "\<lambda>s. P (caps_of_state s)"
  (wp: mapM_x_wp_inv_weak crunch_wps simp: crunch_simps)

crunch typ_at [wp]: unmap_pdpt "\<lambda>s. P (typ_at T p s)"
  (wp: mapM_x_wp_inv_weak crunch_wps hoare_drop_imps)

crunch caps_of_state [wp]: unmap_pdpt "\<lambda>s. P (caps_of_state s)"
  (wp: mapM_x_wp_inv_weak crunch_wps simp: crunch_simps)

lemmas flush_table_typ_ats [wp] = abs_typ_at_lifts [OF flush_table_typ_at]

definition
  "valid_apinv ap \<equiv> case ap of
  asid_pool_invocation.Assign asid p slot \<Rightarrow>
  (\<lambda>s. \<exists>pool. ko_at (ArchObj (arch_kernel_obj.ASIDPool pool)) p s \<and>
              pool (ucast asid) = None)
  and cte_wp_at (\<lambda>cap. is_pml4_cap cap \<and> cap_asid cap = None) slot
  and K (0 < asid \<and> asid \<le> 2^asid_bits - 1)
  and ([VSRef (ucast (asid_high_bits_of asid)) None] \<rhd> p)"

crunch device_state_inv[wp]: ackInterrupt, writeCR3 "\<lambda>ms. P (device_state ms)"

lemma dmo_ackInterrupt[wp]: "\<lbrace>invs\<rbrace> do_machine_op (ackInterrupt irq) \<lbrace>\<lambda>y. invs\<rbrace>"
  apply (wp dmo_invs)
  apply safe
   apply (drule_tac Q="\<lambda>_ m'. underlying_memory m' p = underlying_memory m p"
          in use_valid)
     apply ((clarsimp simp: ackInterrupt_def machine_op_lift_def
                           machine_rest_lift_def split_def | wp)+)[3]
  apply(erule (1) use_valid[OF _ ackInterrupt_irq_masks])
  done

lemmas writeCR3_irq_masks = no_irq[OF no_irq_writeCR3]

lemma dmo_writeCR3[wp]: "\<lbrace>invs\<rbrace> do_machine_op (writeCR3 vs asid) \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (wp dmo_invs)
  apply safe
   apply (drule_tac Q="\<lambda>_ m'. underlying_memory m' p = underlying_memory m p"
          in use_valid)
     apply ((clarsimp simp: writeCR3_def machine_op_lift_def
                           machine_rest_lift_def split_def | wp)+)[3]
  apply(erule (1) use_valid[OF _ writeCR3_irq_masks])
  done

crunch inv[wp]: getCurrentCR3 P

lemma getCurrentCR3_rewrite_lift[wp]:
  "\<lbrace>P\<rbrace> getCurrentCR3 \<lbrace>\<lambda>rv s. Q rv \<longrightarrow> P s\<rbrace>"
  apply (wp hoare_drop_imps)
  done

(* FIXME x64: cr3 invariants *)
lemma setCurrentCR3_invs[wp]:
  "\<lbrace>invs\<rbrace> setCurrentCR3 cr3 \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: setCurrentCR3_def)
  apply (wp)
  sorry

lemma setCurrentVSpaceRoot_invs[wp]:
  "\<lbrace>invs\<rbrace> setCurrentVSpaceRoot vspace asid \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: setCurrentVSpaceRoot_def)
  apply (wp)
  done

lemma update_asid_map_valid_arch:
  notes hoare_pre [wp_pre del]
  shows "\<lbrace>valid_arch_state\<rbrace>
  update_asid_map asid
  \<lbrace>\<lambda>_. valid_arch_state\<rbrace>"
  apply (simp add: update_asid_map_def)
  apply (wp find_vspace_for_asid_assert_wp)
  apply (simp add: valid_arch_state_def fun_upd_def[symmetric] comp_upd_simp)
  done

lemma update_asid_map_invs:
  "\<lbrace>invs and K (asid \<le> mask asid_bits)\<rbrace> update_asid_map asid  \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (rule hoare_add_post)
    apply (rule update_asid_map_valid_arch)
   apply fastforce
  apply (simp add: update_asid_map_def)
  apply (wp find_vspace_for_asid_assert_wp)
  apply (clarsimp simp: invs_def valid_state_def)
  apply (simp add: valid_global_refs_def global_refs_def
                   valid_irq_node_def valid_arch_objs_arch_update
                   valid_global_objs_def valid_arch_caps_def
                   valid_table_caps_def valid_kernel_mappings_def
                   valid_machine_state_def valid_vs_lookup_arch_update)
  apply (simp add: valid_asid_map_def fun_upd_def[symmetric] vspace_at_asid_arch_up)
  done

lemma svr_invs [wp]:
  "\<lbrace>invs\<rbrace> set_vm_root t' \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (simp add: set_vm_root_def)
  apply (rule hoare_pre)
   apply (wp hoare_whenE_wp find_vspace_for_asid_inv hoare_vcg_all_lift update_asid_map_invs
              | wpc
              | simp add: split_def if_apply_def2 cong: if_cong)+
    apply (rule_tac Q'="\<lambda>_ s. invs s \<and> x2 \<le> mask asid_bits" in hoare_post_imp_R)
     prefer 2
     apply simp
    apply (rule valid_validE_R)
    apply (wp find_vspace_for_asid_inv | simp add: split_def)+
   apply (rule_tac Q="\<lambda>c s. invs s \<and> s \<turnstile> c" in hoare_strengthen_post)
    apply wp
   apply (clarsimp simp: valid_cap_def mask_def)
  by (fastforce)

crunch pred_tcb_at[wp]: setCurrentVSpaceRoot, update_asid_map "pred_tcb_at proj P t"

lemma svr_pred_st_tcb[wp]:
  "\<lbrace>pred_tcb_at proj P t\<rbrace> set_vm_root t \<lbrace>\<lambda>_. pred_tcb_at proj P t\<rbrace>"
  apply (simp add: set_vm_root_def )
  by (wp get_cap_wp | wpc | simp add: whenE_def split del: if_split)+

crunch typ_at [wp]: getCurrentCR3, set_vm_root "\<lambda>s. P (typ_at T p s)"
  (simp: crunch_simps)

lemmas set_vm_root_typ_ats [wp] = abs_typ_at_lifts [OF set_vm_root_typ_at]

lemma valid_pte_lift3:
  assumes x: "(\<And>P T p. \<lbrace>\<lambda>s. P (typ_at T p s)\<rbrace> f \<lbrace>\<lambda>rv s. P (typ_at T p s)\<rbrace>)"
  shows "\<lbrace>\<lambda>s. P (valid_pte pte s)\<rbrace> f \<lbrace>\<lambda>rv s. P (valid_pte pte s)\<rbrace>"
  apply (insert bool_function_four_cases[where f=P])
  apply (erule disjE)
   apply (cases pte)
     apply (simp add: data_at_def | wp hoare_vcg_const_imp_lift x)+
  apply (erule disjE)
   apply (cases pte)
     apply (simp add: data_at_def | wp hoare_vcg_disj_lift hoare_vcg_const_imp_lift x)+
  apply (erule disjE)
   apply (simp | wp)+
  done

lemma set_cap_valid_pte_stronger:
  "\<lbrace>\<lambda>s. P (valid_pte pte s)\<rbrace> set_cap cap p \<lbrace>\<lambda>rv s. P (valid_pte pte s)\<rbrace>"
  by (wp valid_pte_lift3 set_cap_typ_at)

lemma valid_pde_lift3:
  assumes x: "(\<And>P T p. \<lbrace>\<lambda>s. P (typ_at T p s)\<rbrace> f \<lbrace>\<lambda>rv s. P (typ_at T p s)\<rbrace>)"
  shows "\<lbrace>\<lambda>s. P (valid_pde pde s)\<rbrace> f \<lbrace>\<lambda>rv s. P (valid_pde pde s)\<rbrace>"
  apply (insert bool_function_four_cases[where f=P])
  apply (erule disjE)
   apply (cases pde)
     apply (simp add: data_at_def | wp hoare_vcg_const_imp_lift x)+
  apply (erule disjE)
   apply (cases pde)
     apply (simp add: data_at_def | wp hoare_vcg_disj_lift hoare_vcg_const_imp_lift x)+
  apply (erule disjE)
   apply (simp | wp)+
  done

lemma set_cap_valid_pde_stronger:
  "\<lbrace>\<lambda>s. P (valid_pde pde s)\<rbrace> set_cap cap p \<lbrace>\<lambda>rv s. P (valid_pde pde s)\<rbrace>"
  by (wp valid_pde_lift3 set_cap_typ_at)

lemma valid_pdpte_lift3:
  assumes x: "(\<And>P T p. \<lbrace>\<lambda>s. P (typ_at T p s)\<rbrace> f \<lbrace>\<lambda>rv s. P (typ_at T p s)\<rbrace>)"
  shows "\<lbrace>\<lambda>s. P (valid_pdpte pdpte s)\<rbrace> f \<lbrace>\<lambda>rv s. P (valid_pdpte pdpte s)\<rbrace>"
  apply (insert bool_function_four_cases[where f=P])
  apply (erule disjE)
   apply (cases pdpte)
     apply (simp add: data_at_def | wp hoare_vcg_const_imp_lift x)+
  apply (erule disjE)
   apply (cases pdpte)
     apply (simp add: data_at_def | wp hoare_vcg_disj_lift hoare_vcg_const_imp_lift x)+
  apply (erule disjE)
   apply (simp | wp)+
  done

lemma set_cap_valid_pdpte_stronger:
  "\<lbrace>\<lambda>s. P (valid_pdpte pdpte s)\<rbrace> set_cap cap p \<lbrace>\<lambda>rv s. P (valid_pdpte pdpte s)\<rbrace>"
  by (wp valid_pdpte_lift3 set_cap_typ_at)
end

context Arch begin global_naming X64

definition is_asid_pool_cap :: "cap \<Rightarrow> bool"
 where "is_asid_pool_cap cap \<equiv> \<exists>ptr asid. cap = cap.ArchObjectCap (arch_cap.ASIDPoolCap ptr asid)"


(* FIXME: move *)
lemma valid_cap_to_pt_cap:
  "\<lbrakk>valid_cap c s; obj_refs c = {p}; page_table_at p s\<rbrakk> \<Longrightarrow> is_pt_cap c"
  by (clarsimp simp: valid_cap_def obj_at_def is_obj_defs is_pt_cap_def
                 split: cap.splits option.splits arch_cap.splits if_splits)

lemma valid_cap_to_pdpt_cap:
  "\<lbrakk>valid_cap c s; obj_refs c = {p}; pd_pointer_table_at p s\<rbrakk> \<Longrightarrow> is_pdpt_cap c"
  by (clarsimp simp: valid_cap_def obj_at_def is_obj_defs is_pdpt_cap_def
                 split: cap.splits option.splits arch_cap.splits if_splits)

lemma valid_cap_to_pd_cap:
  "\<lbrakk>valid_cap c s; obj_refs c = {p}; page_directory_at p s\<rbrakk> \<Longrightarrow> is_pd_cap c"
  by (clarsimp simp: valid_cap_def obj_at_def is_obj_defs is_pd_cap_def
                 split: cap.splits option.splits arch_cap.splits if_splits)

lemma ref_is_unique:
  "\<lbrakk>(ref \<rhd> p) s; (ref' \<rhd> p) s; p \<notin> set (x64_global_pdpts (arch_state s));
    valid_vs_lookup s; unique_table_refs (caps_of_state s);
    valid_arch_objs s; valid_asid_table (x64_asid_table (arch_state s)) s;
    valid_caps (caps_of_state s) s\<rbrakk>
   \<Longrightarrow> ref = ref'"
  apply (erule (1) vs_lookupE_alt[OF _ _ valid_asid_table_ran], clarsimp)
      apply (erule (1) vs_lookupE_alt[OF _ _ valid_asid_table_ran], clarsimp)
          apply (clarsimp simp: valid_asid_table_def up_ucast_inj_eq)
          apply (erule (2) inj_on_domD)
         apply ((clarsimp simp: obj_at_def)+)[4]
     apply (erule (1) vs_lookupE_alt[OF _ _ valid_asid_table_ran], clarsimp)
         apply (clarsimp simp: obj_at_def)
        apply (drule (2) vs_lookup_apI)+
        apply (clarsimp dest!: valid_vs_lookupD[OF vs_lookup_pages_vs_lookupI]
                               obj_ref_elemD
                         simp: table_cap_ref_ap_eq[symmetric])
        apply (drule_tac cap=cap and cap'=capa in unique_table_refsD, simp+)[1]
       apply ((clarsimp simp: obj_at_def)+)[3]
    apply (erule (1) vs_lookupE_alt[OF _ _ valid_asid_table_ran], clarsimp)
        apply ((clarsimp simp: obj_at_def)+)[2]
      apply (simp add: pml4e_ref_def split: pml4e.splits)
      apply (drule (5) vs_lookup_pml4I)+
      apply (clarsimp dest!: valid_vs_lookupD[OF vs_lookup_pages_vs_lookupI]
                             obj_ref_elemD)
      apply (drule_tac cap=cap and cap'=capa in unique_table_refsD, simp+)[1]
      apply (drule (3) valid_capsD[THEN valid_cap_to_pdpt_cap])+
      apply (clarsimp simp: is_pdpt_cap_def table_cap_ref_simps vs_cap_ref_simps)
     apply ((clarsimp simp: obj_at_def)+)[2]
   apply (erule (1) vs_lookupE_alt[OF _ _ valid_asid_table_ran], clarsimp)
       apply ((clarsimp simp: obj_at_def)+)[3]
    apply (simp add: pdpte_ref_def split: pdpte.splits)
    apply (drule (7) vs_lookup_pdptI)+
    apply (clarsimp dest!: valid_vs_lookupD[OF vs_lookup_pages_vs_lookupI] obj_ref_elemD)
    apply (drule_tac cap=cap and cap'=capa in unique_table_refsD, simp+)[1]
    apply (drule (3) valid_capsD[THEN valid_cap_to_pd_cap])+
    apply (clarsimp simp: is_pd_cap_def table_cap_ref_simps vs_cap_ref_simps)
   apply (clarsimp simp: obj_at_def)
  apply (erule (1) vs_lookupE_alt[OF _ _ valid_asid_table_ran], clarsimp)
      apply ((clarsimp simp: obj_at_def)+)[4]
  apply (simp add: pde_ref_def split: pde.splits)
  apply (drule (9) vs_lookup_pdI)+
  apply (clarsimp dest!: valid_vs_lookupD[OF vs_lookup_pages_vs_lookupI] obj_ref_elemD)
  apply (drule_tac cap=cap and cap'=capa in unique_table_refsD, simp+)[1]
  apply (drule (3) valid_capsD[THEN valid_cap_to_pt_cap])+
  apply (clarsimp simp: is_pt_cap_def table_cap_ref_simps vs_cap_ref_simps)
  done

lemma pml4_translation_bits:
  fixes p :: machine_word
  shows "p && mask pml4_bits >> word_size_bits < 2 ^ ptTranslationBits"
  apply (rule shiftr_less_t2n)
  apply (simp add: pml4_bits_def simple_bit_simps)
  apply (rule and_mask_less'[of 12 p, simplified])
  done

lemma ucast_ucast_mask_shift_helper:
  "ucast (ucast (p && mask pml4_bits >> word_size_bits :: machine_word) :: 9 word)
        = (p && mask pml4_bits >> word_size_bits :: machine_word)"
  apply (rule ucast_ucast_len)
  using pml4_translation_bits by (auto simp: ptTranslationBits_def)

lemma unat_ucast_pml4_bits_shift:
  "unat (ucast (p && mask pml4_bits >> word_size_bits :: machine_word) :: 9 word)
        = unat (p && mask pml4_bits >> word_size_bits)"
  apply (simp only: unat_ucast)
  apply (rule mod_less[OF unat_less_power])
  using pml4_translation_bits by (auto simp: ptTranslationBits_def)

lemma kernel_vsrefs_kernel_mapping_slots:
  "(ucast (p && mask pml4_bits >> word_size_bits) \<in> kernel_mapping_slots) =
    (VSRef (p && mask pml4_bits >> word_size_bits) (Some APageMapL4) \<in> kernel_vsrefs)"
  apply (clarsimp simp: kernel_mapping_slots_def kernel_vsrefs_def
                        word_le_nat_alt unat_ucast_pml4_bits_shift)
  apply (clarsimp simp: pptr_base_def pptrBase_def bit_simps mask_def)
  done

lemma vs_lookup_typI:
  "\<lbrakk>(r \<rhd> p) s; valid_arch_objs s; valid_asid_table (x64_asid_table (arch_state s)) s\<rbrakk>
   \<Longrightarrow> page_table_at p s
    \<or> page_directory_at p s
    \<or> pd_pointer_table_at p s
    \<or> page_map_l4_at p s
    \<or> asid_pool_at p s"
  apply (erule (1) vs_lookupE_alt)
     apply (clarsimp simp: ran_def)
     apply (drule (2) valid_asid_tableD)
    apply simp+
  done

(* FIXME: Looks Correct and needs to be correct !  *)
lemma vs_lookup_vs_lookup_pagesI':
  "\<lbrakk>(r \<unrhd> p) s; page_table_at p s \<or> page_directory_at p s \<or> pd_pointer_table_at p s \<or> page_map_l4_at p s \<or> asid_pool_at p s;
    valid_arch_objs s; valid_asid_table (x64_asid_table (arch_state s)) s\<rbrakk>
   \<Longrightarrow> (r \<rhd> p) s"
  sorry (*
  apply (erule (1) vs_lookup_pagesE_alt)
      apply (clarsimp simp:ran_def)
      apply (drule (2) valid_asid_tableD)
     apply (rule vs_lookupI)
      apply (fastforce simp: vs_asid_refs_def graph_of_def)
     apply simp
    apply (rule vs_lookupI)
     apply (fastforce simp: vs_asid_refs_def graph_of_def)
    apply (rule rtrancl_into_rtrancl[OF rtrancl.intros(1)])
    apply (fastforce simp: vs_lookup1_def obj_at_def vs_refs_def graph_of_def)
   apply (rule vs_lookupI)
    apply (fastforce simp: vs_asid_refs_def graph_of_def)
   apply (rule_tac y="([VSRef (ucast b) (Some AASIDPool), VSRef (ucast a) None], p\<^sub>2)" in rtrancl_trans)
    apply (rule rtrancl_into_rtrancl[OF rtrancl.intros(1)])
    apply (fastforce simp: vs_lookup1_def obj_at_def vs_refs_def graph_of_def)
   apply (rule rtrancl_into_rtrancl[OF rtrancl.intros(1)])
   apply (clarsimp simp: vs_lookup1_def obj_at_def vs_refs_def graph_of_def)
   apply (rule_tac x="(c, p)" in image_eqI)
    apply simp
   apply (clarsimp simp: pml4e_ref_def pml4e_ref_pages_def valid_pde_def obj_at_def
                         a_type_def
                   split:pml4e.splits )
  apply (rule vs_lookupI)
   apply (fastforce simp: vs_asid_refs_def graph_of_def)
  apply (rule_tac y="([VSRef (ucast b) (Some AASIDPool), VSRef (ucast a) None], p\<^sub>2)" in rtrancl_trans)
   apply (rule rtrancl_into_rtrancl[OF rtrancl.intros(1)])
   apply (fastforce simp: vs_lookup1_def obj_at_def vs_refs_def graph_of_def)
  apply (rule_tac y="([VSRef (ucast c) (Some APageMapL4), VSRef (ucast b) (Some AASIDPool),
           VSRef (ucast a) None], (ptrFromPAddr addr))" in rtrancl_trans)
   apply (rule rtrancl_into_rtrancl[OF rtrancl.intros(1)])
   apply (clarsimp simp: vs_lookup1_def obj_at_def vs_refs_def graph_of_def)
   apply (rule_tac x="(c,(ptrFromPAddr addr))" in image_eqI)
    apply simp
   apply (clarsimp simp: pml4e_ref_def)
  apply (rule rtrancl_into_rtrancl[OF rtrancl.intros(1)])
  apply (clarsimp simp: vs_lookup1_def obj_at_def vs_refs_def graph_of_def pdpte_ref_pages_def a_type_def
                  split: pdpte.splits )
  done
*)

lemma vs_lookup_vs_lookup_pagesI:
  "\<lbrakk>(r \<rhd> p) s; (r' \<unrhd> p) s; valid_arch_objs s; valid_asid_table (x64_asid_table (arch_state s)) s\<rbrakk>
   \<Longrightarrow> (r' \<rhd> p) s"
  by (erule (5) vs_lookup_vs_lookup_pagesI'[OF _ vs_lookup_typI])

(* FIXME: move *)
lemma valid_cap_to_pml4_cap:
  "\<lbrakk>valid_cap c s; obj_refs c = {p}; page_map_l4_at p s\<rbrakk> \<Longrightarrow> is_pml4_cap c"
  by (clarsimp simp: valid_cap_def obj_at_def is_obj_defs is_pml4_cap_def
              split: cap.splits option.splits arch_cap.splits if_splits)

lemma set_cap_empty_pde:
  "\<lbrace>empty_pde_at p and cte_at p'\<rbrace> set_cap cap p' \<lbrace>\<lambda>_. empty_pde_at p\<rbrace>"
  apply (simp add: empty_pde_at_def)
  apply (rule hoare_pre)
   apply (wp set_cap_obj_at_other hoare_vcg_ex_lift)
  apply clarsimp
  apply (rule exI, rule conjI, assumption)
  apply (erule conjI)
  apply (clarsimp simp: cte_wp_at_cases obj_at_def)
  done

lemma set_cap_empty_pml4e:
  "\<lbrace>empty_pml4e_at p and cte_at p'\<rbrace> set_cap cap p' \<lbrace>\<lambda>_. empty_pml4e_at p\<rbrace>"
  apply (simp add: empty_pml4e_at_def)
  apply (rule hoare_pre)
   apply (wp set_cap_obj_at_other hoare_vcg_ex_lift)
  apply clarsimp
  apply (rule exI, rule conjI, assumption)
  apply (erule conjI)
  apply (clarsimp simp: cte_wp_at_cases obj_at_def)
  done

lemma set_cap_empty_pdpte:
  "\<lbrace>empty_pdpte_at p and cte_at p'\<rbrace> set_cap cap p' \<lbrace>\<lambda>_. empty_pdpte_at p\<rbrace>"
  apply (simp add: empty_pdpte_at_def)
  apply (rule hoare_pre)
   apply (wp set_cap_obj_at_other hoare_vcg_ex_lift)
  apply clarsimp
  apply (rule exI, rule conjI, assumption)
  apply (erule conjI)
  apply (clarsimp simp: cte_wp_at_cases obj_at_def)
  done

lemma valid_cap_obj_ref_vspace:
  "\<lbrakk> s \<turnstile> cap; s \<turnstile> cap'; obj_refs cap = obj_refs cap' \<rbrakk>
       \<Longrightarrow> (is_pt_cap cap \<longrightarrow> is_pt_cap cap')
         \<and> (is_pd_cap cap \<longrightarrow> is_pd_cap cap')
         \<and> (is_pdpt_cap cap \<longrightarrow> is_pdpt_cap cap')
         \<and> (is_pml4_cap cap \<longrightarrow> is_pml4_cap cap')"
  by (auto simp: is_cap_simps valid_cap_def
                 obj_at_def is_ep is_ntfn is_cap_table
                 is_tcb a_type_def
          split: cap.split_asm if_split_asm
                 arch_cap.split_asm option.split_asm)

lemma is_vspace_cap_asid_None_table_ref:
  "is_pt_cap cap \<or> is_pd_cap cap \<or> is_pdpt_cap cap \<or> is_pml4_cap cap
     \<Longrightarrow> ((table_cap_ref cap = None) = (cap_asid cap = None))"
  by (auto simp: is_cap_simps table_cap_ref_def cap_asid_def
          split: option.split_asm)

lemma no_cap_to_obj_with_diff_ref_map:
  "\<lbrakk> caps_of_state s p = Some cap; is_pt_cap cap \<or> is_pd_cap cap \<or> is_pdpt_cap cap \<or> is_pml4_cap cap;
     table_cap_ref cap = None;
     unique_table_caps (caps_of_state s);
     valid_objs s; obj_refs cap = obj_refs cap' \<rbrakk>
       \<Longrightarrow> no_cap_to_obj_with_diff_ref cap' {p} s"
  apply (clarsimp simp: no_cap_to_obj_with_diff_ref_def
                        cte_wp_at_caps_of_state)
  apply (frule(1) caps_of_state_valid_cap[where p=p])
  apply (frule(1) caps_of_state_valid_cap[where p="(a, b)" for a b])
  apply (drule(1) valid_cap_obj_ref_vspace, simp)
  apply (drule(1) unique_table_capsD[rotated, where cps="caps_of_state s"])
      apply simp
     apply (simp add: is_vspace_cap_asid_None_table_ref)
    apply fastforce
   apply assumption
  apply simp
  done


lemmas store_pte_cte_wp_at1[wp]
    = hoare_cte_wp_caps_of_state_lift [OF store_pte_caps_of_state]

lemmas store_pde_cte_wp_at1[wp]
    = hoare_cte_wp_caps_of_state_lift [OF store_pde_caps_of_state]

lemmas store_pdpte_cte_wp_at1[wp]
    = hoare_cte_wp_caps_of_state_lift [OF store_pdpte_caps_of_state]

crunch global_refs_inv[wp]: store_pml4e "\<lambda>s. P (global_refs s)"
    (wp: get_object_wp)

crunch global_refs_inv[wp]: store_pde "\<lambda>s. P (global_refs s)"
    (wp: get_object_wp)

crunch global_refs_inv[wp]: store_pdpte "\<lambda>s. P (global_refs s)"
    (wp: get_object_wp)

crunch global_refs_inv[wp]: store_pte "\<lambda>s. P (global_refs s)"
    (wp: get_object_wp)

lemma mapM_swp_store_pte_invs_unmap:
  "\<lbrace>invs and
    (\<lambda>s. \<forall>sl\<in>set slots. sl && ~~ mask pt_bits \<notin> global_refs s) and
    K (pte = InvalidPTE)\<rbrace>
  mapM (swp store_pte pte) slots \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (rule hoare_post_imp)
   prefer 2
   apply (rule mapM_wp')
   apply simp
   apply (rule hoare_pre, wp store_pte_invs hoare_vcg_const_Ball_lift
                             hoare_vcg_ex_lift)
    apply (clarsimp simp: pte_ref_pages_def)+
  done

lemma mapM_swp_store_pde_invs_unmap:
  "\<lbrace>invs and
    (\<lambda>s. \<forall>sl\<in>set slots. sl && ~~ mask pd_bits \<notin> global_refs s) and
    K (pde = InvalidPDE)\<rbrace>
  mapM (swp store_pde pde) slots \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (rule hoare_post_imp)
   prefer 2
   apply (rule mapM_wp')
   apply simp
   apply (rule hoare_pre, wp store_pde_invs hoare_vcg_const_Ball_lift
                             hoare_vcg_ex_lift)
    apply clarsimp+
  done

lemma mapM_swp_store_pdpte_invs_unmap:
  "\<lbrace>invs and
    (\<lambda>s. \<forall>sl\<in>set slots. sl && ~~ mask pdpt_bits \<notin> global_refs s) and
    K (pdpte = InvalidPDPTE)\<rbrace>
  mapM (swp store_pdpte pdpte) slots \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (rule hoare_post_imp)
   prefer 2
   apply (rule mapM_wp')
   apply simp
   apply (rule hoare_pre, wp store_pdpte_invs hoare_vcg_const_Ball_lift
                             hoare_vcg_ex_lift)
    apply (clarsimp simp: pdpte_ref_pages_def)+
  done

lemma mapM_swp_store_pml4e_invs_unmap:
  "\<lbrace>invs and
    (\<lambda>s. \<forall>sl\<in>set slots.
            ucast (sl && mask pml4_bits >> word_size_bits) \<notin> kernel_mapping_slots) and
    (\<lambda>s. \<forall>sl\<in>set slots. sl && ~~ mask pml4_bits \<notin> global_refs s) and
    K (pml4e = InvalidPML4E)\<rbrace>
  mapM (swp store_pml4e pml4e) slots \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (rule hoare_post_imp)
   prefer 2
   apply (rule mapM_wp')
   apply simp
   apply (rule hoare_pre, wp store_pml4e_invs hoare_vcg_const_Ball_lift
                             hoare_vcg_ex_lift)
    apply (clarsimp simp: pml4e_ref_pages_def)+
  done

lemma vs_refs_pml4I3:
  "\<lbrakk>pml4e_ref (pml4 x) = Some p; x \<notin> kernel_mapping_slots\<rbrakk>
   \<Longrightarrow> (VSRef (ucast x) (Some APageMapL4), p) \<in> vs_refs (ArchObj (PageMapL4 pml4))"
  by (auto simp: pml4e_ref_def vs_refs_def graph_of_def)


lemma mapM_x_swp_store_pte_invs_unmap:
  "\<lbrace>invs and (\<lambda>s. \<forall>sl \<in> set slots. sl && ~~ mask pt_bits \<notin> global_refs s) and
    K (pde = InvalidPTE)\<rbrace>
  mapM_x (swp store_pte pde) slots \<lbrace>\<lambda>_. invs\<rbrace>"
  by (simp add: mapM_x_mapM | wp mapM_swp_store_pte_invs_unmap)+

lemma mapM_x_swp_store_pde_invs_unmap:
  "\<lbrace>invs and (\<lambda>s. \<forall>sl \<in> set slots. sl && ~~ mask pd_bits \<notin> global_refs s) and
    K (pde = InvalidPDE)\<rbrace>
  mapM_x (swp store_pde pde) slots \<lbrace>\<lambda>_. invs\<rbrace>"
  by (simp add: mapM_x_mapM | wp mapM_swp_store_pde_invs_unmap)+

lemma mapM_x_swp_store_pdpte_invs_unmap:
  "\<lbrace>invs and (\<lambda>s. \<forall>sl \<in> set slots. sl && ~~ mask pdpt_bits \<notin> global_refs s) and
    K (pdpte = InvalidPDPTE)\<rbrace>
  mapM_x (swp store_pdpte pdpte) slots \<lbrace>\<lambda>_. invs\<rbrace>"
  by (simp add: mapM_x_mapM | wp mapM_swp_store_pdpte_invs_unmap)+

lemma mapM_x_swp_store_pml4e_invs_unmap:
  "\<lbrace>invs and K (\<forall>sl\<in>set slots.
                   ucast (sl && mask pml4_bits >> word_size_bits) \<notin> kernel_mapping_slots) and
    (\<lambda>s. \<forall>sl \<in> set slots. sl && ~~ mask pml4_bits \<notin> global_refs s) and
    K (pml4e = InvalidPML4E)\<rbrace>
  mapM_x (swp store_pml4e pml4e) slots \<lbrace>\<lambda>_. invs\<rbrace>"
  by (simp add: mapM_x_mapM | wp mapM_swp_store_pml4e_invs_unmap)+

(* FIXME: move *)
lemma vs_cap_ref_table_cap_ref_None:
  "vs_cap_ref x = None \<Longrightarrow> table_cap_ref x = None"
  by (simp add: vs_cap_ref_def table_cap_ref_simps
         split: cap.splits arch_cap.splits)

(* FIXME: move *)
lemma master_cap_eq_is_pg_cap_eq:
  "cap_master_cap c = cap_master_cap d \<Longrightarrow> is_pg_cap c = is_pg_cap d"
  by (simp add: cap_master_cap_def is_pg_cap_def
         split: cap.splits arch_cap.splits)

(* FIXME: move *)
lemma master_cap_eq_is_device_cap_eq:
  "cap_master_cap c = cap_master_cap d \<Longrightarrow> cap_is_device c = cap_is_device d"
  by (simp add: cap_master_cap_def
         split: cap.splits arch_cap.splits)

(* FIXME: move *)
lemmas vs_cap_ref_eq_imp_table_cap_ref_eq' =
       vs_cap_ref_eq_imp_table_cap_ref_eq[OF master_cap_eq_is_pg_cap_eq]

lemma arch_update_cap_invs_map:
  "\<lbrace>cte_wp_at (is_arch_update cap and
               (\<lambda>c. \<forall>r. vs_cap_ref c = Some r \<longrightarrow> vs_cap_ref cap = Some r)) p
             and invs and valid_cap cap\<rbrace>
  set_cap cap p
  \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def)
  apply (rule hoare_pre)
   apply (wp arch_update_cap_pspace arch_update_cap_valid_mdb set_cap_idle
             update_cap_ifunsafe valid_irq_node_typ set_cap_typ_at
             set_cap_irq_handlers set_cap_valid_arch_caps
             set_cap_cap_refs_respects_device_region_spec[where ptr = p])
  apply (clarsimp simp: cte_wp_at_caps_of_state
              simp del: imp_disjL)
  apply (frule(1) valid_global_refsD2)
  apply (frule(1) cap_refs_in_kernel_windowD)
  apply (clarsimp simp: is_cap_simps is_arch_update_def
              simp del: imp_disjL)
  apply (frule master_cap_cap_range, simp del: imp_disjL)
  apply (thin_tac "cap_range a = cap_range b" for a b)
  apply (rule conjI)
   apply (rule ext)
   apply (simp add: cap_master_cap_def split: cap.splits arch_cap.splits)
  apply (rule context_conjI)
   apply (simp add: appropriate_cte_cap_irqs)
   apply (clarsimp simp: cap_irqs_def cap_irq_opt_def cap_master_cap_def
                  split: cap.split)
  apply (rule conjI)
   apply (drule(1) if_unsafe_then_capD [OF caps_of_state_cteD])
    apply (clarsimp simp: cap_master_cap_def)
   apply (erule ex_cte_cap_wp_to_weakenE)
   apply (clarsimp simp: appropriate_cte_cap_def cap_master_cap_def
                  split: cap.split_asm)
  apply (rule conjI)
   apply (frule master_cap_obj_refs)
   apply simp
  apply (rule conjI)
   apply (frule master_cap_obj_refs)
   apply (case_tac "table_cap_ref capa =
                    table_cap_ref (ArchObjectCap a)")
    apply (frule unique_table_refs_no_cap_asidE[where S="{p}"])
     apply (simp add: valid_arch_caps_def)
    apply (simp add: no_cap_to_obj_with_diff_ref_def Ball_def)
   apply (case_tac "table_cap_ref capa")
    apply clarsimp
    apply (erule no_cap_to_obj_with_diff_ref_map,
           simp_all)[1]
      apply (clarsimp simp: table_cap_ref_def cap_master_cap_simps
                            is_cap_simps
                     split: cap.split_asm arch_cap.split_asm
                     dest!: cap_master_cap_eqDs)
     apply (simp add: valid_arch_caps_def)
    apply (simp add: valid_pspace_def)
   apply (erule swap)
   apply (erule vs_cap_ref_eq_imp_table_cap_ref_eq'[symmetric])
   apply (frule table_cap_ref_vs_cap_ref_Some)
   apply simp
  apply (rule conjI)
   apply (clarsimp simp del: imp_disjL)
   apply ((erule disjE |
            ((clarsimp simp: is_cap_simps cap_master_cap_simps
                             cap_asid_def vs_cap_ref_def
                      dest!: cap_master_cap_eqDs
                      split: option.split_asm prod.split_asm),
              drule valid_table_capsD[OF caps_of_state_cteD],
             (clarsimp simp: invs_def valid_state_def valid_arch_caps_def is_cap_simps
                             cap_asid_def)+))+)[1]
  apply (clarsimp simp: is_cap_simps is_pt_cap_def cap_master_cap_simps
                        cap_asid_def vs_cap_ref_def ranI
                 dest!: cap_master_cap_eqDs split: option.split_asm if_split_asm
                 elim!: ranE
                  cong: master_cap_eq_is_device_cap_eq
             | rule conjI)+
  apply (clarsimp dest!: master_cap_eq_is_device_cap_eq)
  done

    (* Want something like
       cte_wp_at (\<lambda>c. \<forall>p'\<in>obj_refs c. \<not>(vs_cap_ref c \<unrhd> p') s \<and> is_arch_update cap c) p
       So that we know the new cap isn't clobbering a cap with necessary mapping info.
       invs is fine here (I suspect) because we unmap the page BEFORE we replace the cap.
    *)

lemma arch_update_cap_invs_unmap_page:
  "\<lbrace>(\<lambda>s. cte_wp_at (\<lambda>c. (\<forall>p'\<in>obj_refs c. \<forall>ref. vs_cap_ref c = Some ref \<longrightarrow> \<not> (ref \<unrhd> p') s) \<and> is_arch_update cap c) p s)
             and invs and valid_cap cap
             and K (is_pg_cap cap)\<rbrace>
  set_cap cap p
  \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def)
  apply (rule hoare_pre)
   apply (wp arch_update_cap_pspace arch_update_cap_valid_mdb set_cap_idle
             update_cap_ifunsafe valid_irq_node_typ set_cap_typ_at
             set_cap_irq_handlers set_cap_valid_arch_caps
             set_cap_cap_refs_respects_device_region_spec[where ptr = p])
  apply clarsimp
  apply (clarsimp simp: cte_wp_at_caps_of_state is_arch_update_def
                        is_cap_simps cap_master_cap_simps
                        fun_eq_iff appropriate_cte_cap_irqs
                        is_pt_cap_def
                 dest!: cap_master_cap_eqDs
              simp del: imp_disjL)
  apply (rule conjI)
   apply (drule(1) if_unsafe_then_capD [OF caps_of_state_cteD])
    apply (clarsimp simp: cap_master_cap_def)
   apply (erule ex_cte_cap_wp_to_weakenE)
   apply (clarsimp simp: appropriate_cte_cap_def)
  apply (rule conjI)
   apply (drule valid_global_refsD2, clarsimp)
   subgoal by (simp add: cap_range_def)
  apply (rule conjI[rotated])
   apply (frule(1) cap_refs_in_kernel_windowD)
   apply (simp add: cap_range_def)
  apply (drule unique_table_refs_no_cap_asidE[where S="{p}"])
   apply (simp add: valid_arch_caps_def)
  apply (simp add: no_cap_to_obj_with_diff_ref_def table_cap_ref_def Ball_def)
  done

lemma arch_update_cap_invs_unmap_page_table:
  "\<lbrace>cte_wp_at (is_arch_update cap) p
             and invs and valid_cap cap
             and (\<lambda>s. cte_wp_at (\<lambda>c. is_final_cap' c s) p s)
             and obj_at (empty_table {}) (obj_ref_of cap)
             and (\<lambda>s. cte_wp_at (\<lambda>c. \<forall>r. vs_cap_ref c = Some r
                                \<longrightarrow> \<not> (r \<unrhd> obj_ref_of cap) s) p s)
             and K (is_pt_cap cap \<and> vs_cap_ref cap = None)\<rbrace>
  set_cap cap p
  \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def)
  apply (rule hoare_pre)
   apply (wp arch_update_cap_pspace arch_update_cap_valid_mdb set_cap_idle
             update_cap_ifunsafe valid_irq_node_typ set_cap_typ_at
             set_cap_irq_handlers set_cap_valid_arch_caps
             set_cap_cap_refs_respects_device_region_spec[where ptr = p])
  apply (simp add: final_cap_at_eq)
  apply (clarsimp simp: cte_wp_at_caps_of_state is_arch_update_def
                        is_cap_simps cap_master_cap_simps
                        appropriate_cte_cap_irqs is_pt_cap_def
                        fun_eq_iff[where f="cte_refs cap" for cap]
                 dest!: cap_master_cap_eqDs
              simp del: imp_disjL)
  apply (rule conjI)
   apply (drule(1) if_unsafe_then_capD [OF caps_of_state_cteD])
    apply (clarsimp simp: cap_master_cap_def)
   apply (erule ex_cte_cap_wp_to_weakenE)
   apply (clarsimp simp: appropriate_cte_cap_def)
  apply (rule conjI)
   apply (drule valid_global_refsD2, clarsimp)
   apply (simp add: cap_range_def)
  apply (frule(1) cap_refs_in_kernel_windowD)
  apply (simp add: cap_range_def obj_irq_refs_def image_def)
  apply (intro conjI)
    apply (clarsimp simp: no_cap_to_obj_with_diff_ref_def
                          cte_wp_at_caps_of_state)
    apply fastforce
   apply (clarsimp simp: obj_at_def empty_table_def)
   apply (clarsimp split: Structures_A.kernel_object.split_asm
                          arch_kernel_obj.split_asm)
  apply clarsimp
  apply fastforce
  done

lemma arch_update_cap_invs_unmap_page_directory:
  "\<lbrace>cte_wp_at (is_arch_update cap) p
             and invs and valid_cap cap
             and (\<lambda>s. cte_wp_at (\<lambda>c. is_final_cap' c s) p s)
             and obj_at (empty_table {}) (obj_ref_of cap)
             and (\<lambda>s. cte_wp_at (\<lambda>c. \<forall>r. vs_cap_ref c = Some r
                                \<longrightarrow> \<not> (r \<unrhd> obj_ref_of cap) s) p s)
             and K (is_pd_cap cap \<and> vs_cap_ref cap = None)\<rbrace>
  set_cap cap p
  \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def)
  apply (rule hoare_pre)
   apply (wp arch_update_cap_pspace arch_update_cap_valid_mdb set_cap_idle
             update_cap_ifunsafe valid_irq_node_typ set_cap_typ_at
             set_cap_irq_handlers set_cap_valid_arch_caps
             set_cap_cap_refs_respects_device_region_spec[where ptr = p])
  apply (simp add: final_cap_at_eq)
  apply (clarsimp simp: cte_wp_at_caps_of_state is_arch_update_def
                        is_cap_simps cap_master_cap_simps
                        appropriate_cte_cap_irqs is_pt_cap_def
                        fun_eq_iff[where f="cte_refs cap" for cap]
                 dest!: cap_master_cap_eqDs
              simp del: imp_disjL)
  apply (rule conjI)
   apply (drule(1) if_unsafe_then_capD [OF caps_of_state_cteD])
    apply (clarsimp simp: cap_master_cap_def)
   apply (erule ex_cte_cap_wp_to_weakenE)
   apply (clarsimp simp: appropriate_cte_cap_def)
  apply (rule conjI)
   apply (drule valid_global_refsD2, clarsimp)
   apply (simp add: cap_range_def)
  apply (frule(1) cap_refs_in_kernel_windowD)
  apply (simp add: cap_range_def obj_irq_refs_def image_def)
  apply (intro conjI)
    apply (clarsimp simp: no_cap_to_obj_with_diff_ref_def
                          cte_wp_at_caps_of_state)
    apply fastforce
   apply (clarsimp simp: obj_at_def empty_table_def)
   apply (clarsimp split: Structures_A.kernel_object.split_asm
                          arch_kernel_obj.split_asm)
  apply clarsimp
  apply fastforce
  done

lemma arch_update_cap_invs_unmap_pd_pointer_table:
  "\<lbrace>cte_wp_at (is_arch_update cap) p
             and invs and valid_cap cap
             and (\<lambda>s. cte_wp_at (\<lambda>c. is_final_cap' c s) p s)
             and obj_at (empty_table {}) (obj_ref_of cap)
             and (\<lambda>s. cte_wp_at (\<lambda>c. \<forall>r. vs_cap_ref c = Some r
                                \<longrightarrow> \<not> (r \<unrhd> obj_ref_of cap) s) p s)
             and K (is_pdpt_cap cap \<and> vs_cap_ref cap = None)\<rbrace>
  set_cap cap p
  \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def)
  apply (rule hoare_pre)
   apply (wp arch_update_cap_pspace arch_update_cap_valid_mdb set_cap_idle
             update_cap_ifunsafe valid_irq_node_typ set_cap_typ_at
             set_cap_irq_handlers set_cap_valid_arch_caps
             set_cap_cap_refs_respects_device_region_spec[where ptr = p])
  apply (simp add: final_cap_at_eq)
  apply (clarsimp simp: cte_wp_at_caps_of_state is_arch_update_def
                        is_cap_simps cap_master_cap_simps
                        appropriate_cte_cap_irqs is_pt_cap_def
                        fun_eq_iff[where f="cte_refs cap" for cap]
                 dest!: cap_master_cap_eqDs
              simp del: imp_disjL)
  apply (rule conjI)
   apply (drule(1) if_unsafe_then_capD [OF caps_of_state_cteD])
    apply (clarsimp simp: cap_master_cap_def)
   apply (erule ex_cte_cap_wp_to_weakenE)
   apply (clarsimp simp: appropriate_cte_cap_def)
  apply (rule conjI)
   apply (drule valid_global_refsD2, clarsimp)
   apply (simp add: cap_range_def)
  apply (frule(1) cap_refs_in_kernel_windowD)
  apply (simp add: cap_range_def obj_irq_refs_def image_def)
  apply (intro conjI)
    apply (clarsimp simp: no_cap_to_obj_with_diff_ref_def
                          cte_wp_at_caps_of_state)
    apply fastforce
   apply (clarsimp simp: obj_at_def empty_table_def)
   apply (clarsimp split: Structures_A.kernel_object.split_asm
                          arch_kernel_obj.split_asm)
  apply clarsimp
  apply fastforce
  done

lemma arch_update_cap_invs_unmap_page_map_l4:
  "\<lbrace>cte_wp_at (is_arch_update cap) p
             and invs and valid_cap cap
             and (\<lambda>s. cte_wp_at (\<lambda>c. is_final_cap' c s) p s)
             and obj_at (empty_table {}) (obj_ref_of cap)
             and (\<lambda>s. cte_wp_at (\<lambda>c. \<forall>r. vs_cap_ref c = Some r
                                \<longrightarrow> \<not> (r \<unrhd> obj_ref_of cap) s) p s)
             and K (is_pml4_cap cap \<and> vs_cap_ref cap = None)\<rbrace>
  set_cap cap p
  \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: invs_def valid_state_def)
  apply (rule hoare_pre)
   apply (wp arch_update_cap_pspace arch_update_cap_valid_mdb set_cap_idle
             update_cap_ifunsafe valid_irq_node_typ set_cap_typ_at
             set_cap_irq_handlers set_cap_valid_arch_caps
             set_cap_cap_refs_respects_device_region_spec[where ptr = p])
  apply (simp add: final_cap_at_eq)
  apply (clarsimp simp: cte_wp_at_caps_of_state is_arch_update_def
                        is_cap_simps cap_master_cap_simps
                        appropriate_cte_cap_irqs is_pt_cap_def
                        fun_eq_iff[where f="cte_refs cap" for cap]
                 dest!: cap_master_cap_eqDs
              simp del: imp_disjL)
  apply (rule conjI)
   apply (drule(1) if_unsafe_then_capD [OF caps_of_state_cteD])
    apply (clarsimp simp: cap_master_cap_def)
   apply (erule ex_cte_cap_wp_to_weakenE)
   apply (clarsimp simp: appropriate_cte_cap_def)
  apply (rule conjI)
   apply (drule valid_global_refsD2, clarsimp)
   apply (simp add: cap_range_def)
  apply (frule(1) cap_refs_in_kernel_windowD)
  apply (simp add: cap_range_def obj_irq_refs_def image_def)
  apply (intro conjI)
    apply (clarsimp simp: no_cap_to_obj_with_diff_ref_def
                          cte_wp_at_caps_of_state)
    apply fastforce
   apply (clarsimp simp: obj_at_def empty_table_def)
   apply (clarsimp split: Structures_A.kernel_object.split_asm
                          arch_kernel_obj.split_asm)
  apply clarsimp
  apply fastforce
  done

lemma invalidateTLBEntry_underlying_memory:
  "\<lbrace>\<lambda>m'. underlying_memory m' p = um\<rbrace>
   invalidateTLBEntry a
   \<lbrace>\<lambda>_ m'. underlying_memory m' p = um\<rbrace>"
  by (clarsimp simp: invalidateTLBEntry_def machine_op_lift_def
                     machine_rest_lift_def split_def | wp)+

lemmas invalidateTLBEntry_irq_masks = no_irq[OF no_irq_invalidateTLBEntry]

crunch device_state_inv[wp]: invalidateTLBEntry "\<lambda>ms. P (device_state ms)"
  (ignore: ignore_failure)

lemma dmo_invalidateTLBEntry_invs[wp]:
  "\<lbrace>invs\<rbrace> do_machine_op (invalidateTLBEntry a) \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (wp dmo_invs)
  apply safe
   apply (drule use_valid)
     apply (rule invalidateTLBEntry_underlying_memory)
    apply (fastforce+)
  apply (erule (1) use_valid[OF _ invalidateTLBEntry_irq_masks])
  done

crunch device_state[wp]: invalidateTranslationSingleASID "\<lambda>ms. P (device_state ms)"

lemma invalidatePageStructureCache_invs[wp]:
  "\<lbrace>invs\<rbrace>do_machine_op (invalidateTranslationSingleASID a b)\<lbrace>\<lambda>_. invs\<rbrace>"
  sorry (* invalidatePageStructureCache invs *)

lemma flush_table_invs[wp]:
  "\<lbrace>invs\<rbrace> flush_table pm vaddr pt vspace \<lbrace>\<lambda>rv. invs\<rbrace>"
  by (wp mapM_x_wp_inv_weak get_cap_wp | wpc | simp add: flush_table_def)+

crunch vs_lookup[wp]: flush_table "\<lambda>s. P (vs_lookup s)"
  (wp: mapM_x_wp_inv_weak get_cap_wp simp: crunch_simps)

crunch cte_wp_at[wp]: flush_table "\<lambda>s. P (cte_wp_at P' p s)"
  (wp: mapM_x_wp_inv_weak crunch_wps simp: crunch_simps)

lemma global_refs_arch_update_eq:
  "\<lbrakk> x64_global_pml4 (f (arch_state s)) = x64_global_pml4 (arch_state s);
     x64_global_pdpts (f (arch_state s)) = x64_global_pdpts (arch_state s);
     x64_global_pds (f (arch_state s)) = x64_global_pds (arch_state s);
     x64_global_pts (f (arch_state s)) = x64_global_pts (arch_state s)\<rbrakk>
       \<Longrightarrow> global_refs (arch_state_update f s) = global_refs s"
  by (simp add: global_refs_def)

crunch global_refs_inv[wp]: flush_table "\<lambda>s. P (global_refs s)"
  (wp: mapM_x_wp_inv_weak crunch_wps simp: crunch_simps global_refs_arch_update_eq)

lemma lookup_pml4_slot_kernel_mappings:
  "\<lbrakk>vptr < pptr_base; canonical_address vptr; is_aligned pml4 pml4_bits\<rbrakk>
    \<Longrightarrow> ucast (lookup_pml4_slot pml4 vptr && mask pml4_bits >> word_size_bits) \<notin> kernel_mapping_slots"
  by (simp add: less_kernel_base_mapping_slots)

lemma not_in_global_refs_vs_lookup:
  "(\<exists>\<rhd> p) s \<and> valid_vs_lookup s \<and> valid_global_refs s
            \<and> valid_arch_state s \<and> valid_global_objs s
        \<longrightarrow> p \<notin> global_refs s"
  apply (clarsimp dest!: valid_vs_lookupD[OF vs_lookup_pages_vs_lookupI])
  apply (drule(1) valid_global_refsD2)
  apply (simp add: cap_range_def)
  apply blast
  done

crunch device_state_inv[wp]: invalidateASID,resetCR3 "\<lambda>s. P (device_state s)"

lemma resetCR3_underlying_memory[wp]:
  "\<lbrace>\<lambda>m'. underlying_memory m' p = um\<rbrace> resetCR3 \<lbrace>\<lambda>_ m'. underlying_memory m' p = um\<rbrace>"
  by (clarsimp simp: resetCR3_def machine_op_lift_def machine_rest_lift_def split_def | wp)+

lemma invalidateASID_underlying_memory[wp]:
  "\<lbrace>\<lambda>m'. underlying_memory m' p = um\<rbrace> invalidateASID vspace asid \<lbrace>\<lambda>_ m'. underlying_memory m' p = um\<rbrace>"
  by (clarsimp simp: invalidateASID_def machine_op_lift_def machine_rest_lift_def split_def | wp)+

lemma no_irq_invalidateASID: "no_irq (invalidateASID vpsace asid)"
  by (clarsimp simp: invalidateASID_def)

lemmas resetCR3_irq_masks = no_irq[OF no_irq_resetCR3]
lemmas invalidateASID_irq_masks = no_irq[OF no_irq_invalidateASID]

lemma flush_all_invs[wp]:
  "\<lbrace>invs\<rbrace> flush_all vspace asid \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (simp add: flush_all_def)
  apply (wp dmo_invs)
  apply safe
   apply (drule use_valid[OF _ invalidateASID_underlying_memory])
    apply fastforce+
  apply (erule (1) use_valid[OF _ invalidateASID_irq_masks])
  done

lemma valid_asid_table_injD:
  "\<lbrakk>(a,b) \<in> vs_asid_refs (x64_asid_table (arch_state s)); (a,c) \<in> vs_asid_refs (x64_asid_table (arch_state s));
    valid_asid_table (x64_asid_table (arch_state s)) s\<rbrakk>
  \<Longrightarrow> c = b"
  sorry

lemma update_aobj_not_reachable:
  "\<lbrace>\<lambda>s. lookup_refs (Some (ArchObj aobj)) vs_lookup_pages1_on_heap_obj \<subseteq> lookup_refs (kheap s p) vs_lookup_pages1_on_heap_obj
    \<and> (b, p) \<in> (vs_lookup_pages s) \<and> (VSRef offset (Some ty), ptr) \<notin> vs_refs_pages (ArchObj aobj)
    \<and> valid_asid_table (x64_asid_table (arch_state s)) s\<rbrace>
  update_object p
        (ArchObj aobj)
  \<lbrace>\<lambda>yb s. ([VSRef offset (Some ty)] @ b, ptr) \<notin> vs_lookup_pages s\<rbrace>"
  apply (simp add: update_object_def set_object_def)
  apply (wp get_object_wp)
  apply (clarsimp simp: vs_lookup_pages_def)
  apply (erule rtranclE[where b = "(VSRef offset (Some ty) # b, ptr)"])
   apply (clarsimp simp: vs_asid_refs_def)
  apply (case_tac y, clarsimp)
  apply (cut_tac s1 = s in lookup_bound_estimate[OF vs_lookup_pages1_is_wellformed_lookup, rotated -1])
     apply (simp add: Image_def)
     apply (rule_tac x = "(aa, baa)" in bexI[rotated])
     apply assumption
    apply (simp add: fun_upd_def[symmetric])
    apply (rule_tac s4 = s in vs_lookup_pages1_is_wellformed_lookup[where s = "s\<lparr>kheap := kheap s(p \<mapsto> ArchObj aobj)\<rparr>" for s
                ,simplified])
   apply (clarsimp simp: lookup_refs_def vs_lookup_pages1_on_heap_obj_def vs_refs_pages_def image_def obj_at_def
                         graph_of_def pde_ref_pages_def Image_def split: if_split_asm pde.split_asm)
  apply (clarsimp dest!: vs_lookup_pages1D)
  apply (subgoal_tac "p = pa")
   apply (clarsimp simp: obj_at_def)
  apply (subgoal_tac "a = ab")
   apply simp
   apply (drule(1) valid_asid_table_injD)
    apply simp
   apply simp
   apply (erule wellformed_lookup.lookupable_is_unique[OF vs_lookup_pages1_is_wellformed_lookup])
   apply simp
  apply (clarsimp simp: vs_lookup_pages_def vs_asid_refs_def
                 dest!: wellformed_lookup.lookup_ref_step[OF vs_lookup_pages1_is_wellformed_lookup] vs_lookup_pages1D)
  done

lemma lookup_refs_pdpt_shrink_strg:
  "ko_at (ArchObj (PDPointerTable pdpt)) ptr s \<longrightarrow>
    lookup_refs (Some (ArchObj (PDPointerTable (pdpt(slot := InvalidPDPTE))))) vs_lookup_pages1_on_heap_obj
      \<subseteq> lookup_refs (kheap s ptr) vs_lookup_pages1_on_heap_obj"
  by (clarsimp simp: obj_at_def lookup_refs_def vs_lookup_pages1_on_heap_obj_def
                        vs_refs_pages_def graph_of_def pdpte_ref_pages_def image_def
                 split: if_splits)

lemma lookup_refs_pd_shrink_strg:
  "ko_at (ArchObj (PageDirectory pd)) ptr s \<longrightarrow>
    lookup_refs (Some (ArchObj (PageDirectory (pd(slot := InvalidPDE))))) vs_lookup_pages1_on_heap_obj
      \<subseteq> lookup_refs (kheap s ptr) vs_lookup_pages1_on_heap_obj"
  by (clarsimp simp: obj_at_def lookup_refs_def vs_lookup_pages1_on_heap_obj_def
                        vs_refs_pages_def graph_of_def pdpte_ref_pages_def image_def
                 split: if_splits)

crunch vs_lookup_pages[wp]: flush_all "\<lambda>s. P (vs_lookup_pages s)"
crunch obj_at[wp]: flush_all "\<lambda>s. P (obj_at Q q s)"
crunch valid_arch_state[wp]: flush_all "\<lambda>s. valid_arch_state s"

crunch vs_lookup_pages[wp]: flush_table "\<lambda>s. P (vs_lookup_pages s)"
 (wp: mapM_x_wp_inv_weak get_cap_wp simp: flush_table_def)

crunch obj_at[wp]: flush_table "\<lambda>s. P (obj_at Q q s)"
 (wp: mapM_x_wp_inv_weak get_cap_wp simp: flush_table_def)

crunch valid_arch_state[wp]: flush_table "\<lambda>s. valid_arch_state s"
 (wp: mapM_x_wp_inv_weak get_cap_wp simp: flush_table_def)

lemma valid_arch_state_asid_table_strg:
  "valid_arch_state s \<longrightarrow> valid_asid_table (x64_asid_table (arch_state s)) s"
  by (simp add: valid_arch_state_def)

lemma not_in_vs_refs_pages_strg:
  "ptr = ucast ptr' \<longrightarrow> (VSRef ptr (Some APDPointerTable), pd)
    \<notin> vs_refs_pages (ArchObj (PDPointerTable (pda(ptr' := InvalidPDPTE))))"
  by (clarsimp simp: vs_refs_pages_def graph_of_def pdpte_ref_pages_def)

lemma vs_lookup_pages_current_cr3[iff]:
  "(vs_lookup_pages (s\<lparr>arch_state := arch_state s\<lparr>x64_current_cr3 := p\<rparr>\<rparr>)) =
   vs_lookup_pages s"
  by (simp add: vs_lookup_pages_arch_update)

crunch vs_lookup_pages[wp]: invalidateLocalPageStructureCacheASID "\<lambda>s. P (vs_lookup_pages s)"
  (simp: crunch_simps wp: crunch_wps)

(* FIXME x64: unmap_pdpt_vs_lookup_pages_pre might also needed here*)
lemma unmap_pd_vs_lookup_pages_pre:
  "\<lbrace>pspace_aligned and valid_arch_objs and valid_arch_state\<rbrace>unmap_pd asid vaddr pd
   \<lbrace>\<lambda>r s. (the (vs_cap_ref (ArchObjectCap (PageDirectoryCap pd (Some (asid,vaddr))))),pd) \<notin> vs_lookup_pages s\<rbrace>"
  apply (clarsimp simp: unmap_pd_def vs_cap_ref_simps store_pdpte_def)
  apply wp
        apply (rule update_aobj_not_reachable[where b = "[b,c,d]" for b c d,simplified])
  apply (strengthen lookup_refs_pdpt_shrink_strg valid_arch_state_asid_table_strg not_in_vs_refs_pages_strg
         | clarsimp )+
      apply (strengthen imp_consequent | wp hoare_vcg_all_lift  | clarsimp simp: conj_ac)+
     apply (wpc | wp get_pdpte_wp get_pml4e_wp assertE_wp | clarsimp simp: lookup_pdpt_slot_def find_vspace_for_asid_def)+
  apply auto
  sorry  (* OK, need a better way to apply vs_lookup_pagesE_alt for all the subgoals *)

lemma unmap_pt_vs_lookup_pages_pre:
  "\<lbrace>pspace_aligned and valid_arch_objs and valid_arch_state\<rbrace>unmap_page_table asid vaddr pt
   \<lbrace>\<lambda>r s. (the (vs_cap_ref (ArchObjectCap (PageTableCap pt (Some (asid,vaddr))))),pt) \<notin> vs_lookup_pages s\<rbrace>"
  apply (clarsimp simp: unmap_page_table_def vs_cap_ref_simps)
  apply wp
    apply (clarsimp simp: unmap_pd_def vs_cap_ref_simps store_pde_def)
  apply wp
        apply (rule update_aobj_not_reachable[where b = "[b,c,d,e]" for b c d e,simplified])
  apply (strengthen lookup_refs_pd_shrink_strg valid_arch_state_asid_table_strg not_in_vs_refs_pages_strg
         | clarsimp )+
      apply (strengthen imp_consequent | wp hoare_vcg_all_lift  | clarsimp simp: conj_ac)+
     apply (wpc | wp get_pdpte_wp get_pml4e_wp get_pde_wp assertE_wp
                | clarsimp simp: lookup_pdpt_slot_def find_vspace_for_asid_def lookup_pd_slot_def)+
  apply auto
  sorry (* OK, need a better way to apply vs_lookup_pagesE_alt for all the subgoals *)

lemma unmap_pd_vs_lookup_pages:
  "\<lbrace>pspace_aligned and valid_arch_objs and valid_arch_state\<rbrace> unmap_pd asid vaddr pd
  \<lbrace>\<lambda>r s. ([VSRef ((vaddr >> 30) && mask 9) (Some APDPointerTable), VSRef ((vaddr >> 39) && mask 9) (Some APageMapL4),
                       VSRef (asid && mask asid_low_bits) (Some AASIDPool), VSRef (ucast (asid_high_bits_of asid)) None],
        pd)
       \<notin> vs_lookup_pages s\<rbrace>"
  apply (rule hoare_pre)
  apply (rule hoare_post_imp[OF _ unmap_pd_vs_lookup_pages_pre])
   apply (simp add: vs_cap_ref_def)
  apply simp
  done

lemma unmap_pt_vs_lookup_pages:
  "\<lbrace>pspace_aligned and valid_arch_objs and valid_arch_state\<rbrace> unmap_page_table asid vaddr pt
           \<lbrace>\<lambda>rv s. ([VSRef ((vaddr >> 21) && mask 9) (Some APageDirectory), VSRef ((vaddr >> 30) && mask 9) (Some APDPointerTable),
                     VSRef ((vaddr >> 39) && mask 9) (Some APageMapL4), VSRef (asid && mask asid_low_bits) (Some AASIDPool),
                     VSRef (ucast (asid_high_bits_of asid)) None],
                    pt) \<notin> vs_lookup_pages s\<rbrace>"
  apply (rule hoare_pre)
  apply (rule hoare_post_imp[OF _ unmap_pt_vs_lookup_pages_pre])
   apply (simp add: vs_cap_ref_def)
  apply simp
  done

lemma unmap_pdpt_invs[wp]:
  "\<lbrace>invs and K (asid \<le> mask asid_bits \<and> vaddr < pptr_base \<and> canonical_address vaddr)\<rbrace>
     unmap_pdpt asid vaddr pdpt
   \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: unmap_pdpt_def)
  apply (rule hoare_pre)
   apply (wp store_pml4e_invs do_machine_op_global_refs_inv get_pml4e_wp
             hoare_vcg_all_lift find_vspace_for_asid_lots
        | wpc | simp add: flush_all_def pml4e_ref_pages_def)+
  apply (strengthen lookup_pml4_slot_kernel_mappings[THEN notE[where R=False], rotated -1, mk_strg D], simp)
  apply (strengthen not_in_global_refs_vs_lookup)+
  apply (auto simp: vspace_at_asid_def page_map_l4_at_aligned_pml4_bits[simplified] invs_arch_objs
                    invs_psp_aligned lookup_pml4_slot_eq pml4e_ref_def)
  done

crunch invs[wp]: lookup_pdpt_slot "\<lambda>s. P s"
crunch invs[wp]: lookup_pd_slot "\<lambda>s. P s"

lemma pdpte_at_strg:
  "pdpte_at p s \<Longrightarrow> typ_at (AArch APDPointerTable) (p && ~~ mask pdpt_bits) s"
  by (simp add: pdpte_at_def)
lemma pde_at_strg:
  "pde_at p s \<Longrightarrow> typ_at (AArch APageDirectory) (p && ~~ mask pd_bits) s"
  by (simp add: pde_at_def)

lemma vs_lookup1_archD:
  "(x \<rhd>1 y) s \<Longrightarrow> \<exists>rs r p p' ko. x = (rs,p) \<and> y = (r # rs,p')
                          \<and> ko_at (ArchObj ko) p s \<and> (r,p') \<in> vs_refs_arch ko"
  by (clarsimp dest!: vs_lookup1D simp: obj_at_def vs_refs_def split: kernel_object.splits)

crunch invs[wp]: invalidateLocalPageStructureCacheASID invs

lemma unmap_pd_invs[wp]:
  "\<lbrace>invs and K (asid \<le> mask asid_bits \<and> vaddr < pptr_base \<and> canonical_address vaddr)\<rbrace>
     unmap_pd asid vaddr pd
   \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: unmap_pd_def)
  apply (rule hoare_pre)
   apply (wp_trace store_pdpte_invs do_machine_op_global_refs_inv get_pdpte_wp
             hoare_vcg_all_lift find_vspace_for_asid_lots
        | wpc | simp add: flush_all_def pdpte_ref_pages_def
        | strengthen imp_consequent )+
   apply (strengthen not_in_global_refs_vs_lookup invs_valid_vs_lookup invs_valid_global_refs
           invs_arch_state invs_valid_global_objs | wp)+
  apply (auto simp: vspace_at_asid_def page_map_l4_at_aligned_pml4_bits[simplified] invs_arch_objs
                    invs_psp_aligned lookup_pml4_slot_eq pml4e_ref_def)
  done

lemma unmap_pt_invs[wp]:
  "\<lbrace>invs and K (asid \<le> mask asid_bits \<and> vaddr < pptr_base \<and> canonical_address vaddr)\<rbrace>
     unmap_page_table asid vaddr pt
   \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: unmap_page_table_def)
  apply (rule hoare_pre)
   apply (wp_trace store_pde_invs do_machine_op_global_refs_inv get_pde_wp
             hoare_vcg_all_lift find_vspace_for_asid_lots
        | wpc | simp add: flush_all_def pdpte_ref_pages_def
        | strengthen imp_consequent )+
      apply (strengthen not_in_global_refs_vs_lookup invs_valid_vs_lookup invs_valid_global_refs
           invs_arch_state invs_valid_global_objs | wp)+
  apply (auto simp: vspace_at_asid_def page_map_l4_at_aligned_pml4_bits[simplified] invs_arch_objs
                    invs_psp_aligned lookup_pml4_slot_eq pml4e_ref_def)
  done

lemma final_cap_lift:
  assumes x: "\<And>P. \<lbrace>\<lambda>s. P (caps_of_state s)\<rbrace> f \<lbrace>\<lambda>rv s. P (caps_of_state s)\<rbrace>"
  shows      "\<lbrace>\<lambda>s. P (is_final_cap' cap s)\<rbrace> f \<lbrace>\<lambda>rv s. P (is_final_cap' cap s)\<rbrace>"
  by (simp add: is_final_cap'_def2 cte_wp_at_caps_of_state, rule x)

lemmas dmo_final_cap[wp] = final_cap_lift [OF do_machine_op_caps_of_state]
lemmas store_pte_final_cap[wp] = final_cap_lift [OF store_pte_caps_of_state]
lemmas unmap_page_table_final_cap[wp] = final_cap_lift [OF unmap_page_table_caps_of_state]
lemmas unmap_page_directory_final_cap[wp] = final_cap_lift [OF unmap_pd_caps_of_state]
lemmas unmap_pdpt_final_cap[wp] = final_cap_lift [OF unmap_pdpt_caps_of_state]


lemma mapM_x_swp_store_empty_pt':
  "\<lbrace>obj_at (\<lambda>ko. \<exists>pt. ko = ArchObj (PageTable pt)
                 \<and> (\<forall>x. x \<in> (\<lambda>sl. ucast ((sl && mask pt_bits) >> word_size_bits)) ` set slots
                           \<or> pt x = InvalidPTE)) p
         and K (is_aligned p pt_bits \<and> (\<forall>x \<in> set slots. x && ~~ mask pt_bits = p))\<rbrace>
      mapM_x (swp store_pte InvalidPTE) slots
   \<lbrace>\<lambda>rv. obj_at (empty_table {}) p\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (induct slots, simp_all add: mapM_x_Nil mapM_x_Cons)
   apply wp
   apply (clarsimp simp: obj_at_def empty_table_def fun_eq_iff)
  apply (rule hoare_seq_ext, assumption)
  apply (thin_tac "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q)
  apply (simp add: store_pte_def update_object_def set_object_def)
  apply (wp get_object_wp | simp)
  apply (clarsimp simp: obj_at_def)
  apply auto
  done

lemma mapM_x_swp_store_empty_pd':
  "\<lbrace>obj_at (\<lambda>ko. \<exists>pd. ko = ArchObj (PageDirectory pd)
                 \<and> (\<forall>x. x \<in> (\<lambda>sl. ucast ((sl && mask pd_bits) >> word_size_bits)) ` set slots
                           \<or> pd x = InvalidPDE)) p
         and K (is_aligned p pt_bits \<and> (\<forall>x \<in> set slots. x && ~~ mask pd_bits = p))\<rbrace>
      mapM_x (swp store_pde InvalidPDE) slots
   \<lbrace>\<lambda>rv. obj_at (empty_table {}) p\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (induct slots, simp_all add: mapM_x_Nil mapM_x_Cons)
   apply wp
   apply (clarsimp simp: obj_at_def empty_table_def fun_eq_iff)
  apply (rule hoare_seq_ext, assumption)
  apply (thin_tac "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q)
  apply (simp add: store_pde_def update_object_def set_object_def)
  apply (wp get_object_wp | simp)
  apply (clarsimp simp: obj_at_def)
  apply auto
  done

lemma mapM_x_swp_store_empty_pt:
  "\<lbrace>page_table_at p and pspace_aligned
       and K ((UNIV :: 9 word set) \<subseteq> (\<lambda>sl. ucast ((sl && mask pt_bits) >> word_size_bits)) ` set slots
                       \<and> (\<forall>x\<in>set slots. x && ~~ mask pt_bits = p))\<rbrace>
     mapM_x (swp store_pte InvalidPTE) slots
   \<lbrace>\<lambda>rv. obj_at (empty_table {}) p\<rbrace>"
  apply (wp mapM_x_swp_store_empty_pt')
  apply (clarsimp simp: obj_at_def a_type_def)
  apply (clarsimp split: Structures_A.kernel_object.split_asm
                         arch_kernel_obj.split_asm if_split_asm)
  apply (frule(1) pspace_alignedD)
  apply (clarsimp simp: pt_bits_def pageBits_def image_def table_size_def ptTranslationBits_def word_size_bits_def)
  apply blast
  done

lemma mapM_x_swp_store_empty_pd:
  "\<lbrace>page_directory_at p and pspace_aligned
       and K ((UNIV :: 9 word set) \<subseteq> (\<lambda>sl. ucast ((sl && mask pd_bits) >> word_size_bits)) ` set slots
                       \<and> (\<forall>x\<in>set slots. x && ~~ mask pd_bits = p))\<rbrace>
     mapM_x (swp store_pde InvalidPDE) slots
   \<lbrace>\<lambda>rv. obj_at (empty_table {}) p\<rbrace>"
  apply (wp mapM_x_swp_store_empty_pd')
  apply (clarsimp simp: obj_at_def a_type_def)
  apply (clarsimp split: Structures_A.kernel_object.split_asm
                         arch_kernel_obj.split_asm if_split_asm)
  apply (frule(1) pspace_alignedD)
  apply (clarsimp simp: pt_bits_def pageBits_def image_def table_size_def ptTranslationBits_def word_size_bits_def)
  apply blast
  done

(* FIXME: move near Invariants_A.vs_lookup_2ConsD *)
lemma vs_lookup_pages_2ConsD:
  "((v # v' # vs) \<unrhd> p) s \<Longrightarrow>
   \<exists>p'. ((v' # vs) \<unrhd> p') s \<and> ((v' # vs, p') \<unrhd>1 (v # v' # vs, p)) s"
  apply (clarsimp simp: vs_lookup_pages_def)
  apply (erule rtranclE)
   apply (clarsimp simp: vs_asid_refs_def)
  apply (fastforce simp: vs_lookup_pages1_def)
  done

(* FIXME: move to Invariants_A *)
lemma vs_lookup_pages_eq_at:
  "[VSRef a None] \<rhd> pd = [VSRef a None] \<unrhd> pd"
  apply (simp add: vs_lookup_pages_def vs_lookup_def Image_def)
  apply (rule ext)
  apply (rule iffI)
   apply (erule bexEI)
   apply (erule rtranclE, simp)
   apply (clarsimp simp: vs_refs_def graph_of_def image_def
                  dest!: vs_lookup1D
                  split: Structures_A.kernel_object.splits
                         arch_kernel_obj.splits)
  apply (erule bexEI)
  apply (erule rtranclE, simp)
  apply (clarsimp simp: vs_refs_pages_def graph_of_def image_def
                 dest!: vs_lookup_pages1D
                 split: Structures_A.kernel_object.splits
                        arch_kernel_obj.splits)
  done

(* FIXME: move to Invariants_A *)
lemma vs_lookup_pages_eq_ap:
  "[VSRef b (Some AASIDPool), VSRef a None] \<rhd> pm =
   [VSRef b (Some AASIDPool), VSRef a None] \<unrhd> pm"
  apply (simp add: vs_lookup_pages_def vs_lookup_def Image_def)
  apply (rule ext)
  apply (rule iffI)
   apply (erule bexEI)
   apply (erule rtranclE, simp)
   apply (clarsimp simp: vs_refs_def graph_of_def image_def
                  dest!: vs_lookup1D
                  split: Structures_A.kernel_object.splits
                         arch_kernel_obj.splits)
   apply (erule rtranclE)
    apply (clarsimp simp: vs_asid_refs_def graph_of_def image_def)
    apply (rule converse_rtrancl_into_rtrancl[OF _ rtrancl_refl])
    apply (fastforce simp: vs_refs_pages_def graph_of_def image_def
                          vs_lookup_pages1_def)
   apply (clarsimp simp: vs_refs_def graph_of_def image_def
                  dest!: vs_lookup1D
                  split: Structures_A.kernel_object.splits
                         arch_kernel_obj.splits)
  apply (erule bexEI)
  apply (erule rtranclE, simp)
  apply (clarsimp simp: vs_refs_pages_def graph_of_def image_def
                 dest!: vs_lookup_pages1D
                 split: Structures_A.kernel_object.splits
                        arch_kernel_obj.splits)
  apply (erule rtranclE)
   apply (clarsimp simp: vs_asid_refs_def graph_of_def image_def)
   apply (rule converse_rtrancl_into_rtrancl[OF _ rtrancl_refl])
   apply (fastforce simp: vs_refs_def graph_of_def image_def
                         vs_lookup1_def)
  apply (clarsimp simp: vs_refs_pages_def graph_of_def image_def
                 dest!: vs_lookup_pages1D
                 split: Structures_A.kernel_object.splits
                        arch_kernel_obj.splits)
  done

(* FIXME: move to Invariants_A *)
lemma pte_ref_pages_invalid_None[simp]:
  "pte_ref_pages InvalidPTE = None"
  by (simp add: pte_ref_pages_def)

lemma is_final_cap_caps_of_state_2D:
  "\<lbrakk> caps_of_state s p = Some cap; caps_of_state s p' = Some cap';
     is_final_cap' cap'' s; obj_irq_refs cap \<inter> obj_irq_refs cap'' \<noteq> {};
     obj_irq_refs cap' \<inter> obj_irq_refs cap'' \<noteq> {} \<rbrakk>
       \<Longrightarrow> p = p'"
  apply (clarsimp simp: is_final_cap'_def3)
  apply (frule_tac x="fst p" in spec)
  apply (drule_tac x="snd p" in spec)
  apply (drule_tac x="fst p'" in spec)
  apply (drule_tac x="snd p'" in spec)
  apply (clarsimp simp: cte_wp_at_caps_of_state Int_commute
                        prod_eqI)
  done

(* FIXME: move *)
lemma empty_table_pt_capI:
  "\<lbrakk>caps_of_state s p =
    Some (cap.ArchObjectCap (arch_cap.PageTableCap pt None));
    valid_table_caps s\<rbrakk>
   \<Longrightarrow> obj_at (empty_table (set (x64_global_pdpts (arch_state s)))) pt s"
    apply (case_tac p)
    apply (clarsimp simp: valid_table_caps_def simp del: imp_disjL)
    apply (drule spec)+
    apply (erule impE, simp add: is_cap_simps)+
    by assumption

lemma arch_obj_pred_empty_table:
  "arch_obj_pred (empty_table S)"
  by (fastforce simp: arch_obj_pred_def non_arch_obj_def empty_table_def
               split: kernel_object.splits arch_kernel_obj.splits)

lemma arch_obj_pred_empty_refs_pages:
  "arch_obj_pred (\<lambda>ko. vs_refs_pages ko = {})"
  by (fastforce simp: arch_obj_pred_def non_arch_obj_def vs_refs_pages_def
               split: kernel_object.splits arch_kernel_obj.splits)

lemma arch_obj_pred_empty_refs:
  "arch_obj_pred (\<lambda>ko. vs_refs ko = {})"
  by (fastforce simp: arch_obj_pred_def non_arch_obj_def vs_refs_def
               split: kernel_object.splits arch_kernel_obj.splits)

lemma set_cap_cte_wp_at_ex:
  "\<lbrace>K (P cap) and cte_wp_at \<top> slot\<rbrace> set_cap cap slot \<lbrace>\<lambda>r s. \<exists>slot. cte_wp_at P slot s\<rbrace>"
  apply (rule hoare_pre)
   apply (wp hoare_vcg_ex_lift set_cap_cte_wp_at)
  apply fastforce
  done

lemma vs_cap_ref_of_table_capNone:
  "\<lbrakk>is_pd_cap cap \<or> is_pt_cap cap \<or> is_pdpt_cap cap \<or> is_pml4_cap cap; cap_asid cap = None\<rbrakk> \<Longrightarrow> vs_cap_ref cap = None"
  by (auto simp: cap_asid_def is_cap_simps vs_cap_ref_def split: cap.splits arch_cap.splits option.split_asm)

lemma unique_table_caps_ptD2:
  "\<lbrakk> is_pt_cap cap; cs p = Some cap; cap_asid cap = None;
     cs p' = Some cap';
     obj_refs cap' = obj_refs cap;
     unique_table_caps cs; valid_cap cap s; valid_cap cap' s\<rbrakk>
  \<Longrightarrow> p = p'"
  apply (erule(3) unique_table_caps_ptD)
    apply (clarsimp simp: is_cap_simps)
    apply (case_tac cap')
     apply (clarsimp simp: valid_cap_simps obj_at_def is_ep_def is_ntfn_def is_cap_table_def is_tcb_def
                    split: option.splits)+
     apply (rename_tac p acap pd)
     apply (case_tac acap)
      apply (clarsimp simp: valid_cap_simps obj_at_def is_ep_def is_ntfn_def is_cap_table_def is_tcb_def
                    split: option.splits if_splits)+
  done


lemma unique_table_caps_pdD2:
  "\<lbrakk> is_pd_cap cap; cs p = Some cap; cap_asid cap = None;
     cs p' = Some cap';
     obj_refs cap' = obj_refs cap;
     unique_table_caps cs; valid_cap cap s; valid_cap cap' s\<rbrakk>
  \<Longrightarrow> p = p'"
  apply (erule(3) unique_table_caps_pdD)
    apply (clarsimp simp: is_cap_simps)
    apply (case_tac cap')
     apply (clarsimp simp: valid_cap_simps obj_at_def is_ep_def is_ntfn_def is_cap_table_def is_tcb_def
                    split: option.splits)+
     apply (rename_tac p acap pd)
     apply (case_tac acap)
      apply (clarsimp simp: valid_cap_simps obj_at_def is_ep_def is_ntfn_def is_cap_table_def is_tcb_def
                    split: option.splits if_splits)+
  done

lemma unique_table_caps_pdptD2:
  "\<lbrakk> is_pdpt_cap cap; cs p = Some cap; cap_asid cap = None;
     cs p' = Some cap';
     obj_refs cap' = obj_refs cap;
     unique_table_caps cs; valid_cap cap s; valid_cap cap' s\<rbrakk>
  \<Longrightarrow> p = p'"
  apply (erule(3) unique_table_caps_pdptD)
    apply (clarsimp simp: is_cap_simps)
    apply (case_tac cap')
     apply (clarsimp simp: valid_cap_simps obj_at_def is_ep_def is_ntfn_def is_cap_table_def is_tcb_def
                    split: option.splits)+
     apply (rename_tac p acap pd)
     apply (case_tac acap)
      apply (clarsimp simp: valid_cap_simps obj_at_def is_ep_def is_ntfn_def is_cap_table_def is_tcb_def
                    split: option.splits if_splits)+
  done

lemma unique_table_caps_pml4D2:
  "\<lbrakk> is_pml4_cap cap; cs p = Some cap; cap_asid cap = None;
     cs p' = Some cap';
     obj_refs cap' = obj_refs cap;
     unique_table_caps cs; valid_cap cap s; valid_cap cap' s\<rbrakk>
  \<Longrightarrow> p = p'"
  apply (erule(3) unique_table_caps_pml4D)
    apply (clarsimp simp: is_cap_simps)
    apply (case_tac cap')
     apply (clarsimp simp: valid_cap_simps obj_at_def is_ep_def is_ntfn_def is_cap_table_def is_tcb_def
                    split: option.splits)+
     apply (rename_tac p acap pd)
     apply (case_tac acap)
      apply (clarsimp simp: valid_cap_simps obj_at_def is_ep_def is_ntfn_def is_cap_table_def is_tcb_def
                    split: option.splits if_splits)+
  done

lemma obj_refs_eqI:
  "\<lbrakk>a \<in> obj_refs c; a \<in> obj_refs b\<rbrakk> \<Longrightarrow> obj_refs c = obj_refs b"
  by (clarsimp dest!: obj_ref_elemD)

lemma valid_pd_cap_asidNone[simp]:
  "s \<turnstile> ArchObjectCap (PageDirectoryCap pa asid) \<Longrightarrow> s \<turnstile> ArchObjectCap (PageDirectoryCap pa None)"
  by (clarsimp simp: valid_cap_def cap_aligned_def)

lemma valid_pdpt_cap_asidNone[simp]:
  "s \<turnstile> ArchObjectCap (PDPointerTableCap pa asid) \<Longrightarrow> s \<turnstile> ArchObjectCap (PDPointerTableCap pa None)"
  by (clarsimp simp: valid_cap_def cap_aligned_def)

lemma valid_pt_cap_asidNone[simp]:
  "s \<turnstile> ArchObjectCap (PageTableCap pa asid) \<Longrightarrow> s \<turnstile> ArchObjectCap (PageTableCap pa None)"
  by (clarsimp simp: valid_cap_def cap_aligned_def)


lemma update_aobj_zombies[wp]:
  "\<lbrace>\<lambda>s. is_final_cap' cap s\<rbrace>
  update_object ptr (ArchObj obj)
  \<lbrace>\<lambda>_ s. is_final_cap' cap s\<rbrace>"
  apply (simp add: is_final_cap'_def2)
  apply (wp hoare_vcg_ex_lift hoare_vcg_all_lift update_aobj_cte_wp_at)
  done

crunch is_final_cap' [wp]: store_pde "is_final_cap' cap"
  (wp: crunch_wps simp: crunch_simps ignore: update_object set_pd)

crunch is_final_cap' [wp]: store_pte "is_final_cap' cap"
  (wp: crunch_wps simp: crunch_simps ignore: update_object set_pt)

crunch is_final_cap' [wp]: store_pdpte "is_final_cap' cap"
  (wp: crunch_wps simp: crunch_simps ignore: update_object set_pdpt)

crunch is_final_cap' [wp]: store_pml4e "is_final_cap' cap"
  (wp: crunch_wps simp: crunch_simps ignore: update_object set_pml4)

lemma lookup_pages_shrink_store_pde:
  "\<lbrace>\<lambda>s. p \<notin> vs_lookup_pages s\<rbrace> store_pde slot InvalidPDE \<lbrace>\<lambda>rv s. p \<notin> vs_lookup_pages s\<rbrace>"
  apply (case_tac p)
  apply (simp add: store_pde_def update_object_def set_object_def | wp get_object_wp | clarsimp)+
  apply (simp add: vs_lookup_pages_def)
  apply (drule_tac s1 = s in lookup_bound_estimate[OF vs_lookup_pages1_is_wellformed_lookup, rotated -1])
   apply (simp add: fun_upd_def[symmetric])
   apply (rule vs_lookup_pages1_is_wellformed_lookup[where s = "s\<lparr>kheap := kheap s(ptr \<mapsto> ArchObj obj)\<rparr>" for s ptr obj
                ,simplified])
   apply (clarsimp simp: lookup_refs_def vs_lookup_pages1_on_heap_obj_def vs_refs_pages_def image_def obj_at_def
                         graph_of_def pde_ref_pages_def split: if_split_asm pde.split_asm)
  apply clarsimp
  done

lemma lookup_pages_shrink_store_pte:
  "\<lbrace>\<lambda>s. p \<notin> vs_lookup_pages s\<rbrace> store_pte slot InvalidPTE \<lbrace>\<lambda>rv s. p \<notin> vs_lookup_pages s\<rbrace>"
  apply (case_tac p)
  apply (simp add: store_pte_def update_object_def set_object_def | wp get_object_wp | clarsimp)+
  apply (simp add: vs_lookup_pages_def)
  apply (drule_tac s1 = s in lookup_bound_estimate[OF vs_lookup_pages1_is_wellformed_lookup, rotated -1])
   apply (simp add: fun_upd_def[symmetric])
   apply (rule vs_lookup_pages1_is_wellformed_lookup[where s = "s\<lparr>kheap := kheap s(ptr \<mapsto> ArchObj obj)\<rparr>" for s ptr obj
                ,simplified])
   apply (clarsimp simp: lookup_refs_def vs_lookup_pages1_on_heap_obj_def vs_refs_pages_def image_def obj_at_def
                         graph_of_def pde_ref_pages_def split: if_split_asm pde.split_asm)
  apply clarsimp
  done


lemma store_invalid_pde_vs_lookup_pages_shrink:
  "\<lbrace>\<lambda>s. invs s \<and> p \<notin> vs_lookup_pages s\<rbrace> mapM_x (\<lambda>a. store_pde a InvalidPDE) ls \<lbrace>\<lambda>rv s. p \<notin> vs_lookup_pages s\<rbrace>"
  apply (wp mapM_x_wp lookup_pages_shrink_store_pde)
  apply force+
  done

lemma store_invalid_pte_vs_lookup_pages_shrink:
  "\<lbrace>\<lambda>s. invs s \<and> p \<notin> vs_lookup_pages s\<rbrace> mapM_x (\<lambda>a. store_pte a InvalidPTE) ls \<lbrace>\<lambda>rv s. p \<notin> vs_lookup_pages s\<rbrace>"
  apply (wp mapM_x_wp lookup_pages_shrink_store_pte)
  apply force+
  done

lemma set_current_cr3_global_refs[iff]:
  "global_refs (s\<lparr>arch_state := arch_state s\<lparr>x64_current_cr3 := param_a\<rparr>\<rparr>) = global_refs s"
  by (simp add: global_refs_def)

crunch global_refs[wp]: unmap_pd "\<lambda>s. P (global_refs s)"
crunch global_refs[wp]: unmap_pdpt "\<lambda>s. P (global_refs s)"
crunch global_refs[wp]: unmap_page_table "\<lambda>s. P (global_refs s)"

lemma range_neg_mask_strengthen:
  "P ptr \<Longrightarrow> (\<forall>x\<in>set [ptr , ptr + 2 ^ word_size_bits .e. ptr + 2 ^ table_size - 1]. P (x && ~~ mask table_size))"
  sorry (* word proof *)

lemma vtable_range_univ:
  "{y. \<exists>x\<in>set [ptr , ptr + 2 ^ word_size_bits .e. ptr + 2 ^ table_size - 1].
                          (y :: 9 word) = ucast (x && mask table_size >> word_size_bits)} = UNIV"
  sorry (* word proof *)

lemma empty_refs_strg:
  "empty_table {} a \<longrightarrow> (vs_refs_pages a = {})"
  by (simp add: empty_table_def split: kernel_object.splits arch_kernel_obj.splits)

lemma obj_at_empty_refs_strg:
  "obj_at (empty_table (set (x64_global_pdpts (arch_state s)))) ptr s \<longrightarrow> obj_at (\<lambda>a. vs_refs_pages a = {}) ptr s"
  apply (clarsimp simp: obj_at_def)
  done

lemma perform_page_directory_invocation_invs[wp]:
  "\<lbrace>invs and valid_pdi pdi\<rbrace>
     perform_page_directory_invocation pdi
   \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (cases pdi)
   apply (rename_tac cap cslot_ptr pdpte obj_ref)
   apply (rule hoare_pre)
   apply (clarsimp simp: perform_page_directory_invocation_def)
   apply (wp hoare_vcg_const_imp_lift hoare_vcg_all_lift  hoare_vcg_conj_lift
             store_pdpte_invs arch_update_cap_invs_map
           | strengthen obj_at_empty_refs_strg
           | simp add: arch_obj_pred_empty_table del: split_paired_all split_paired_All | wps
           | rule set_cap.aobj_at |wpc)+
     apply (rule set_cap_cte_wp_at_ex[simplified])
    apply wp+
    apply (clarsimp simp: valid_pdi_def is_arch_update_def cte_wp_at_caps_of_state
                          vs_cap_ref_of_table_capNone
                      simp del:  split_paired_All)
    apply (frule vs_lookup_pages_vs_lookupI)
     apply (rule conjI)
      apply (clarsimp dest!: same_master_cap_same_types simp: vs_cap_ref_of_table_capNone)
     apply (intro conjI allI)
      apply clarsimp
      apply (drule_tac ref = ref in valid_vs_lookupD)
       apply fastforce
      apply (rule ccontr, clarsimp)
      apply (frule_tac cap = x and cap' = capa in unique_table_caps_pdptD2[OF _ _ _ _ obj_refs_eqI invs_unique_table_caps])
          apply assumption+
       apply (erule caps_of_state_valid, fastforce)
      apply (erule caps_of_state_valid, fastforce)
     apply (clarsimp simp: is_cap_simps cap_asid_def vs_cap_ref_def split: option.split_asm)
    apply (clarsimp simp: is_cap_simps)
    apply (rule ref_is_unique)
          apply simp
         apply (erule(1) vs_lookup_vs_lookup_pagesI)
          apply fastforce+
         apply (simp add:global_refs_def)
        apply fastforce+
   apply (clarsimp dest!:invs_valid_objs valid_objs_caps)
  apply (rename_tac cap cslot)
  apply (clarsimp simp: perform_page_directory_invocation_def)
  apply (rule hoare_name_pre_state)
  apply (clarsimp simp: valid_pdi_def is_cap_simps)
  apply (rule hoare_pre)
   apply (wpc | clarsimp simp: cte_wp_at_caps_of_state | wp arch_update_cap_invs_unmap_page_directory get_cap_wp)+
    apply (rule_tac P = "is_pd_cap cap" in hoare_gen_asm)
    apply (rule_tac Q = "\<lambda>r. cte_wp_at (op = cap) (a,b) and invs and is_final_cap' cap
                             and (\<lambda>s. (the (vs_cap_ref (ArchObjectCap (PageDirectoryCap p (Some (x1, x2a))))), p) \<notin> vs_lookup_pages s)
                             and obj_at (empty_table {}) (the (aobj_ref (update_map_data (Structures_A.the_arch_cap cap) None)))"
                             in hoare_post_imp)
     apply (clarsimp simp: cte_wp_at_caps_of_state is_cap_simps update_map_data_def
                           is_arch_update_def cap_master_cap_simps)
     apply (clarsimp dest!: caps_of_state_valid_cap[OF _ invs_valid_objs] split: option.split_asm
                      simp: is_arch_diminished_def diminished_def mask_cap_def cap_rights_update_def
                            acap_rights_update_def vs_cap_ref_simps)
    apply (wp hoare_vcg_conj_lift)
        apply (wp mapM_x_wp, force)
       apply (rule mapM_x_swp_store_pde_invs_unmap[unfolded swp_def])
      apply (wp mapM_x_wp)
      apply force
     apply (wp store_invalid_pde_vs_lookup_pages_shrink)
    apply (wp mapM_x_swp_store_empty_pd[unfolded swp_def])
   apply (clarsimp simp: cte_wp_at_caps_of_state vs_cap_ref_def is_arch_diminished_def
                         is_cap_simps diminished_def mask_cap_def)
   apply (clarsimp simp: cap_rights_update_def
                         acap_rights_update_def
                  split: cap.split_asm arch_cap.split_asm)
   apply (wp unmap_pd_vs_lookup_pages)
  apply (clarsimp simp: is_final_cap'_def2 obj_irq_refs_def acap_rights_update_def cte_wp_at_caps_of_state
                        is_arch_diminished_def diminished_def mask_cap_def
                  del: )
  apply (clarsimp simp: cap_rights_update_def acap_rights_update_def is_arch_update_def is_cap_simps
                        update_map_data_def vs_cap_ref_simps invs_psp_aligned pd_bits_def
                 split: cap.split_asm arch_cap.split_asm)
  apply (intro conjI impI)
    apply fastforce
   apply (clarsimp simp: valid_cap_def)
   apply (drule valid_table_caps_pdD, force)
   apply (clarsimp simp: obj_at_def empty_table_def)
  apply (strengthen  range_neg_mask_strengthen[mk_strg])
    apply (frule valid_global_refsD2, force)
  apply (clarsimp simp: valid_cap_def wellformed_mapdata_def image_def le_mask_iff_lt_2n
                        cap_range_def invs_arch_objs pd_bits_def vtable_range_univ invs_arch_state)
  apply (simp add: mask_def)
  done

lemma valid_table_caps_empty_ptD:
  "\<lbrakk> caps_of_state s p = Some (ArchObjectCap (PageTableCap pt None));
     valid_table_caps s \<rbrakk> \<Longrightarrow>
    obj_at (empty_table (set (x64_global_pdpts (arch_state s)))) pt s"
  apply (clarsimp simp: valid_table_caps_def simp del: split_paired_All)
  apply (erule allE)+
  apply (erule (1) impE)
  apply (fastforce simp add: is_pt_cap_def cap_asid_def)
  done

lemma perform_page_table_invocation_invs[wp]:
  "\<lbrace>invs and valid_pti pti\<rbrace>
     perform_page_table_invocation pti
   \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (cases pti)
   apply (rename_tac cap cslot_ptr pdpte obj_ref)
   apply (rule hoare_pre)
   apply (clarsimp simp: perform_page_table_invocation_def)
   apply (wp hoare_vcg_const_imp_lift hoare_vcg_all_lift  hoare_vcg_conj_lift
             store_pde_invs arch_update_cap_invs_map
           | strengthen obj_at_empty_refs_strg
           | simp add: arch_obj_pred_empty_table del: split_paired_all split_paired_All | wps
           | wp set_cap.aobj_at | wpc)+
     apply (rule set_cap_cte_wp_at_ex[simplified])
    apply (wp)+
    apply (clarsimp simp: valid_pti_def is_arch_update_def cte_wp_at_caps_of_state
                          vs_cap_ref_of_table_capNone
                      simp del:  split_paired_All)
    apply (frule vs_lookup_pages_vs_lookupI)
     apply (rule conjI)
      apply (clarsimp dest!: same_master_cap_same_types simp: vs_cap_ref_of_table_capNone)
     apply (intro conjI allI)
      apply clarsimp
      apply (drule_tac ref = ref in valid_vs_lookupD)
       apply fastforce
      apply (rule ccontr, clarsimp)
      apply (frule_tac cap = x and cap' = capa in unique_table_caps_pdD2[OF _ _ _ _ obj_refs_eqI invs_unique_table_caps])
          apply assumption+
       apply (erule caps_of_state_valid, fastforce)
      apply (erule caps_of_state_valid, fastforce)
     apply (clarsimp simp: is_cap_simps cap_asid_def vs_cap_ref_def split: option.split_asm)
    apply (clarsimp simp: is_cap_simps)
    apply (rule ref_is_unique)
          apply simp
         apply (erule(1) vs_lookup_vs_lookup_pagesI)
          apply fastforce+
         apply (simp add:global_refs_def)
        apply fastforce+
   apply (clarsimp dest!:invs_valid_objs valid_objs_caps)
  apply (rename_tac cap cslot)
  apply (clarsimp simp: perform_page_table_invocation_def)
  apply (rule hoare_name_pre_state)
  apply (clarsimp simp: valid_pti_def is_cap_simps)
  apply (rule hoare_pre)
   apply (wpc | clarsimp simp: cte_wp_at_caps_of_state | wp arch_update_cap_invs_unmap_page_table get_cap_wp)+
    apply (rule_tac P = "is_pt_cap cap" in hoare_gen_asm)
    apply (rule_tac Q = "\<lambda>r. cte_wp_at (op = cap) (a,b) and invs and is_final_cap' cap
                             and (\<lambda>s. (the (vs_cap_ref (ArchObjectCap (PageTableCap p (Some (x1, x2a))))), p) \<notin> vs_lookup_pages s)
                             and obj_at (empty_table {}) (the (aobj_ref (update_map_data (Structures_A.the_arch_cap cap) None)))"
                             in hoare_post_imp)
     apply (clarsimp simp: cte_wp_at_caps_of_state is_cap_simps update_map_data_def
                           is_arch_update_def cap_master_cap_simps)
     apply (clarsimp dest!: caps_of_state_valid_cap[OF _ invs_valid_objs] split: option.split_asm
                      simp: is_arch_diminished_def diminished_def mask_cap_def cap_rights_update_def
                            acap_rights_update_def vs_cap_ref_simps)
    apply (wp hoare_vcg_conj_lift)
        apply (wp mapM_x_wp, force)
       apply (rule mapM_x_swp_store_pte_invs_unmap[unfolded swp_def])
      apply (wp mapM_x_wp)
      apply force
     apply (wp store_invalid_pte_vs_lookup_pages_shrink)
    apply (wp mapM_x_swp_store_empty_pt[unfolded swp_def])
   apply (clarsimp simp: cte_wp_at_caps_of_state vs_cap_ref_def is_arch_diminished_def
                         is_cap_simps diminished_def mask_cap_def)
   apply (clarsimp simp: cap_rights_update_def
                         acap_rights_update_def
                  split: cap.split_asm arch_cap.split_asm)
   apply (wp unmap_pt_vs_lookup_pages unmap_page_table_caps_of_state)
  apply (clarsimp simp: is_final_cap'_def2 obj_irq_refs_def acap_rights_update_def cte_wp_at_caps_of_state
                        is_arch_diminished_def diminished_def mask_cap_def
                  del: )
  apply (clarsimp simp: cap_rights_update_def acap_rights_update_def is_arch_update_def is_cap_simps
                        update_map_data_def vs_cap_ref_simps invs_psp_aligned pt_bits_def
                 split: cap.split_asm arch_cap.split_asm)
  apply (intro conjI impI)
    apply fastforce
   apply (clarsimp simp: valid_cap_def)
   apply (drule valid_table_caps_empty_ptD, force)
   apply (clarsimp simp: obj_at_def empty_table_def)
  apply (strengthen  range_neg_mask_strengthen[mk_strg])
    apply (frule valid_global_refsD2, force)
  apply (clarsimp simp: valid_cap_def wellformed_mapdata_def image_def le_mask_iff_lt_2n cap_range_def
                        invs_arch_objs vtable_range_univ invs_arch_state)
  apply (simp add: mask_def)
  done

lemma valid_kernel_mappingsD:
  "\<lbrakk> kheap s pml4ptr = Some (ArchObj (PageMapL4 pml4));
     valid_kernel_mappings s \<rbrakk>
      \<Longrightarrow> \<forall>x r. pml4e_ref (pml4 x) = Some r \<longrightarrow>
                  (r \<in> set (x64_global_pdpts (arch_state s)))
                       = (ucast (pptr_base >> pml4_shift_bits) \<le> x)"
  apply (simp add: valid_kernel_mappings_def)
  apply (drule bspec, erule ranI)
  unfolding valid_kernel_mappings_if_pm_def valid_kernel_mappings_if_pm_arch_def
  apply (simp add: valid_kernel_mappings_if_pm_def
                   kernel_mapping_slots_def)
  done


lemma set_mi_invs[wp]: "\<lbrace>invs\<rbrace> set_message_info t a \<lbrace>\<lambda>x. invs\<rbrace>"
  by (simp add: set_message_info_def, wp)

lemma reachable_page_table_not_global:
  "\<lbrakk>(ref \<rhd> p) s; valid_kernel_mappings s; valid_global_pdpts s;
    valid_arch_objs s; valid_asid_table (x64_asid_table (arch_state s)) s\<rbrakk>
   \<Longrightarrow> p \<notin> set (x64_global_pdpts (arch_state s))"
  apply clarsimp
  apply (erule (2) vs_lookupE_alt[OF _ _valid_asid_table_ran])
      apply (fastforce simp: valid_global_pdpts_def obj_at_def)+
    apply (clarsimp simp: valid_global_pdpts_def)
    apply (drule (1) bspec)
    apply (clarsimp simp: obj_at_def)
    apply (clarsimp simp: valid_kernel_mappings_def valid_kernel_mappings_if_pm_def ran_def)
    apply (drule_tac x="ArchObj (PageMapL4 pm)" in spec)
    apply (drule mp, erule_tac x=p\<^sub>2 in exI)
    apply clarsimp
   apply (fastforce simp: valid_global_pdpts_def obj_at_def)+
  done

lemma invs_valid_global_pdpts[elim]:
  "invs s \<Longrightarrow> valid_global_pdpts s"
  by (clarsimp simp: invs_def valid_arch_state_def valid_state_def)

lemma valid_table_caps_ptD:
  "\<lbrakk> caps_of_state s p = Some (ArchObjectCap (PageTableCap pt None));
     valid_table_caps s \<rbrakk> \<Longrightarrow>
    obj_at (empty_table (set (x64_global_pdpts (arch_state s)))) pt s"
  apply (clarsimp simp: valid_table_caps_def simp del: split_paired_All)
  apply (erule allE)+
  apply (erule (1) impE)
  apply (fastforce simp add: is_pt_cap_def cap_asid_def)
  done

lemma empty_ref_pageD[elim]:
  "\<lbrakk> data_at X64LargePage page s \<rbrakk> \<Longrightarrow>
    obj_at (\<lambda>ko. vs_refs_pages ko = {}) page s"
  "\<lbrakk> data_at X64HugePage page s \<rbrakk> \<Longrightarrow>
    obj_at (\<lambda>ko. vs_refs_pages ko = {}) page s"
  by (fastforce simp: vs_refs_pages_def data_at_def obj_at_def)+

lemma empty_refs_pageCapD[elim]:
  "s \<turnstile> ArchObjectCap (PageCap dev p Ra tpa sz ma) \<Longrightarrow> obj_at (\<lambda>ko. vs_refs_pages ko = {}) p s"
  by (clarsimp simp: valid_cap_def vs_refs_pages_def obj_at_def split: if_splits)

lemma reachable_pd_not_global:
  "\<lbrakk>(ref \<rhd> p) s; valid_kernel_mappings s; valid_global_pdpts s;
    valid_arch_objs s; valid_asid_table (x64_asid_table (arch_state s)) s\<rbrakk>
   \<Longrightarrow> p \<notin> set (x64_global_pdpts (arch_state s))"
  apply clarsimp
  apply (erule (2) vs_lookupE_alt[OF _ _valid_asid_table_ran])
      apply (fastforce simp: valid_global_pdpts_def obj_at_def)+
    apply (clarsimp simp: valid_global_pdpts_def)
    apply (drule (1) bspec)
    apply (clarsimp simp: obj_at_def)
    apply (clarsimp simp: valid_kernel_mappings_def valid_kernel_mappings_if_pm_def ran_def)
    apply (drule_tac x="ArchObj (PageMapL4 pm)" in spec)
    apply (drule mp, erule_tac x=p\<^sub>2 in exI)
    apply clarsimp
   apply (fastforce simp: valid_global_pdpts_def obj_at_def)+
  done

crunch global_refs: store_pde "\<lambda>s. P (global_refs s)"

crunch invs[wp]: pte_check_if_mapped, pde_check_if_mapped "invs"

crunch vs_lookup[wp]: pte_check_if_mapped, pde_check_if_mapped "\<lambda>s. P (vs_lookup s)"

crunch valid_pte[wp]: pte_check_if_mapped "\<lambda>s. P (valid_pte p s)"

crunch invs[wp]: lookup_pt_slot invs

lemma unmap_page_invs[wp]:
  "\<lbrace>invs and K (asid \<le> mask asid_bits \<and> vaddr < pptr_base \<and> canonical_address vaddr)\<rbrace>
     unmap_page pgsz asid vaddr pptr
   \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: unmap_page_def)
  apply (rule hoare_pre)
   apply (wpc | wp | strengthen imp_consequent)+
   apply ((wp store_pde_invs store_pte_invs unlessE_wp do_machine_op_global_refs_inv get_pde_wp
             hoare_vcg_all_lift find_vspace_for_asid_lots get_pte_wp store_pdpte_invs get_pdpte_wp
        | wpc | simp add: flush_all_def pdpte_ref_pages_def
        | strengthen imp_consequent
                     not_in_global_refs_vs_lookup
                     not_in_global_refs_vs_lookup invs_valid_vs_lookup
                      invs_valid_global_refs
           invs_arch_state invs_valid_global_objs | clarsimp simp: conj_ac)+)[7]
   apply (strengthen imp_consequent
                     not_in_global_refs_vs_lookup
                     not_in_global_refs_vs_lookup invs_valid_vs_lookup
                      invs_valid_global_refs
           invs_arch_state invs_valid_global_objs | clarsimp simp: conj_ac)+
   apply wp
  apply (auto simp: vspace_at_asid_def page_map_l4_at_aligned_pml4_bits[simplified] invs_arch_objs
                    invs_psp_aligned lookup_pml4_slot_eq pml4e_ref_def)
  done

lemma perform_page_invs [wp]:
  "\<lbrace>invs and valid_page_inv page_inv\<rbrace> perform_page_invocation page_inv \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (simp add: perform_page_invocation_def)
  apply (cases page_inv, simp_all)
     -- "PageMap"
     apply (rename_tac cap cslot_ptr sum)
     apply clarsimp
     apply (rule hoare_pre)
      apply (wp  store_pte_invs store_pde_invs store_pdpte_invs
                 hoare_vcg_const_imp_lift hoare_vcg_all_lift set_cap_arch_obj arch_update_cap_invs_map
             | wpc
             | simp add: pte_check_if_mapped_def pde_check_if_mapped_def del: fun_upd_apply split_paired_Ex
            )+
       apply (wp_trace set_cap_cte_wp_at_ex hoare_vcg_imp_lift hoare_vcg_all_lift arch_update_cap_invs_map
                 set_cap.aobj_at[OF arch_obj_pred_empty_refs_pages] | wps)+
     apply (clarsimp simp: valid_page_inv_def cte_wp_at_caps_of_state valid_slots_def is_cap_simps parent_for_refs_def
                           empty_refs_def same_refs_def pt_bits_def is_arch_update_def cap_master_cap_def
                    split: vm_page_entry.splits
                    simp del: split_paired_Ex split_paired_All
              | strengthen not_in_global_refs_vs_lookup invs_valid_global_refs invs_arch_state invs_valid_vs_lookup
                           invs_valid_global_objs)+
       apply (intro conjI impI allI)
         apply (clarsimp simp del: split_paired_Ex split_paired_All)
         apply (frule(2) unique_table_caps_ptD[OF _ _ _ _ _ _ invs_unique_table_caps], simp add: is_cap_simps, fastforce simp: is_cap_simps)
           apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs] is_aligned_pt[OF _ invs_psp_aligned]
                            simp: obj_refs_def valid_cap_def pt_bits_def is_aligned_neg_mask_eq)
          apply simp
         apply clarsimp
        apply (rule ref_is_unique[OF  _ vs_lookup_vs_lookup_pagesI reachable_page_table_not_global])
          apply ((fastforce simp: local.invs_valid_kernel_mappings elim:valid_objs_caps[OF invs_valid_objs])+)[16]
       apply (drule_tac x = ref in spec)
       apply (clarsimp simp: vs_cap_ref_def pde_ref_pages_def split: pde.splits)
       apply (clarsimp simp: valid_pde_def split: pde.splits
                      split: vmpage_size.splits option.split_asm pde.splits)
       apply (intro conjI impI allI)
          apply fastforce
         apply (clarsimp simp del: split_paired_Ex split_paired_All)
         apply (frule(2) unique_table_caps_pdD[OF _ _ _ _ _ _ invs_unique_table_caps], simp add: is_cap_simps, fastforce simp: is_cap_simps)
           apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs] is_aligned_pd[OF _ invs_psp_aligned]
                            simp: obj_refs_def valid_cap_def pt_bits_def is_aligned_neg_mask_eq)
          apply simp
         apply clarsimp
        apply (rule ref_is_unique[OF  _ vs_lookup_vs_lookup_pagesI reachable_page_table_not_global])
          apply ((fastforce simp: local.invs_valid_kernel_mappings elim:valid_objs_caps[OF invs_valid_objs])+)[16]
       apply (frule(1) caps_of_state_valid[OF _ invs_valid_objs])
       apply (drule valid_global_refsD2, fastforce)
      apply (clarsimp dest!: is_aligned_pd[OF _ invs_psp_aligned]
                       simp: is_aligned_neg_mask_eq cap_range_def valid_cap_def)
     apply (clarsimp dest!: empty_refs_pageCapD)
      apply (intro conjI impI allI)
       apply (clarsimp simp del: split_paired_Ex split_paired_All)
       apply (frule(2) unique_table_caps_pdptD[OF _ _ _ _ _ _ invs_unique_table_caps], simp add: is_cap_simps, fastforce simp: is_cap_simps)
         apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs] is_aligned_pdpt[OF _ invs_psp_aligned]
                          simp: obj_refs_def valid_cap_def pdpt_bits_def is_aligned_neg_mask_eq)
        apply simp
       apply clarsimp
      apply (rule ref_is_unique[OF  _ vs_lookup_vs_lookup_pagesI reachable_page_table_not_global])
                    apply ((fastforce simp: local.invs_valid_kernel_mappings elim:valid_objs_caps[OF invs_valid_objs])+)[16]
      apply (frule(1) caps_of_state_valid[OF _ invs_valid_objs, where c = "(ArchObjectCap (PDPointerTableCap pc asid))" for pc asid])
      apply (drule valid_global_refsD2[where cap = "(ArchObjectCap (PDPointerTableCap pc asid))" for pc asid], fastforce)
      apply (clarsimp dest!: is_aligned_pdpt[OF _ invs_psp_aligned]
                       simp: is_aligned_neg_mask_eq cap_range_def valid_cap_def cap_aligned_def)
     -- "PageReMap"
     apply (rename_tac sum)
     apply clarsimp
     apply (rule hoare_pre)
      apply (wp  store_pte_invs store_pde_invs store_pdpte_invs
                 hoare_vcg_const_imp_lift hoare_vcg_all_lift set_cap_arch_obj arch_update_cap_invs_map
             | wpc
             | simp add: pte_check_if_mapped_def pde_check_if_mapped_def del: fun_upd_apply split_paired_Ex
            )+
     apply (clarsimp simp: valid_page_inv_def cte_wp_at_caps_of_state valid_slots_def is_cap_simps parent_for_refs_def
                           empty_refs_def same_refs_def pt_bits_def is_arch_update_def cap_master_cap_def
                    split: vm_page_entry.splits
                    simp del: split_paired_Ex split_paired_All
              | strengthen not_in_global_refs_vs_lookup invs_valid_global_refs invs_arch_state invs_valid_vs_lookup
                           invs_valid_global_objs)+
      apply (intro conjI impI allI)
         apply (rule ccontr)
         apply (clarsimp simp del: split_paired_Ex split_paired_All)
         apply (frule(2) unique_table_caps_ptD[OF _ _ _ _ _ _ invs_unique_table_caps], simp add: is_cap_simps, fastforce simp: is_cap_simps)
           apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs] is_aligned_pt[OF _ invs_psp_aligned]
                            simp: obj_refs_def valid_cap_def pt_bits_def is_aligned_neg_mask_eq)
          apply simp
         apply clarsimp
       apply (drule_tac x = ref in spec)
       apply (drule vs_lookup_vs_lookup_pagesI')
          apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs]
                           simp: valid_cap_simps cap_asid_def pt_bits_def
                          split: option.split_asm)
          apply (frule(1) is_aligned_pt[OF _ invs_psp_aligned])
          apply (clarsimp simp: is_aligned_neg_mask_eq pt_bits_def)
         apply force
        apply force
       apply clarsimp
       apply (drule ref_is_unique[OF  _ _ reachable_page_table_not_global])
                  apply ((fastforce simp: local.invs_valid_kernel_mappings elim:valid_objs_caps[OF invs_valid_objs])+)[13]
     apply (drule_tac x = ref in spec)
     apply (clarsimp simp: vs_cap_ref_simps pde_ref_def split: pde.splits)
     apply (intro conjI impI allI)
        apply fastforce
       apply (rule ccontr)
       apply (clarsimp simp del: split_paired_Ex split_paired_All)
       apply (frule(2) unique_table_caps_pdD[OF _ _ _ _ _ _ invs_unique_table_caps], simp add: is_cap_simps, fastforce simp: is_cap_simps)
         apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs] is_aligned_pd[OF _ invs_psp_aligned]
                          simp: obj_refs_def valid_cap_def pt_bits_def is_aligned_neg_mask_eq)
        apply simp
       apply clarsimp
       apply (drule vs_lookup_vs_lookup_pagesI')
         apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs]
                           simp: valid_cap_simps cap_asid_def pt_bits_def
                          split: option.split_asm)
         apply (frule(1) is_aligned_pd[OF _ invs_psp_aligned])
        apply (clarsimp simp: is_aligned_neg_mask_eq pt_bits_def)
       apply force
      apply force
     apply (drule ref_is_unique[OF  _ _ reachable_page_table_not_global])
                apply ((fastforce simp: local.invs_valid_kernel_mappings elim: valid_objs_caps[OF invs_valid_objs]
                       | strengthen reachable_page_table_not_global[mk_strg])+)[13]
     apply (frule(1) caps_of_state_valid[OF _ invs_valid_objs])
     apply (drule valid_global_refsD2, fastforce)
     apply (clarsimp dest!: is_aligned_pd[OF _ invs_psp_aligned]
                       simp: is_aligned_neg_mask_eq cap_range_def valid_cap_def)
    apply (drule_tac x = ref in spec)
    apply (clarsimp simp: vs_cap_ref_simps pdpte_ref_def pdpte_ref_pages_def split: pdpte.splits)
    apply (intro conjI impI allI)
       apply fastforce
      apply (rule ccontr)
      apply (clarsimp simp del: split_paired_Ex split_paired_All)
      apply (frule(2) unique_table_caps_pdptD[OF _ _ _ _ _ _ invs_unique_table_caps], simp add: is_cap_simps, fastforce simp: is_cap_simps)
        apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs] is_aligned_pdpt[OF _ invs_psp_aligned]
                         simp: obj_refs_def valid_cap_def pdpt_bits_def is_aligned_neg_mask_eq)
       apply simp
      apply clarsimp
     apply (drule vs_lookup_vs_lookup_pagesI')
        apply (clarsimp dest!: caps_of_state_valid[OF _ invs_valid_objs]
                           simp: valid_cap_simps cap_asid_def pdpt_bits_def
                          split: option.split_asm)
        apply (frule(1) is_aligned_pdpt[OF _ invs_psp_aligned])
        apply (clarsimp simp: is_aligned_neg_mask_eq pdpt_bits_def)
       apply force
      apply force
     apply (drule ref_is_unique[OF  _ _ reachable_page_table_not_global])
                apply ((fastforce simp: local.invs_valid_kernel_mappings elim: valid_objs_caps[OF invs_valid_objs]
                       | strengthen reachable_page_table_not_global[mk_strg])+)[13]
     apply (frule(1) caps_of_state_valid[OF _ invs_valid_objs])
     apply (drule valid_global_refsD2, fastforce)
     apply (clarsimp dest!: is_aligned_pdpt[OF _ invs_psp_aligned]
                       simp: is_aligned_neg_mask_eq cap_range_def valid_cap_def)
    -- "PageUnmap"
    apply (rename_tac arch_cap cslot_ptr)
    apply (rule hoare_pre)
     apply (wp dmo_invs arch_update_cap_invs_unmap_page get_cap_wp
               hoare_vcg_const_imp_lift | wpc | simp)+
   apply (clarsimp simp: valid_page_inv_def cte_wp_at_caps_of_state valid_cap_def mask_def)
  apply wp
  -- "PageFlush"
  apply(simp add: valid_page_inv_def tcb_at_invs)
  done


lemma not_kernel_slot_not_global_pml4:
  "\<lbrakk>pml4e_ref (pml4 x) = Some p; x \<notin> kernel_mapping_slots;
    kheap s p' = Some (ArchObj (PageMapL4 pml4)); valid_kernel_mappings s\<rbrakk>
   \<Longrightarrow> p \<notin> set (x64_global_pdpts (arch_state s))"
  apply (clarsimp simp: valid_kernel_mappings_def valid_kernel_mappings_if_pm_def)
   apply (drule_tac x="ArchObj (PageMapL4 pml4)" in bspec)
    apply ((fastforce simp: ran_def)+)[1]
   apply (simp split: arch_kernel_obj.split_asm)
  done

lemma perform_asid_pool_invs [wp]:
  "\<lbrace>invs and valid_apinv api\<rbrace> perform_asid_pool_invocation api \<lbrace>\<lambda>_. invs\<rbrace>"
  apply (clarsimp simp: perform_asid_pool_invocation_def split: asid_pool_invocation.splits)
  apply (wp arch_update_cap_invs_map
            get_cap_wp set_cap_typ_at empty_table_lift
            set_cap_obj_at_other
               |wpc|simp|wp_once hoare_vcg_ex_lift)+
  sorry (* FIXME: check store_pml4e_invs in ArchAcc_AI, more strengthen rules needed ...
  apply (clarsimp simp: valid_apinv_def cte_wp_at_caps_of_state is_arch_update_def is_cap_simps cap_master_cap_simps)
  apply (frule caps_of_state_cteD)
  apply (drule cte_wp_valid_cap, fastforce)
  apply (simp add: valid_cap_def cap_aligned_def)
  apply (clarsimp simp: cap_asid_def split: option.splits)
  apply (rule conjI)
   apply (clarsimp simp: vs_cap_ref_def)
  apply clarsimp
  apply (rule conjI)
   apply (erule vs_lookup_atE)
   apply clarsimp
   apply (drule caps_of_state_cteD)
   apply (clarsimp simp: cte_wp_at_cases obj_at_def)
  apply (rule conjI)
   apply (rule exI)
   apply (rule conjI, assumption)
   apply (rule conjI)
    apply (rule_tac x=a in exI)
    apply (rule_tac x=b in exI)
    apply (clarsimp simp: vs_cap_ref_def mask_asid_low_bits_ucast_ucast)
   apply (clarsimp simp: asid_low_bits_def[symmetric] ucast_ucast_mask
                         word_neq_0_conv[symmetric])
   apply (erule notE, rule asid_low_high_bits, simp_all)[1]
   apply (simp add: asid_high_bits_of_def)
  apply (rule conjI)
   apply (erule(1) valid_table_caps_pdD [OF _ invs_pd_caps])
  apply (rule conjI)
   apply clarsimp
   apply (drule caps_of_state_cteD)
   apply (clarsimp simp: obj_at_def cte_wp_at_cases a_type_def)
   apply (clarsimp split: Structures_A.kernel_object.splits arch_kernel_obj.splits)
  apply (clarsimp simp: obj_at_def)
  done
  *)

(* FIXME: Strange lemma
lemma invs_aligned_pdD:
  "\<lbrakk> pspace_aligned s; valid_arch_state s \<rbrakk> \<Longrightarrow> is_aligned (x64_global_pml4 (arch_state s)) pd_bits"
  apply (clarsimp simp: valid_arch_state_def)
  apply (drule (1) is_aligned_pml4)
  apply (simp add: pml4_bits_def pageBits_def)
  done
*)

end
end
(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory ArchStructures_H
imports
  "../../../lib/Lib"
  "../Types_H"
  Hardware_H
begin

context X64 begin

#INCLUDE_HASKELL SEL4/Object/Structures/X64.lhs CONTEXT X64 decls_only
#INCLUDE_HASKELL SEL4/Object/Structures/X64.lhs CONTEXT X64 instanceproofs
#INCLUDE_HASKELL SEL4/Object/Structures/X64.lhs CONTEXT X64 bodies_only

datatype arch_kernel_object_type =
    PDET
  | PTET
  | PDPTET
  | PML4ET
  | ASIDPoolT
  | IOPTET

primrec
  archTypeOf :: "arch_kernel_object \<Rightarrow> arch_kernel_object_type"
where
  "archTypeOf (KOPDE e) = PDET"
| "archTypeOf (KOPTE e) = PTET"
| "archTypeOf (KOPDPTE e) = PDPTET"
| "archTypeOf (KOPML4E e) = PML4ET"
| "archTypeOf (KOASIDPool e) = ASIDPoolT"
| "archTypeOf (KOIOPTE e) = IOPTET"


end (* context X64 *)

end
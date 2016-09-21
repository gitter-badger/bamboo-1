(* pseudo immediate value *)

type pseudo_imm =
  | Big of Big_int.big_int
  | Int of int
  | CodePos
  | DestLabel of Label.label
  | ContractId of Syntax.contract_id (* an immediate value *)

  | StorageStart
  | StorageSize
  | StorageContractId
  | StorageConstructorArgumentBegin of Syntax.contract_id
  | StorageConstructorArgumentsSize of Syntax.contract_id (* the size is dependent on the contract id *)
  | MemoryStart
  | MemorySize
  | CodeSize
  | Minus of pseudo_imm * pseudo_imm
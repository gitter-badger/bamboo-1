open Syntax


let ident_lookup_type
      (contract_interfaces : Contract.contract_interface Assoc.contract_id_assoc)
      (tenv : TypeEnv.type_env) id : typ exp =
  match TypeEnv.lookup tenv id with
  | Some typ -> (IdentifierExp id, typ)
  | None -> failwith ("unknown identifier "^id)
  (* what should it return when it is a method name? *)


let rec assign_type_call
      contract_interfaces
      cname
      venv (src : unit function_call) : (typ function_call * typ) =
  let args' = List.map (assign_type_exp contract_interfaces cname venv)
                       src.call_args in
  let ret_typ =
    match src.call_head with
    | "value" when true (* check the argument is 'msg' *) -> UintType
    | contract_name
      when true (* check the contract exists*) -> ContractArchType contract_name
    | _ -> failwith "assign_type_call: should not happen"
    in
  ({ call_head = src.call_head
     ; call_args = args' },
   ret_typ)
and assign_type_message_info contract_interfaces cname tenv
                             (orig : unit message_info) : typ message_info =
  let v' = Misc.option_map (assign_type_exp contract_interfaces cname tenv)
                            orig.message_value_info in
  let block' = assign_type_sentences contract_interfaces cname tenv orig.message_reentrance_info in
  { message_value_info = v'
  ; message_reentrance_info = block'
  }
and assign_type_exp
      (contract_interfaces : Contract.contract_interface Assoc.contract_id_assoc)
      (cname : string)
      (venv : TypeEnv.type_env) ((exp_inner, ()) : unit exp) : typ exp =
  match exp_inner with
  | ThisExp -> (ThisExp, ContractInstanceType cname)
  | TrueExp -> (TrueExp, BoolType)
  | FalseExp -> (FalseExp, BoolType)
  | SenderExp -> (SenderExp, AddressType)
  | NowExp -> (NowExp, UintType)
  | FunctionCallExp c ->
     let (c', typ) = assign_type_call contract_interfaces cname venv c in
     (FunctionCallExp c', typ)
  | IdentifierExp s ->
     (* Now something is strange. This might not need a type anyway. *)
     (* Maybe introduce a type called CallableType *)
     ident_lookup_type contract_interfaces venv s
  | ParenthExp e ->
     (* omit the parenthesis at this place, the tree already contains the structure *)
     assign_type_exp contract_interfaces cname venv e
  | NewExp n ->
     let (n', contract_name) = assign_type_new_exp contract_interfaces cname venv n in
     (NewExp n', ContractInstanceType contract_name)
  | LtExp (l, r) ->
     let l' = assign_type_exp contract_interfaces cname venv l in
     let r' = assign_type_exp contract_interfaces cname venv r in
     (LtExp (l', r'), BoolType)
  | GtExp (l, r) ->
     let l' = assign_type_exp contract_interfaces cname venv l in
     let r' = assign_type_exp contract_interfaces cname venv r in
     (GtExp (l', r'), BoolType)
  | NeqExp (l, r) ->
     let l' = assign_type_exp contract_interfaces cname venv l in
     let r' = assign_type_exp contract_interfaces cname venv r in
     (NeqExp (l', r'), BoolType)
  | EqualityExp (l, r) ->
     let l' = assign_type_exp contract_interfaces cname venv l in
     let r' = assign_type_exp contract_interfaces cname venv r in
     (EqualityExp (l', r'), BoolType)
  | NotExp negated ->
     let negated' = assign_type_exp contract_interfaces cname venv negated in
     (NotExp negated', BoolType)
  | AddressExp inner ->
     let inner' = assign_type_exp contract_interfaces cname venv inner in
     (AddressExp inner', AddressType)
  | ArrayAccessExp aa ->
     let atyp = TypeEnv.lookup venv aa.array_access_array in
     begin match atyp with
     | Some (MappingType (key_type, value_type)) ->
        let (idx', idx_typ') = assign_type_exp contract_interfaces cname venv aa.array_access_index in
        (* TODO Check idx_typ' and key_type are somehow compatible *)
        (ArrayAccessExp
           { array_access_array = aa.array_access_array
           ; array_access_index = (idx', idx_typ')
           }, value_type)
     | _ -> failwith "index access haa to be on mappings"
     end
  | SendExp send ->
     let msg_info' = assign_type_message_info contract_interfaces cname venv
                                           send.send_msg_info in
     let contract' = assign_type_exp contract_interfaces cname venv send.send_head_contract in
     let contract_name = Syntax.contract_name_of_instance contract' in
     let method_sig : Ethereum.function_signature = begin
         match Contract.find_method_signature
                 contract_interfaces contract_name send.send_head_method with
         | Some x -> x
         | None -> failwith ("method "^send.send_head_method^" not found")
       end
     in
     let types = Ethereum.(List.map to_typ (method_sig.sig_return)) in
     let reference =
       ( SendExp
           { send_head_contract = contract'
           ; send_head_method = send.send_head_method
           ; send_args = List.map (assign_type_exp contract_interfaces cname venv)
                                  send.send_args
           ; send_msg_info = msg_info'
           },
         ReferenceType types
       ) in
     (match types with
     | [single] -> (SingleDereferenceExp reference, single)
     | _ -> reference)
  | ValueExp ->
     (ValueExp, UintType)
  | SingleDereferenceExp _
  | TupleDereferenceExp _ ->
     failwith "DereferenceExp not supposed to appear in the raw tree for now"
and assign_type_new_exp
      contract_interfaces
      (cname : string)
      (tenv : TypeEnv.type_env)
      (e : unit new_exp) : (typ new_exp * string (* name of the contract just created *)) =
  let msg_info' = assign_type_message_info contract_interfaces
                                           cname tenv e.new_msg_info in
  let args' = List.map (assign_type_exp contract_interfaces cname tenv) e.new_args in
  let e' =
    { new_head = e.new_head
    ; new_args = args'
    ; new_msg_info = msg_info'
    }
  in
  (e',
   e.new_head
  )
and assign_type_lexp
      contract_interfaces
      (cname : string)
      venv (src : unit lexp) : typ lexp =
  (* no need to type the left hand side? *)
  match src with
  | IdentifierLExp s -> IdentifierLExp s
  | ArrayAccessLExp aa ->
     let atyp = TypeEnv.lookup venv aa.array_access_array in
     begin match atyp with
     | Some (MappingType (key_type, value_type)) ->
        let (idx', idx_typ') = assign_type_exp contract_interfaces
                                               cname venv
                                               aa.array_access_index in
        (* TODO Check idx_typ' and key_type are somehow compatible *)
        (ArrayAccessLExp
           { array_access_array = aa.array_access_array
           ; array_access_index = (idx', idx_typ')})
     | _ -> failwith ("unknown array"^aa.array_access_array)
     end
and assign_type_return
      (contract_interfaces : Contract.contract_interface Assoc.contract_id_assoc)
      (cname : string)
      (tenv : TypeEnv.type_env)
      (src : unit return) : typ return =
  { return_exp = assign_type_exp contract_interfaces
                                   cname tenv src.return_exp
  ; return_cont =  assign_type_exp contract_interfaces
                                   cname tenv src.return_cont
  }
and type_variable_init
      contract_interfaces cname tenv (vi : unit variable_init) :
      (typ variable_init * TypeEnv.type_env) =
  (* This function has to enlarge the type environment *)
  let value' = assign_type_exp contract_interfaces
                               cname tenv vi.variable_init_value in
  let added_name = vi.variable_init_name in
  let added_typ = vi.variable_init_type in
  let new_env = TypeEnv.add_pair tenv added_name added_typ in
  let new_init =
    { variable_init_type = added_typ
    ; variable_init_name = added_name
    ; variable_init_value = value'
    } in
  (new_init, new_env)
and assign_type_sentence
      (contract_interfaces : Contract.contract_interface Assoc.contract_id_assoc)
      (cname : string)
      (venv : TypeEnv.type_env)
      (src : unit sentence) :
      (typ sentence * TypeEnv.type_env (* updated environment *)) =
  match src with
  | AbortSentence -> (AbortSentence, venv)
  | ReturnSentence r ->
     let r' =
       assign_type_return contract_interfaces cname venv r in
     (ReturnSentence r', venv)
  | AssignmentSentence (l, r) ->
     let l' = assign_type_lexp contract_interfaces cname venv l in
     let r' = assign_type_exp contract_interfaces cname venv r in
     (AssignmentSentence (l', r'), venv)
  | IfSingleSentence (cond, s) ->
     let cond' = assign_type_exp contract_interfaces cname venv cond in
     let (s', _ (* new variable in the if-body does not affect the context*) )
       = assign_type_sentence
           contract_interfaces cname venv s in
     (IfSingleSentence (cond', s'), venv)
  | SelfdestructSentence e ->
     let e' = assign_type_exp contract_interfaces cname venv e in
     (SelfdestructSentence e', venv)
  | VariableInitSentence vi ->
     let (vi', venv') =  type_variable_init contract_interfaces cname venv vi in
     (VariableInitSentence vi', venv')
and assign_type_sentences
          (contract_interfaces : Contract.contract_interface Assoc.contract_id_assoc)
          (cname : string)
          (type_environment : TypeEnv.type_env)
          (ss : unit sentence list) : typ sentence list =
  match ss with
  | [] -> []
  | first_s :: rest_ss ->
     let (first_s', (updated_environment : TypeEnv.type_env)) =
       assign_type_sentence
         contract_interfaces cname type_environment first_s in
     first_s' :: assign_type_sentences contract_interfaces
                                       cname
                                       updated_environment
                                       rest_ss


let assign_type_case (contract_interfaces : Contract.contract_interface Assoc.contract_id_assoc)
                     (contract_name : string)
                     (venv : TypeEnv.type_env)
                     (case : unit case) =
  let case_arguments = case_header_arg_list case.case_header in
  { case_header = case.case_header
  ; case_body = assign_type_sentences
                  contract_interfaces
                  contract_name
                  (TypeEnv.add_block case_arguments venv)
                  case.case_body
  }


let assign_type_contract (env : Contract.contract_interface Assoc.contract_id_assoc)
      (raw : unit Syntax.contract) :
      Syntax.typ Syntax.contract =
  let tenv = TypeEnv.(add_block raw.contract_arguments empty_type_env) in
  { contract_name = raw.contract_name
  ; contract_arguments = raw.contract_arguments
  ; contract_cases =
      List.map (assign_type_case env raw.contract_name tenv) raw.contract_cases
  }

let assign_types (raw : unit Syntax.contract Assoc.contract_id_assoc) :
      Syntax.typ Syntax.contract Assoc.contract_id_assoc =
  let interfaces = Assoc.assoc_map Contract.contract_interface_of raw in
  Assoc.assoc_map (assign_type_contract interfaces) raw

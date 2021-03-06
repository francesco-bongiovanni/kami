Require Import Kami.Syntax String Lib.Struct Lib.ilist.

Set Implicit Arguments.
Set Asymmetric Patterns.

Inductive RtlExpr: Kind -> Type :=
| RtlReadReg k: string -> RtlExpr k
| RtlReadInput k: (string * list nat) -> RtlExpr k
| RtlReadWire k: (string * list nat) -> RtlExpr k
| RtlConst k: ConstT k -> RtlExpr k
| RtlUniBool: UniBoolOp -> RtlExpr Bool -> RtlExpr Bool
| RtlBinBool: BinBoolOp -> RtlExpr Bool -> RtlExpr Bool -> RtlExpr Bool
| RtlUniBit n1 n2: UniBitOp n1 n2 -> RtlExpr (Bit n1) -> RtlExpr (Bit n2)
| RtlBinBit n1 n2 n3: BinBitOp n1 n2 n3 -> RtlExpr (Bit n1) -> RtlExpr (Bit n2) ->
                      RtlExpr (Bit n3)
| RtlBinBitBool n1 n2: BinBitBoolOp n1 n2 -> RtlExpr (Bit n1) -> RtlExpr (Bit n2) ->
                       RtlExpr Bool
| RtlITE k: RtlExpr Bool -> RtlExpr k -> RtlExpr k -> RtlExpr k
| RtlEq k: RtlExpr (k) -> RtlExpr (k) -> RtlExpr (Bool)
| RtlReadIndex i k: RtlExpr ((Bit i)) -> RtlExpr ((Vector k i)) -> RtlExpr (k)
| RtlReadField n (ls: Vector.t _ n) (i: Fin.t n):
    RtlExpr ((Struct ls)) -> RtlExpr ((Vector.nth (Vector.map (@attrType _) ls) i))
| RtlBuildVector n k: Vec (RtlExpr (n)) k -> RtlExpr ((Vector n k))
| RtlBuildStruct n (attrs: Vector.t _ n):
    ilist (fun a => RtlExpr ((attrType a))) attrs -> RtlExpr ((Struct attrs))
| RtlUpdateVector i k: RtlExpr ((Vector k i)) -> RtlExpr ((Bit i)) -> RtlExpr (k)
                       -> RtlExpr ((Vector k i))
| RtlReadArrayIndex i k: RtlExpr ((Bit (Nat.log2 (2 * i)))) -> RtlExpr ((Array k i)) -> RtlExpr k
| RtlBuildArray n k: Vector.t (RtlExpr n) (S k) -> RtlExpr (Array n k)
| RtlUpdateArray i k: RtlExpr (Array k i) -> RtlExpr (Bit (Nat.log2 (2 * i))) -> RtlExpr k ->
                      RtlExpr (Array k i).

Record RtlModule :=
  { regFiles: list (string * list (string * bool) * string * sigT (fun x => ConstT (Vector (snd x) (fst x))));
    inputs: list (string * list nat * Kind);
    outputs: list (string * list nat * Kind);
    regInits: list (string * sigT (fun x => ConstT x));
    regWrites: list (string * sigT RtlExpr);
    wires: list (string * list nat * sigT RtlExpr) }.

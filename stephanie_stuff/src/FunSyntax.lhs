The abstract and concrete syntax of FUN, a small functional
programming language.


> {-# LANGUAGE FlexibleContexts, FlexibleInstances #-}

> module FunSyntax where

> import qualified ParserCombinators as P
> import Text.PrettyPrint (Doc, (<+>),($$),(<>))
> import qualified Text.PrettyPrint as PP

> import qualified Data.Char as Char

> import Control.Applicative(Alternative(..))
> import Control.Monad

> import Test.QuickCheck hiding (Fun)

The syntax of the language is a little like that of the WHILE programming
language.

> type Variable = String

> data Bop =
>    Plus     -- +  :: Int  -> Int  -> Int
>  | Minus    -- -  :: Int  -> Int  -> Int
>  | Times    -- *  :: Int  -> Int  -> Int
>  | Gt       -- >  :: Int -> Int -> Bool
>  | Ge       -- >= :: Int -> Int -> Bool
>  | Lt       -- <  :: Int -> Int -> Bool
>  | Le       -- <= :: Int -> Int -> Bool
>     deriving (Eq, Show, Enum)

Like Haskell (and OCaml), and unlike WHILE, this language does not
distinguish between expressions and statements: everything is an
expression. For that reason, we add 'If' as a new expression form to
the expressions that we already had in WHILE (variables, constants and
binary operators).

> data Expression =
>  -- stuff shared with WHILE...
>    Var Variable                        -- uppercase strings 'X'
>  | IntExp  Int                         -- natural numbers   '0' ..
>  | BoolExp Bool                        -- 'true' or 'false'
>  | Op  Bop Expression Expression       -- infix binary operators 'e1 + e2'
>  -- new stuff...
>  | If Expression Expression Expression -- if expressions, 'if X then Y else Z'
>  -- interesting new stuff...
>  | Fun Variable Expression             -- anonymous function,   'fun X -> e'
>  | App Expression Expression           -- function application, 'e1 e2'
>  | Let Variable Expression Expression  -- (recursive) binding,  'let F = e in e'
>     deriving (Show, Eq)

The "fun" stuff is in the last three lines. We want to be able to
create (anonymous) first-class functions, apply them to arguments, and
use them in recursive definitions. For example, our good friend the
factorial function might be written in the concrete syntax of FUN as:

      let FACT = fun X ->
                  if X <= 1 then 1 else X * FACT (X - 1)
      in FACT 5

and represented in the abstract syntax as:

> factExp :: Expression
> factExp = Let "FACT" (Fun "X" (If
>                            (Op Le (Var "X") (IntExp 1)) (IntExp 1)
>                              (Op Times (Var "X") (App (Var "FACT") (Op Minus (Var "X") (IntExp 1))))))
>          (App (Var "FACT") (IntExp 5))


FUN Parser
----------

The rest of this file is a parser and pretty printer for the FUN
language. 

> -- parse something then consume all following whitespace
> wsP :: P.Parser a -> P.Parser a
> wsP p = p <* many (P.satisfy Char.isSpace)

> -- a parser that looks for a particular string, then consumes all
> -- whitespace afterwards.
> kwP :: String -> P.Parser String
> kwP s = wsP $ P.string s

> varP :: P.Parser Variable
> varP  = wsP (some (P.satisfy Char.isUpper))

> boolP :: P.Parser Bool
> boolP =  (kwP "true"  *> pure True)
>      <|> (kwP "false" *> pure False)

> -- only natural numbers for simplicity (no negative numbers)
> intP :: P.Parser Int
> intP =  oneNat

> oneNat :: P.Parser Int
> oneNat = read <$> (some (P.satisfy Char.isDigit))
>   -- know that read will succeed because input is all digits

> char :: Char -> P.Parser Char
> char c = P.satisfy (== c)

> parenP :: P.Parser a -> P.Parser a
> parenP p = char '(' *> p <* char ')'


> opP :: P.Parser Bop
> opP =  (kwP "+"  *> pure Plus)
>    <|> (kwP "-"  *> pure Minus)
>    <|> (kwP "*"  *> pure Times)
>    <|> (kwP ">=" *> pure Ge)
>    <|> (kwP "<=" *> pure Le)
>    <|> (kwP ">"  *> pure Gt)
>    <|> (kwP "<"  *> pure Lt)

> varExprP  = Var     <$> wsP varP
> boolExprP = BoolExp <$> wsP boolP
> intExprP  = IntExp  <$> wsP intP

> ifP = If <$>
>     (kwP "if"   *> exprP) <*>
>     (kwP "then" *> exprP) <*>
>     (kwP "else" *> exprP)

> funP = Fun <$>
>     (kwP "fun" *>  varP) <*>
>     (kwP "->"  *>  exprP)

> letrecP = Let <$>
>     (kwP "let" *> varP)  <*>
>     (kwP "="   *> exprP) <*>
>     (kwP "in"  *> exprP)


> -- we use chainl1 for associativity and precedence
> exprP :: P.Parser Expression
> exprP = sumP where
>   sumP    = prodP `P.chainl1` (Op <$> addOp)
>   prodP   = compP `P.chainl1` (Op <$> mulOp)
>   compP   = appP  `P.chainl1` (Op <$> cmpOp)
>   appP    = factorP `P.chainl1` wsP (pure App)
>   factorP = wsP (parenP exprP) <|> baseP
>   baseP   = boolExprP <|> intExprP <|> ifP <|> funP <|> letrecP
>          <|> varExprP

> addOp :: P.Parser Bop
> addOp = kwP "+" *> pure Plus
>     <|> kwP "-" *> pure Minus

> mulOp :: P.Parser Bop
> mulOp = kwP "*" *> pure Times

> cmpOp :: P.Parser Bop
> cmpOp =  kwP "<=" *> pure Le
>      <|> kwP ">=" *> pure Ge
>      <|> kwP "<"  *> pure Lt
>      <|> kwP ">"  *> pure Gt


> parse :: String -> Maybe Expression
> parse s = fst <$> P.doParse exprP s


FUN Printer
------------

> instance PP Bop where
>   pp Plus   =  PP.text "+"
>   pp Minus  =  PP.text "-"
>   pp Times  =  PP.text "*"
>   pp Gt     =  PP.text ">"
>   pp Ge     =  PP.text ">="
>   pp Lt     =  PP.text "<"
>   pp Le     =  PP.text "<="

> class PP a where
>   pp :: a -> Doc

> display :: PP a => a -> String
> display = show . pp

> instance PP Variable where
>  pp s = PP.text s

> instance PP Expression where
>  pp (Var x)  = PP.text x
>  pp (IntExp x)   = PP.text (show x)
>  pp (BoolExp x)  = if x then PP.text "true" else PP.text "false"
>  pp e@(Op _ _ _) = ppPrec 0 e
>  pp (If e s1 s2) =
>    PP.vcat [PP.text "if" <+> pp e <+> PP.text "then",
>         PP.nest 2 (pp s1),
>         PP.text "else",
>         PP.nest 2 (pp s2) ]
>  pp e@(App _ _) = ppPrec 0 e
>  pp (Fun x e)   =
>   PP.hang (PP.text "fun" <+> pp x <+> PP.text "->") 2 (pp e)
>  pp (Let x e1 e2) =
>   PP.vcat [PP.text "let" <+> pp x <+> PP.text "=",
>         PP.nest 2 (pp e1),
>         PP.text "in",
>         PP.nest 2 (pp e2) ]

> ppPrec n (Op bop e1 e2) =
>     parens (level bop < n) $
>           ppPrec (level bop) e1 <+> pp bop <+> ppPrec (level bop + 1) e2
> ppPrec n (App e1 e2) =
>     parens (levelApp < n) $
>           ppPrec levelApp e1 <+> ppPrec (levelApp + 1) e2
> ppPrec n e@(Fun _ _) =
>     parens (levelFun < n) $ pp e
> ppPrec n e@(If _ _ _) =
>     parens (levelIf < n) $ pp e
> ppPrec n e@(Let _ _ _) =
>     parens (levelLet < n) $ pp e
> ppPrec _ e' = pp e'
> parens b = if b then PP.parens else id

> -- emulate the C++ precendence-level table
> level :: Bop -> Int
> level Plus   = 3
> level Minus  = 3
> level Times  = 5
> level _      = 8

> levelApp     = 10
> levelIf      = 2
> levelLet     = 1
> levelFun     = 1  -- (= almost always needs parens)



Roundtrip Property
------------------


> indented :: PP a => a -> String
> indented = PP.render . pp

> prop_roundtrip :: Expression -> Bool
> prop_roundtrip s = parse (indented s) == Just s


> quickCheckN :: Test.QuickCheck.Testable prop => Int -> prop -> IO ()
> quickCheckN n = quickCheckWith $ stdArgs { maxSuccess = n , maxSize = 100 }


> instance Arbitrary Expression where
>   arbitrary = sized genExp

>   shrink (Op o e1 e2)  = [Op o e1' e2' | e1' <- shrink e1, e2' <- shrink e2 ]
>   shrink (If e1 e2 e3) = [If e1' e2' e3' | e1' <- shrink e1, e2' <- shrink e2, e3' <- shrink e3 ]
>   shrink (Fun v e1)    = [Fun v e1' | e1' <- shrink e1]
>   shrink (App e1 e2)   = [App e1' e2' | e1' <- shrink e1, e2' <- shrink e2 ]
>   shrink (Let v e1 e2) = [Let v e1' e2' | e1' <- shrink e1, e2' <- shrink e2 ]
>   shrink _             = [ ]

> genExp :: Int -> Gen Expression
> genExp 0 = oneof     [ liftM Var arbVar
>                      , liftM IntExp arbNat
>                      , liftM BoolExp arbitrary
>                      ]
> genExp n = frequency [ (1, liftM Var arbVar)
>                      , (1, liftM IntExp arbNat)
>                      , (1, liftM BoolExp arbitrary)
>                      , (7, liftM3 Op arbitrary (genExp n') (genExp n'))
>                      , (7, liftM3 If (genExp n') (genExp n') (genExp n'))
>                      , (7, liftM2 Fun arbVar (genExp n'))
>                      , (7, liftM2 App (genExp n') (genExp n'))
>                      , (7, liftM3 Let arbVar (genExp n') (genExp n'))
>                      ]
>  where n' = n `div` 2
> instance Arbitrary Bop where
>   arbitrary = elements [ Plus .. ]

> arbNat :: Gen Int
> arbNat = liftM abs arbitrary

> arbVar :: Gen Variable
> arbVar = elements $ map pure ['A'..'Z']

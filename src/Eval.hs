{-# LANGUAGE RecursiveDo #-}

module Eval where

--import Parser

import Control.Monad.Except
import Control.Monad.Fix
import Data.Map as Map
import Test.HUnit
import Types

type Environment = Map Variable Value

type StepResult = Either String (Either (Environment, Expression) Value)

data Value
  = IntVal Int
  | BoolVal Bool
  | -- note! function values can go wrong when they are run
    FunVal (Value -> StepResult)
  | UserDT DataConstructor [Value]

instance Eq Value where
  IntVal i == IntVal j = i == j
  BoolVal i == BoolVal j = i == j
  UserDT dt l == UserDT dt' l' =
    getDCName dt == getDCName dt'
      && length l == length l'
      && Prelude.foldr (\(v1, v2) acc -> v1 == v2 && acc) True (zip l l')
  _ == _ = False

instance Show Value where
  show (IntVal i) = show i
  show (BoolVal b) = show b
  show (UserDT dt l) = getDCName dt ++ " " ++ Prelude.foldr (\x acc -> show x ++ acc) [] l
  show (FunVal _) = "<function>" -- can't show functions

vLookup :: Variable -> Map Variable Value -> StepResult
vLookup x env =
  case Map.lookup x env of
    Just ty -> return $ return ty
    Nothing -> throwError $ "Unbound variable " ++ x

retVal :: Value -> StepResult
retVal = return . return

retStep :: Expression -> Environment -> StepResult
retStep e env = return $ Left (env, e)

isErr :: Either a b -> Bool
isErr (Left _) = True
isErr (Right _) = False

evalB :: Bop -> Value -> Value -> Environment -> StepResult
evalB Plus (IntVal i1) (IntVal i2) = retStep $ IntExp (i1 + i2)
evalB Minus (IntVal i1) (IntVal i2) = retStep $ IntExp (i1 - i2)
evalB Times (IntVal i1) (IntVal i2) = retStep $ IntExp (i1 * i2)
evalB Gt (IntVal i1) (IntVal i2) = retStep $ BoolExp (i1 > i2)
evalB Ge (IntVal i1) (IntVal i2) = retStep $ BoolExp (i1 >= i2)
evalB Lt (IntVal i1) (IntVal i2) = retStep $ BoolExp (i1 < i2)
evalB Le (IntVal i1) (IntVal i2) = retStep $ BoolExp (i1 <= i2)
evalB _ _ _ = const . throwError $ "Invalid argument to binary operator"

-- isValue :: Expression -> Bool
-- isValue (IntExp _) = True
-- isValue (BoolExp _) = True
-- isValue (Lam _ _) = True
-- isValue (TyCstr _ _) = True
-- isValue (App )

--

evalBounded :: Expression -> Environment -> StepResult
evalBounded (Var x) s = vLookup x s
evalBounded (IntExp i) _ = retVal $ IntVal i
evalBounded (BoolExp i) _ = retVal $ BoolVal i
evalBounded (Op o e1 e2) s = do
  t1 <- evalBounded e1 s
  t2 <- evalBounded e2 s
  case (t1, t2) of
    (Left (s', e1'), _) -> retStep (Op o e1' e2) s' -- step evaluator
    (Right _, Left (s', e2')) -> retStep (Op o e1 e2') s'
    (Right v1, Right v2) -> evalB o v1 v2 s
evalBounded (Lam x e) s = retVal $ FunVal (\v -> return $ Left (Map.insert x v s, e))
evalBounded (App lam []) s = return $ Left (s, lam)
-- //TODO: User Defined Datatypes
evalBounded (App lam (x : xs)) s = do
  t1 <- evalBounded lam s
  t2 <- evalBounded x s
  case (t1, t2) of
    (_, Left (s', x')) -> retStep (App lam (x' : xs)) s'
    (Right (UserDT d l), Right v) -> retVal $ UserDT d (l ++ [v])
    (Right (FunVal g), Right v) -> case g v of
      Left _ -> g v -- threw an error
      Right (Left (s', lam')) -> return $ Left (s', App lam' xs) -- apply function one round
      _ -> throwError "app requires a function/data constructor"
    _ -> throwError "app requires a function/data constructor"
-- //TODO Yikes, doesn't allow for recursive functions
evalBounded (Let x e1 e2) s = mdo
  t <- evalBounded e1 s
  case t of
    Left (s'', e1') -> return $ Left (s'', Let x e1' e2)
    Right v -> do
      let s' = Map.insert x v s
      return $ Left (s', e2)
evalBounded (Annot e _) s = retStep e s
evalBounded (C dt) _ = retVal $ UserDT dt []
-- case
evalBounded (Case e1 ps) s = do
  t1 <- evalBounded e1 s
  case t1 of
    Left (s', e1') -> retStep (Case e1' ps) s'
    Right v -> findCase v ps s

-- // TODO Handle user defined data types in casing
patternMatch :: Value -> Pattern -> Environment -> (Bool, Environment)
patternMatch (IntVal i) (IntP p) s = (i == p, s)
patternMatch (BoolVal b) (BoolP p) s = (b == p, s)
patternMatch v (VarP x) s = (True, Map.insert x v s)
patternMatch (UserDT dt l) (P dt' ps) s =
  if getDCName dt == getDCName dt' && length l == length ps
    then
      Prelude.foldr
        ( \(v, p) acc ->
            let res = patternMatch v p (snd acc)
             in (fst res && fst acc, snd res)
        )
        (True, s)
        (zip l ps)
    else (False, s)
patternMatch _ _ s = (False, s)

checkCase :: Value -> (Pattern, Expression) -> Environment -> StepResult
checkCase v (p, e) s =
  let (res, s') = patternMatch v p s
   in if res
        then retStep e s'
        else throwError "case match invalid"

findCase :: Value -> [(Pattern, Expression)] -> Environment -> StepResult
findCase v l s = Prelude.foldr f (throwError "no matching cases") l
  where
    f :: (Pattern, Expression) -> StepResult -> StepResult
    f c acc =
      let res = checkCase v c s
       in if isErr res then acc else res

-- //TODO add user defined constructors

eval :: Expression -> Environment -> Either String Value
eval e s = do
  step <- evalBounded e s
  case step of
    Left (s', e') -> eval e' s'
    Right v -> return v

-- -- repl

-- test cases:

-- replE :: IO ()
-- replE = do
--   putStr "%> "
--   line <- getLine
--   case Parser.parse line of
--     Just exp ->
--       case eval exp Map.empty of
--         Left str -> putStrLn str >> replE
--         Right val -> putStrLn (show val) >> replE
--     Nothing -> putStrLn "what?!?" >> replE

-- -- TEST CASES
isFailing :: Either a b -> Test
isFailing (Left _) = TestCase $ assert True
isFailing (Right _) = TestCase $ assert False

tests =
  TestList
    [ "1 + true" ~: isFailing $ eval (Op Plus (IntExp 1) (BoolExp True)) Map.empty,
      "1 1" ~: isFailing $ eval (App (IntExp 1) [IntExp 1]) Map.empty,
      "if 1 .." ~: isFailing $ eval (Case (IntExp 1) [(BoolP False, IntExp 3)]) Map.empty,
      "X" ~: isFailing $ eval (Var "X") Map.empty
    ]

fun1 = Lam "y" (Op Plus (Var "y") (IntExp 1))

fun2 = Lam "y" (Lam "z" (Op Minus (Var "y") (Var "z")))

testLet =
  TestList
    [ "let x = 5 in x" ~: eval (Let "x" (IntExp 5) (Var "x")) Map.empty ~?= Right (IntVal 5),
      "let x = 5 in x + 1"
        ~: eval (Let "x" (IntExp 5) (Op Plus (Var "x") (IntExp 1))) Map.empty ~?= Right (IntVal 6),
      "let x = y -> y + 1 in x 3"
        ~: eval (Let "x" fun1 (App (Var "x") [IntExp 3])) Map.empty ~?= Right (IntVal 4),
      "let x = y -> y + 1 in x 3 4"
        ~: isFailing
        $ eval (Let "x" fun1 (App (Var "x") [BoolExp True, IntExp 4])) Map.empty,
      "let x = y z -> y - z in x 3 4"
        ~: eval (Let "x" fun2 (App (Var "x") [IntExp 3, IntExp 4])) Map.empty ~?= Right (IntVal (-1)),
      "let x = y z -> y - z in x True 5"
        ~: isFailing
        $ eval (Let "x" fun2 (App (Var "x") [BoolExp True, IntExp 5])) Map.empty
    ]

case1 = Case (Var "x") [(IntP 3, IntExp 3), (BoolP True, IntExp 5), (VarP "y", Var "y")]

case2 = Case (Var "x") [(IntP 3, IntExp 3), (BoolP True, IntExp 5)]

testCasingSimple =
  TestList
    [ "case x of [3 -> 4, True -> 5, 'y' -> 'y'] where x = 3"
        ~: eval case1 (Map.insert "x" (IntVal 3) Map.empty) ~?= Right (IntVal 3),
      "case x of [3 -> 4, True -> 5, 'y' -> 'y'] where x = 6"
        ~: eval case1 (Map.insert "x" (IntVal 6) Map.empty) ~?= Right (IntVal 6),
      "case x of [3 -> 4, True -> 5, 'y' -> 'y'] where x = True"
        ~: eval case1 (Map.insert "x" (BoolVal True) Map.empty) ~?= Right (IntVal 5),
      "case x of [3 -> 4, True -> 5] where x = 6"
        ~: isFailing
        $ eval case2 (Map.insert "x" (IntVal 6) Map.empty)
    ]

testUserDefined =
  TestList
    [ "let x = P 3 4 in x"
        ~: eval (Let "x" (C (DC "P" IntTy)) (Var "x")) Map.empty ~?= Right (UserDT (DC "P" IntTy) [])
    ]

-- -- quickcheck property
-- -- Can be evaluated property
-- prop_stepExec :: Expression -> Property
-- prop_stepExec e =
--   isValid e ==> not (isError e1)
--   where
--     x = evalBounded e Map.empty

--     -- is terminating error
--     isError :: Either (Environment, Expression) (Either String Value) -> Bool
--     isError (Right (Left _)) = True
--     isError _ = False

-- quickCheckN :: Test.QuickCheck.Testable prop => Int -> prop -> IO ()
-- quickCheckN n = quickCheckWith $ stdArgs {maxSuccess = n, maxSize = 100}
data List a = Nil | Cons a (List a)
data Maybe a = Nothing | Just a

id :: forall a . a -> a
id = \x -> x ;

ids :: List (forall a . a -> a)
ids = Cons id Nil ;

Cons id ids
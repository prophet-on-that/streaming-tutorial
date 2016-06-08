# Pipelines with FreeT #

The repository and document contain a derivation of
[pipes](http://hackage.haskell.org/package/pipes)-like streaming
abstractions based on *FreeT*, the free monad transformer. The work
presented here is not new, but simply documents my efforts to
understand free monads and their relation to streaming. A host of
excellent resources on these topics are presented [below](#resources).

## Recap: the free monad of a functor ##

Let `f` be a type constructor. The free monad of `f` is defined as follows:

```haskell
data Free f a
  = Pure a
  | Free (f (Free f a))
```

The key thing to know is this: **given a Functor `f`, `Free f` is a
monad**. Here's how: 

```haskell
instance Functor f => Functor (Free f) where
  fmap g (Pure a)
    = Pure (g a)
  fmap g (Free m)
    = Free $ fmap (fmap g) m

instance Functor f => Applicative (Free f) where
  pure
    = Pure
  Pure a <*> h
    = fmap a h
  Free m <*> h
    = Free $ fmap (<*> h) m

instance Functor f => Monad (Free f) where
  Pure a >>= h
    = h a
  Free m >>= h
    = Free $ fmap (>>= h) m
```

Intuitively, something of type `Free f a` is built by nested
applications of `f` to the seed `Pure a`. Information is provided
both by the value of the seed and structure of the functor, which may
hold data (e.g. `(,) b`) or provide paths of execution
(e.g. `Maybe`). The definition of `Free` closely resembles that of a
*List*, and indeed the list type can be recovered as follows: 

```haskell
data List b = Free ((,) b) ()
```

The Functor, Applicative and Monad instances for `Free f` recurse
through each `Free` constructor with `fmap` until reaching the `Pure`
value, which is then modified accordingly. In the Monad instance, the
pure value is replaced by the new `Free f b` term, effectively
appending them.

## Recap: the free monad transformer ##



## Resources ##

Blah

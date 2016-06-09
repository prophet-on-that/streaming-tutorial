# Unidirectional Pipelines with FreeT #

The repository and document contain a derivation of
[pipes](https://hackage.haskell.org/package/pipes)-like streaming
abstractions based on *FreeT*, the free monad transformer. The work
presented here is not new, but simply documents my efforts to
understand free monads and their relation to streaming. A host of
excellent resources on these topics are presented [below](#resources).

## Recap: the free monad of a functor ##

*Please note: the canonical implementation of `Free` and `FreeT` can
 be found in the [free](https://hackage.haskell.org/package/free) package.*

Let `f` be a type constructor. The free monad of `f` is defined as follows:

```haskell
data Free f a
  = Pure a
  | Free (f (Free f a))
```

The key thing to know is this: **given a Functor `f`, `Free f` is a
monad**.

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

`FreeT` is the transformer-equivalent of `Free`, and is what we will
use to construct our streaming primitives (with effects). 

```haskell
data FreeF f a b 
  = Pure a
  | Free (f b)
  
newtype FreeT f m a = FreeT
  { runFreeT :: m (FreeF f a (FreeT f m a))
  }
```

Here, **if `f` is a Functor and `m` a Monad, `FreeT f m` is a
Monad**. This instance, and that of Functor and Applicative, are very
similar to before, although additionally interleave the monadic action.

```haskell
instance (Functor f, Functor m) => Functor (FreeT f m) where
  fmap f (FreeT m)
    = FreeT $ fmap go m
    where
      go (Pure a)
        = Pure (f a)
      go (Free cont)
        = Free $ fmap (fmap f) cont

instance (Functor f, Monad m) => Applicative (FreeT f m) where
  pure
    = FreeT . return . Pure
  FreeT m <*> h
    = FreeT $ m >>= go 
    where
      go (Pure a)
        = runFreeT $ fmap a h
      go (Free cont)
        = return . Free $ fmap (<*> h) cont

instance (Functor f, Monad m) => Monad (FreeT f m) where
  return 
    = pure
  FreeT m >>= h
    = FreeT $ m >>= go
    where
      go (Pure a)
        = runFreeT $ h a
      go (Free cont)
        = return . Free $ fmap (>>= h) cont
```

`FreeT f` is also a monad transformer.

```haskell
instance MonadTrans (FreeT f) where
  lift
    = FreeT . fmap Pure
```

There are also several other handy lift functions we can define:

```haskell
wrap
  :: Monad m
  => f (FreeT f m a)
  -> FreeT f m a
wrap
  = FreeT . return . Free

liftF
  :: (Functor f, Monad m)
  => f a
  -> FreeT f m a
liftF
  = wrap . fmap return
```

## A Consumer Type ##

A *Consumer* streaming component is one which consumes a stream of
values, usually interleaving some effect between consumption. Consider

```haskell 
type Consumer a m b = FreeT ((->) a) m b
```

Here, our functor is `(->) a`, indicating a request for a value of
type `a`. Imagine a value of type `Consumer a m b`. The seed is `Pure
b`, the return value when the consumer terminates. Each additional
layer is a request for data wrapped in an `m`-action. Therefore, a
`Consumer a m b` can consume a (potentially infinite) stream of data
of type `a` before terminating with a `b`.

Let's define a function `consume` for use with a consumer.

```haskell
consume
  :: Monad m
  => Consumer a m a
consume
  = liftF id
```

With this, we can now define arbitrary effectful consumers. Here's one
which consumes strings, printing each to the console. Note that we've
imported the Prelude's `putStrLn` qualified with `P`.

```haskell
putStrLn :: Consumer String IO ()
putStrLn
  = forever $
      consume >>= lift . P.putStrLn
```

## A Producer Type ##

A *Producer* streaming component is one which yields values
downstream. It's the opposite of a consumer, and this is reflected in
the choice of functor for `FreeT`, `(,) a`. Note that this is the
exact correspondence between `Reader` and `Writer`. 

```haskell
type Producer a m b = FreeT ((,) a) m b
```

A `Producer a m b` yields a stream of values of type `a` downstream,
interleaved with `m`-actions, and produces a value of type `b` on
termination. Let's define a function `produce` to yield a value downstream.

```haskell
produce
  :: (Monad m, Monoid a)
  => a
  -> Producer a m ()
produce a
  = liftF (a, ())
```

We can define a producer which yields input from stdin downstream
indefinitely.

```haskell
getLine
  :: Producer String IO ()
getLine
  = forever $
      lift P.getLine >>= produce
```

## Joining Producers to Consumers ##

Joining a `Producer` to a `Consumer` will result in a closed system,
which should be executable in the base monad, `m`. The system is
driven by the downstream component, meaning control will be
transferred to the upstream component only after a `consume` call, and
will be handed back on a `produce`. We give the join function as an
operator, `(*|*)`.

```haskell
(*|*)
  :: Monad m
  => Producer a m b
  -> Consumer a m b
  -> m b
(*|*) prod con = do
  con' <- runFreeT con
  case con' of
    Pure b ->
      pure b
    Free f -> do
      prod' <- runFreeT prod
      case prod' of
        Pure b ->
          pure b
        Free (input, prod') ->
          prod' *|* f input

infix 5 *|*
```

## A Pipe Type ##

A pipe streaming component is a stream transformation, mapping an
input `i` to an output `o`. This time, our functor, `Step i o`, is the
sum of our consumer functor (`(->) i`) and our producer functor (`(,)
o`), encoding both await and yield functionality.

```haskell
data Step i o u
  = Await (i -> u)
  | Yield (o, u)

instance Functor (Step i o) where
  fmap f (Await g)
    = Await $ f . g
  fmap f (Yield (o, u))
    = Yield (o, f u)
    
type Pipe i o m u = FreeT (Step i o) m u
```

We define two functions, `await` and `yield`, the `Pipe` counterparts
to `consume` and `produce`.

```haskell
await
  :: Monad m
  => Pipe i o m i
await
  = liftF $ Await id

yield
  :: Monad m
  => o
  -> Pipe i o m ()
yield o
  = liftF $ Yield (o, ())
```

We should be able to compose a pipe with a producer to yield another
producer, if the output of the producer matches the input of the
pipe. We achieve this with the `(*|=)` operator. As with `(*|*)`, the
pipeline is driven by the downstream component.

```haskell
(*|=)
  :: (Monad m, Monoid b)
  => Producer a m u
  -> Pipe a b m u
  -> Producer b m u
prod *|= pipe = do
  pipe' <- lift $ runFreeT pipe
  case pipe' of
    Pure u ->
      pure u
    Free (Await f) -> do
      prod' <- lift $ runFreeT prod
      case prod' of
        Pure u ->
          pure u
        Free (input, prod') ->
          prod' *|= f input
    Free (Yield (b, cont)) -> do 
      produce b
      prod *|= cont

infixl 6 *|=
```

Similarly, we define an operator `(=|*)` to compose a pipe with a
consumer, yielding a consumer. 

```haskell
(=|*)
  :: (Monad m, Monoid b)
  => Pipe a b m u 
  -> Consumer b m u 
  -> Consumer a m u
pipe =|* con = do
  con' <- lift $ runFreeT con
  case con' of
    Pure u ->
      pure u
    Free f -> do
      pipe' <- lift $ runFreeT pipe
      case pipe' of
        Pure u ->
          pure u
        Free (Await cont) -> do
          input <- consume 
          cont input =|* wrap f
        Free (Yield (input, cont)) ->
          cont =|* f input

infixr 6 =|*
```

Finally, we can compose two pipes with `(=|=)` to yield another pipe.

```haskell
(=|=)
  :: Monad m
  => Pipe a b m u
  -> Pipe b c m u
  -> Pipe a c m u
up =|= down = do
  down' <- lift $ runFreeT down
  case down' of
    Pure u ->
      pure u
    Free (Await f) -> do
      up' <- lift $ runFreeT up
      case up' of
        Pure u ->
          pure u
        Free (Await cont) -> do
          input <- await
          cont input =|= (wrap . Await) f
        Free (Yield (output, cont)) ->
          cont =|= f output
    Free (Yield (b, cont)) -> do
      yield b
      up =|= cont

infix 7 =|=
```

These operators have several properties, which are not proven here:
1. `(=|=)` is associative;
2. `r *|= s =|= t` is equivalent to `r *|= s *|= t`;
3. `r =|= s =|* t` is equivalent to `r =|* s =|* t`;
4. `r *|* s =|* t` is equivalent to `r *|= s *|* t`.

## Comparison with Pipes ##

The [pipes](http://hackage.haskell.org/package/pipes) library
incorporates our `Producer`, `Consumer` and `Pipe` type into a single
type `Proxy`, encoding `FreeT` directly and also supporting upstream
data flow. The primary benefit of this formulation is the conciseness
of the API: our `(*|*)`, `(*|=)`, `(=|*)` and `(=|=)` operators
collapse into a single operator, `(>->)`, and the laws given above are
expressed entirely by the associativity of `(>->)`. Additionally, this
is before we consider equivalents of `for` and `(>~)`. Of course, we
could completely recover the (unidirectional) *Pipes* approach by
defining `Producer` and `Consumer` in terms of `Pipe`, and using
universal quantification in the type signatures of `await` and `yield`
to prevent producers requesting information and consumers creating it.

## Resources ##

Blah

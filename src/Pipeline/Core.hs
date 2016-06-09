{-# LANGUAGE ViewPatterns #-}

module Pipeline.Core
  ( -- * Consumer
    Consumer
  , consume
    -- * Producer
  , Producer
  , produce
    -- * Pipe
  , Pipe
  , await
  , yield
    -- * Composition Operators
  , (*|*)
  , (*|=)
  , (=|*)
  , (=|=)
  ) where

import Control.Monad.Trans.Free
import Control.Monad.Trans.Class
 
type Consumer a m b = FreeT ((->) a) m b

consume
  :: Monad m
  => Consumer a m a
consume
  = liftF id

type Producer a m b = FreeT ((,) a) m b

produce
  :: (Monad m, Monoid a)
  => a
  -> Producer a m ()
produce a
  = liftF (a, ())

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

data Step i o u
  = Await (i -> u)
  | Yield (o, u)

instance Functor (Step i o) where
  fmap f (Await g)
    = Await $ f . g
  fmap f (Yield (o, u))
    = Yield (o, f u)

type Pipe i o m u = FreeT (Step i o) m u

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


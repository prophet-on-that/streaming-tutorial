{-# LANGUAGE ViewPatterns #-}

module Pipeline.Core
  ( -- * Consumer
    Consumer
  , consume
  , stdoutLn
    -- * Producer
  , Producer
  , produce
  , stdinLn
    -- * Pipe
  , Pipe
  , await
  , yield
  , dup
    -- * Composition Operators
  , (*|*)
  , (*|=)
  , (=|*)
  , (=|=)
  ) where

import Control.Monad.Trans.Free
import Control.Monad.Reader
import Control.Monad.Writer

type Consumer a m b = FreeT (Reader a) m b

consume
  :: Monad m
  => Consumer a m a
consume
  = liftF ask

stdoutLn :: Consumer String IO ()
stdoutLn
  = forever $
      consume >>= lift . putStrLn

type Producer a m b = FreeT (Writer a) m b

produce
  :: (Monad m, Monoid a)
  => a
  -> Producer a m ()
produce
  = liftF . tell

stdinLn
  :: Producer String IO ()
stdinLn
  = forever $
      lift getLine >>= produce
  
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
        Free (runWriter -> (prod', input)) ->
          prod' *|* runReader f input

infix 5 *|*

data Step i o u
  = Await (i -> u)
  | Yield (u, o)

instance Functor (Step i o) where
  fmap f (Await g)
    = Await $ f . g
  fmap f (Yield (u, o))
    = Yield (f u, o)

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
  = liftF $ Yield ((), o)

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
        Free (Yield (cont, output)) ->
          cont =|= f output
    Free (Yield (cont, b)) -> do
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
        Free (runWriter -> (prod', input)) ->
          prod' *|= f input
    Free (Yield (cont, b)) -> do 
      produce b
      prod *|= cont

infixl 6 *|=

dup
  :: Monad m
  => Pipe a a m u
dup
  = forever $ do 
      a <- await
      yield a
      yield a

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
        Free (Yield (cont, input)) ->
          cont =|* runReader f input

infixr 6 =|*


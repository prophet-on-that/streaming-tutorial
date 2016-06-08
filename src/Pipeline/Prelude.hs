-- | This module is designed to be imported qualified.

module Pipeline.Prelude
  ( -- * Consumers
    putStrLn
    -- * Producers
  , getLine
    -- * Pipes
  , take
  ) where

import Pipeline.Core

import Prelude hiding (putStrLn, getLine, take)
import qualified Prelude as P
import Control.Monad
import Control.Monad.Trans.Class

putStrLn :: Consumer String IO ()
putStrLn
  = forever $
      consume >>= lift . P.putStrLn

getLine
  :: Producer String IO ()
getLine
  = forever $
      lift P.getLine >>= produce
  
take
  :: Monad m
  => Int
  -> Pipe a a m ()
take n 
  = replicateM_ n $ await >>= yield


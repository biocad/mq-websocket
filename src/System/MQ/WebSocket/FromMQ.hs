{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module System.MQ.WebSocket.FromMQ
  (
    listenMonique
  ) where

import           Control.Concurrent.STM.TVar          (readTVarIO)
import           Control.Monad.Except                 (liftIO)
import qualified Data.ByteString                      as BS (ByteString)
import qualified Data.ByteString.Char8                as BSC8 (unpack)
import           Data.Map.Strict                      ((!?))
import           Data.Maybe                           (fromMaybe)
import           Data.MessagePack                     (pack)
import           Network.WebSockets                   (ClientApp)
import qualified Network.WebSockets                   as WS (Connection,
                                                             sendTextData)
import           System.MQ.Component                  (TwoChannels (..),
                                                       load2Channels)
import           System.MQ.Monad                      (foreverSafe, runMQMonad)
import           System.MQ.Protocol                   (MessageTag, messageSpec)
import           System.MQ.Transport.ByteString       (sub)
import           System.MQ.WebSocket.Atomic.Functions (sharedSpecs)
import           System.MQ.WebSocket.Atomic.Types     (Spec, Specs,
                                                       WSConnection (..),
                                                       WSMessage (..))

-- | Listen to Monique and translate all messages from queue to WebSocket connections
-- that are subscribed to these kind of messages.
listenMonique :: IO ()
listenMonique = runMQMonad $ do
    TwoChannels{..} <- load2Channels

    foreverSafe "mq-websocket" $ do
        tm@(tag, _) <- sub fromScheduler
        let spec = BSC8.unpack $ messageSpec tag

        specs       <- liftIO $ readTVarIO sharedSpecs
        connections <- pure $ (++) (getConnections specs spec) (getConnections specs "*")

        liftIO $ mapM_ (sendMsg tm) connections

  where
    getConnections :: Specs -> Spec -> [WS.Connection]
    getConnections specs = fmap (wsConnection . snd) . fromMaybe [] . (specs !?)

    sendMsg :: (MessageTag, BS.ByteString) -> ClientApp ()
    sendMsg (tag, msg) = flip WS.sendTextData (pack $ WSMessage tag msg)

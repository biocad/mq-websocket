{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module System.MQ.WebSocket.FromMQ
  (
    listenMonique
  ) where

import           Control.Concurrent.STM.TVar    (readTVarIO)
import           Control.Monad.Except           (liftIO)
import qualified Data.ByteString                as BS (ByteString)
import           Data.Map.Strict                ((!?))
import           Data.Maybe                     (fromMaybe)
import           Network.WebSockets             (ClientApp)
import qualified Network.WebSockets             as WS (Connection, sendTextData)
import           System.MQ.Component            (TwoChannels (..),
                                                 load2Channels)
import           System.MQ.Encoding.MessagePack (pack, unpackM)
import           System.MQ.Monad                (foreverSafe, runMQMonad)
import           System.MQ.Protocol             (MessageTag, messageSpec, messageType)
import           System.MQ.Transport.ByteString (sub)
import qualified Data.Text as T (pack)
import           System.MQ.WebSocket.Connection (SubsMap, WSConnection (..),
                                                 sharedSubs, websocketName)
import           System.MQ.WebSocket.Protocol   (Subscription (..),
                                                 WSMessage (..),
                                                 WSData (..), wildcard)

-- | Listen to Monique and translate all messages from queue to WebSocket connections
-- that are subscribed to these kind of messages.
listenMonique :: IO ()
listenMonique = runMQMonad $ do
    TwoChannels{..} <- load2Channels

    foreverSafe websocketName $ do
        tm@(tag, _) <- sub fromScheduler
        -- received tag in MessagePack, thus it should be unpack to normal bytestring
        tagUnpacked <- unpackM tag
        let mSpec = T.pack . messageSpec        $ tagUnpacked
        let mType = T.pack . show . messageType $ tagUnpacked

        subsMap       <- liftIO $ readTVarIO sharedSubs

        let connections = getConnections subsMap (Subscription mSpec mType)    ++
                          getConnections subsMap (Subscription mSpec wildcard) ++
                          getConnections subsMap (Subscription wildcard mType) ++
                          getConnections subsMap (Subscription wildcard wildcard)

        liftIO $ mapM_ (sendMsg tm) connections

  where
    getConnections :: SubsMap -> Subscription -> [WS.Connection]
    getConnections subsMap = fmap (\(WSConnection _ _ x) -> x) . fromMaybe [] . (subsMap !?)

    sendMsg :: (MessageTag, BS.ByteString) -> ClientApp ()
    sendMsg (tag, msg) = flip WS.sendTextData (pack . WSPushedFromMQ $ WSMessage tag msg)

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module System.MQ.WebSocket.FromWS
  (
    listenWebSocket
  ) where

import           Control.Exception              (finally)
import           Control.Monad.IO.Class         (liftIO)
import Data.Text as T (Text, unpack)
import           Data.Aeson                     (eitherDecode)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy           as BSL (ByteString, toStrict)
import           Data.List                      (find)
import           Data.Maybe                     (maybe)
-- import           Data.MessagePack               (unpack)
import           Data.String                    (fromString)
import qualified Network.WebSockets             as WS
import           System.Log.Logger              (errorM, infoM)
import           System.MQ.Component            (TwoChannels (..),
                                                 load2Channels)
import qualified System.MQ.Encoding.MessagePack as MP (pack, unpack)
import Data.MessagePack (MessagePack (..))
import           System.MQ.Monad                (MQMonad, foreverSafe,
                                                 runMQMonad)
import           System.MQ.Transport.ByteString (push)
import           System.MQ.Transport (PushChannel)
import           System.MQ.WebSocket.Connection (ClientId, WSConnection (..), closeConnection,
                                                 packConnection,
                                                 unsubscribeConnection,subscribeConnection,
                                                 websocketName)
import           System.MQ.WebSocket.Protocol   (WSData (..), WSMessage (..), WSError (..))
import           Web.Cookie                     (parseCookiesText)

-- | WebSocket listener function.
-- Processes a `PendingConnection` as follows:
-- * if client id can be restored from cookies, accept the connection and process request from him.
-- * reject the connection otherwise.
--
listenWebSocket :: WS.PendingConnection -> IO ()
listenWebSocket pending = maybe (rejectConnection pending) (acceptConnection pending) clientIdFromCookies
  where
    -- | Try to restore client id from cookies.
    clientIdFromCookies :: Maybe ClientId
    clientIdFromCookies = do
        let headers = WS.requestHeaders . WS.pendingRequest $ pending
        (_, cookiesText) <- find ((== "Cookie") . fst) headers
        lookup "id" $ parseCookiesText cookiesText

-- | Reject a pending connection.
-- All connections from users whom clientId can not be restored from cookies will be rejected.
--
rejectConnection :: WS.PendingConnection -> IO ()
rejectConnection pending = do
    errorM websocketName "user id not found in cookies."
    WS.rejectRequest pending $ MP.pack $ WSError "user id not found in cookies."

-- | Function that accepts a pending connection from new client.
--
acceptConnection :: WS.PendingConnection -> ClientId -> IO ()
acceptConnection pending clientId = do
    connection <- WS.acceptRequest pending
    WS.forkPingThread connection 30
    infoM websocketName $ "New connection established for the clientID: " ++ T.unpack clientId
    wsConnection <- packConnection clientId connection

    finally (dispatchClientMessage wsConnection) (closeConnection wsConnection)


-- | Dispatch messages from an accepted connection.
-- This function is a bridge (unidirectional) between WebSocket and MoniQue.
--
dispatchClientMessage :: WSConnection -> IO ()
dispatchClientMessage wsConnection@(WSConnection _ _ connection) = runMQMonad $ do
    TwoChannels{..} <- load2Channels
    foreverSafe websocketName $ do
        packedMessage <- liftIO $ WS.receiveData connection :: MQMonad BSL.ByteString
        let m = MP.unpack $ BSL.toStrict packedMessage :: Maybe WSData
        liftIO $ print m
        maybe (rejectMessage "unknown message") (dispatchMessage toScheduler) m

  where
    rejectMessage :: Text -> MQMonad ()
    rejectMessage e = liftIO $ do
        errorM websocketName (T.unpack e)
        WS.sendBinaryData connection . MP.pack . WSError $ e

    sendReply :: MessagePack a => a -> MQMonad ()
    sendReply = liftIO . WS.sendBinaryData connection . MP.pack
    
    -- | PROTOCOL REALIZATION
    --
    dispatchMessage :: PushChannel -> WSData ->  MQMonad ()
    -- if 'WSPing' received, then send back 'WSPong' with the same time
    dispatchMessage _ (WSPing t) = sendReply $ WSPong t
    -- 'WSPong' could not be sent by the client
    dispatchMessage _ (WSPong _) = rejectMessage "<pong> message could not be sent from the client"
    -- if 'WSSubscribe' received, then subscribe current channel and send reply with the same subscribes
    dispatchMessage _ (WSSubscribe s) = do
        subscribeConnection wsConnection s
        sendReply $ WSSubscribed s
    -- 'WSSubscribed' could not be sent by the client
    dispatchMessage _ (WSSubscribed _) = rejectMessage "<subscribed> message could not be sent from the client"
    -- if 'WSUnubscribe' received, then unsubscribe current channel and send reply with the same subscribes
    dispatchMessage _ (WSUnsubscribe s) = do
        unsubscribeConnection wsConnection s
        sendReply $ WSUnsubscribed s
    -- 'WSSubscribed' could not be sent by the client
    dispatchMessage _ (WSUnsubscribed _) = rejectMessage "<unsubscribed> message could not be sent from the client"
    -- if 'WSPushToMQ' received, then get tag and message and push it to MoniQue
    dispatchMessage toScheduler' (WSPushToMQ WSMessage {..}) = do
        push toScheduler' (MP.pack wsTag, wsMessage)
        sendReply $ WSPushedToMQ wsTag
    -- 'WSPushedToMQ' could not be sent by the client
    dispatchMessage _ (WSPushedToMQ _) = rejectMessage "<pushed_to_mq> message could not be sent from the client"
    -- 'WSPushedFromMQ' could not be sent by the client
    dispatchMessage _ (WSPushedFromMQ _) = rejectMessage "<pushed_from_mq> message could not be sent from the client"

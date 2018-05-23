{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module System.MQ.WebSocket.FromWS
  (
    listenWebSocket
  ) where

import           Control.Exception                    (finally)
import           Control.Monad.IO.Class               (liftIO)
import           Data.Aeson                           (eitherDecode)
import qualified Data.ByteString.Lazy                 as BSL (ByteString)
import           Data.List                            (find)
import           Data.MessagePack                     (unpack)
import           Data.String                          (fromString)
import qualified Network.WebSockets                   as WS
import           System.MQ.Component                  (TwoChannels (..),
                                                       load2Channels)
import qualified System.MQ.Encoding.MessagePack       as MP (pack)
import           System.MQ.Monad                      (MQMonad, foreverSafe,
                                                       runMQMonad)
import           System.MQ.Transport.ByteString       (push)
import           System.MQ.WebSocket.Atomic.Functions (addConnectionM,
                                                       packConnectionWithSpec,
                                                       removeConnectionM)
import           System.MQ.WebSocket.Atomic.Types     (ClientId,
                                                       ConnectionSetup (..),
                                                       WSMessage (..),
                                                       pingMessage, pongMessage,
                                                       websocketName)
import           Web.Cookie                           (parseCookiesText)

-- | WebSocket listener function.
-- Processes a `PendingConnection` as follows:
-- * if client id can be restored from cookies, accept the connection, add user to @sharedClients@, process request from him.
-- * reject the connection otherwise.
--
listenWebSocket :: WS.PendingConnection -> IO ()
listenWebSocket pending = maybe (rejectConnection pending) (acceptConnection pending) (clientIdFromCookies pending)

-- | Function that accepts a pending connection from new client.
-- The client should send specs that he would like to listen in the very first message after connection is established.
--
acceptConnection :: WS.PendingConnection -> ClientId -> IO ()
acceptConnection pending clientId = do
    connection <- WS.acceptRequest pending
    WS.forkPingThread connection 30
    setupJSON <- WS.receiveData connection :: IO BSL.ByteString

    case eitherDecode setupJSON of
      Left e -> WS.rejectRequest pending (fromString e)
      Right (ConnectionSetup specs) -> do
          wsConnection <- packConnectionWithSpec connection specs
          let clientConnection = (clientId, wsConnection)
          addConnectionM clientConnection

          finally (dispatchClientMessage connection) (removeConnectionM clientConnection)

-- | Reject a pending connection.
-- All connections from users whom clientId can not be restored from cookies will be rejected.
--
rejectConnection :: WS.PendingConnection -> IO ()
rejectConnection pending = WS.rejectRequest pending "User id not found in cookies."

-- | Dispatch messages from an accepted connection.
-- This function is a bridge (unidirectional) between WebSocket and MoniQue.
--
dispatchClientMessage :: WS.Connection -> IO ()
dispatchClientMessage connection = runMQMonad $ do
    TwoChannels{..} <- load2Channels

    foreverSafe websocketName $ do
        packedMessage <- liftIO $ WS.receiveData connection :: MQMonad BSL.ByteString
        -- let maybePing = unpack packedMessage :: Maybe BSL.ByteString

        if packedMessage == pingMessage
           then liftIO $ WS.sendBinaryData connection pongMessage
        else do
          message <- unpack packedMessage
          -- to send message correctly into queue tag should be converted into MessagePack
          push toScheduler (MP.pack $ wsTag message, wsMessage message)

-- | Try to restore client id from cookies.
--
clientIdFromCookies :: WS.PendingConnection -> Maybe ClientId
clientIdFromCookies pending = do
    let headers = WS.requestHeaders . WS.pendingRequest $ pending
    (_, cookiesText) <- find ((== "Cookie") . fst) headers
    lookup "id" $ parseCookiesText cookiesText



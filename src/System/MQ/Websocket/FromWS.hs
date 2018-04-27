{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module System.MQ.Websocket.FromWS
  (
    listenWebSocket
  ) where

import           Control.Exception                    (finally)
import           Control.Monad                        (forever)
import           Data.Aeson.Picker                    ((|--))
import qualified Data.ByteString.Lazy                 as BSL (ByteString)
import           Data.List                            (find)
import           Data.MessagePack                     (unpack)
import           Data.Text                            (Text)
import qualified Network.WebSockets                   as WS
import           System.MQ.Component                  (TwoChannels (..),
                                                       load2Channels)
import           System.MQ.Monad                      (runMQMonad)
import           System.MQ.Transport.ByteString       (push)
import           System.MQ.Websocket.Atomic.Functions (addConnectionM,
                                                       packConnectionWithSpec,
                                                       removeConnectionM)
import           System.MQ.Websocket.Atomic.Types     (ClientId, Spec,
                                                       WSMessage (..))
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
  specsJSON <- WS.receiveData connection :: IO Text
  let specs = specsJSON |-- ["specs"] :: [Spec]

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
dispatchClientMessage connection = do
  TwoChannels{..} <- runMQMonad load2Channels
  forever $ do
    packedMessage <- WS.receiveData connection :: IO BSL.ByteString
    message <- unpack packedMessage
    runMQMonad $ push toScheduler (wsTag message, wsMessage message)

-- | Try to restore client id from cookies.
--
clientIdFromCookies :: WS.PendingConnection -> Maybe ClientId
-- clientIdFromCookies pending = Just "abracadabra"
clientIdFromCookies pending = do
  let headers = WS.requestHeaders . WS.pendingRequest $ pending
  (_, cookiesText) <- find ((== "Cookie") . fst) headers
  lookup "id" $ parseCookiesText cookiesText



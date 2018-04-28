{-# LANGUAGE OverloadedStrings #-}

module System.MQ.WebSocket
  (
    runWebSocket
  ) where

import           Control.Concurrent         (forkIO)
import           Control.Monad.IO.Class     (liftIO)
import           Data.Aeson.Picker          ((|--))
import qualified Network.WebSockets         as WS
import           System.BCD.Config          (getConfigText)
import           System.MQ.Component        (Env)
import           System.MQ.Monad            (MQMonad)
import           System.MQ.WebSocket.FromMQ (listenMonique)
import           System.MQ.WebSocket.FromWS (listenWebSocket)

runWebSocket :: Env -> MQMonad ()
runWebSocket _ = liftIO $ do
    config <- getConfigText
    let host = config |-- ["params", "websocket", "host"] :: String
    let port = config |-- ["params", "websocket", "port"] :: Int

    _ <- forkIO listenMonique
    WS.runServer host port listenWebSocket

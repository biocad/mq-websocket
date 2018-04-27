{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Control.Concurrent  (forkIO)
import           Data.Aeson.Picker   ((|--))
import qualified Network.WebSockets  as WS
import           System.BCD.Config   (getConfigText)
import           System.MQ.WebSocket (listenMonique, listenWebSocket)

main :: IO ()
main = do
  config <- getConfigText
  let host = config |-- ["params", "websocket", "host"] :: String
  let port = config |-- ["params", "websocket", "port"] :: Int

  _ <- forkIO listenMonique
  WS.runServer host port listenWebSocket

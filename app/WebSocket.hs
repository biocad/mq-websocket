module Main where

import           System.MQ.Component (runApp)
import           System.MQ.WebSocket (runWebSocket)

main :: IO ()
main = runApp "mq_websocket" runWebSocket

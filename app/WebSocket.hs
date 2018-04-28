module Main where

import           System.MQ.Component (runApp)
import           System.MQ.WebSocket (runWebSocket)

-- | Make WebSocket a MQ component. Hence it will have a standard technical layer which will send monitoring messages and will react on kill messages.
-- So, configuration for monitoring in `config.json` is required.
--
main :: IO ()
main = runApp "mq_websocket" runWebSocket

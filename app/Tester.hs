{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Control.Monad        (forever)
import           Data.Aeson.Picker    ((|--))
import qualified Data.ByteString      as BS
import           Data.ByteString.Lazy (toStrict)
import qualified Data.MessagePack     as MP (pack)
import           Data.String          (IsString (..))
import           Network.Socket       (withSocketsDo)
import qualified Network.WebSockets   as WS
import           System.BCD.Config    (getConfigText)
import           System.MQ.Monad      (runMQMonad)
import           System.MQ.Protocol   (MessageLike (..), MessageType (..),
                                       Props (..), createMessage, messageTag,
                                       notExpires)
import           System.MQ.WebSocket  (WSMessage (..))

newtype TesterData = TesterData { testerData :: BS.ByteString
                                }

testerProps :: Props TesterData
testerProps = Props "mq_websocket_tester" Config "JSON"

instance MessageLike TesterData where
  props  = testerProps
  pack   = testerData
  unpack = Just . TesterData


main :: IO ()
main = do
    config <- getConfigText
    let host = config |-- ["params", "mq_websocket", "host"] :: String
    let port = config |-- ["params", "mq_websocket", "port"] :: Int

    withSocketsDo $ WS.runClient host port "/" listener
    putStrLn "listener started."
    withSocketsDo $ WS.runClient host port "/" speaker
    putStrLn "speaker started."


listener :: WS.ClientApp ()
listener connection = forever $ do
    msg <- WS.receiveData connection :: IO BS.ByteString
    putStrLn "Received message"
    print msg

speaker :: WS.ClientApp ()
speaker connection = forever $ do
    tell <- getLine
    let tData = TesterData (fromString tell :: BS.ByteString)
    msg <- runMQMonad $ createMessage "" "mq_websocket_tester" notExpires tData
    let tag = messageTag msg
    let wsMsg = WSMessage tag (toStrict $ MP.pack msg)
    let packedMessage = MP.pack wsMsg
    WS.sendTextData connection packedMessage


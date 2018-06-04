{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE ViewPatterns      #-}

module Main where

import           Control.Concurrent             (forkIO)
import           Control.Monad                  (forever)
import           Control.Monad.IO.Class         (liftIO)
import           Data.Aeson.Picker              ((|--))
import           Data.ByteString                (ByteString)
import qualified Data.ByteString                as BS
import           Data.CaseInsensitive           (CI (..))
import           Data.MessagePack               (MessagePack (..))
import           Data.Text                      as T (pack)
import           Network.Socket                 (withSocketsDo)
import qualified Network.WebSockets             as WS
import           Numeric                        (showHex)
import           System.BCD.Config              (getConfigText)
import qualified System.MQ.Encoding.MessagePack as MP (pack, unpack)
import           System.MQ.Monad                (runMQMonad)
import           System.MQ.Protocol             (Message (..), createMessageBS,
                                                 emptyHash, messageTag,
                                                 notExpires)
import           System.MQ.WebSocket            (getTimeNano)
import           System.MQ.WebSocket.Protocol   (CommandLike (..),
                                                 Subscription (..), WSData (..),
                                                 WSMessage (..))



main :: IO ()
main = do
    config <- getConfigText
    let host = config |-- ["deploy", "monique", "websocket", "host"] :: String
    let port = config |-- ["deploy", "monique", "websocket", "port"] :: Int
    withSocketsDo $ WS.runClientWith host port "/"  WS.defaultConnectionOptions cookie processer

cookie :: [(CI BS.ByteString, BS.ByteString)]
cookie = [("Cookie", "id=0000-0000-0000-websocket-tester")]

processer :: WS.ClientApp ()
processer connection = do
    putStrLn "Initialized..."
    _ <- forkIO $ forever $ listener connection
    speaker connection



listener :: WS.ClientApp ()
listener connection = forever $ do
    msg <- WS.receiveData connection :: IO BS.ByteString
    putStrLn "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
    putStrLn "FULL MESSAGE:"
    print msg

    putStrLn "\nFULL MESSAGE (HEX):"
    putStrLn $ unwords $ map (`showHex` "") (BS.unpack msg)

    case MP.unpack msg :: (Maybe WSData) of
        Just msgUnpacked@(WSPushedFromMQ (WSMessage tag' msg')) -> do
            putStrLn "\nCOMMAND"
            print $ command msgUnpacked
            putStrLn "\nTAG FROM MQ"
            print (MP.unpack tag' :: Maybe ByteString)
            putStrLn "\nMESSAGE FROM MQ (HEX)"
            putStrLn $ unwords $ map (`showHex` "") (BS.unpack msg')
            putStrLn "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n"

        Just msgUnpacked -> do
            putStrLn "\nCOMMAND"
            print $ command msgUnpacked
            putStrLn "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n"

        Nothing -> do
            putStrLn "\nERROR: could not unpack WSMessage"
            putStrLn "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n"

speaker :: WS.ClientApp ()
speaker connection = do
  help
  forever $ do
    comm <- getLine
    case words comm of
        ["ping"] -> do
            now <- getTimeNano
            sendToServer $ WSPing now
        ["pong"] -> do
            now <- getTimeNano
            sendToServer $ WSPing now
        ["subscribe", spec', type'] ->
            sendToServer $ WSSubscribe [Subscription (T.pack spec') (T.pack type')]
        ["unsubscribe", spec', type'] ->
            sendToServer $ WSUnsubscribe [Subscription (T.pack spec') (T.pack type')]
        ["push", spec', read -> type', encoding', path] -> do
            dataBS <- liftIO $ BS.readFile path
            msg@Message{..} <- runMQMonad $ createMessageBS emptyHash "0000-0000-0000-websocket-tester" notExpires spec' encoding' type' dataBS
            let tag = messageTag msg
            sendToServer . WSPushToMQ . WSMessage tag $ MP.pack msg
        _        -> help
  where
    sendToServer :: MessagePack a => a -> IO ()
    sendToServer = WS.sendBinaryData connection . MP.pack

help :: IO ()
help = do
    putStrLn "Commands:"
    putStrLn "   help"
    putStrLn "   ping"
    putStrLn "   pong"
    putStrLn "   subscribe <spec> <type>"
    putStrLn "   unsubscribe <spec> <type>"
    putStrLn "   push <spec> <type> <encoding> <path/to/data>"

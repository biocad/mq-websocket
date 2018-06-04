{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE ViewPatterns      #-}

module Main where

import           Control.Concurrent             (forkIO)
import Control.Monad.IO.Class (liftIO)
import           Control.Monad                  (forever)
import           Data.Aeson                     (FromJSON (..), ToJSON (..))
import           Data.Aeson.Picker              ((|--))
import qualified Data.ByteString                as BS
import           Data.CaseInsensitive           (CI (..))
import           Data.MessagePack               (MessagePack (..))
import           Data.Text                      as T (pack)
import           GHC.Generics                   (Generic)
import           Network.Socket                 (withSocketsDo)
import qualified Network.WebSockets             as WS
import           Numeric                        (showHex)
import           System.BCD.Config              (getConfigText)
import qualified System.MQ.Encoding.JSON        as JSON (pack, unpack)
import qualified System.MQ.Encoding.MessagePack as MP (pack, unpack)
import           System.MQ.Monad                (runMQMonad)
import           System.MQ.Protocol             (Message (..), MessageLike (..),
                                                 MessageType (..), Props (..),
                                                 createMessageBS, emptyHash,
                                                 jsonEncoding, messageTag,
                                                 notExpires)
import           System.MQ.WebSocket            (getTimeNano)
import           System.MQ.WebSocket.Protocol   (CommandLike (..),
                                                 Subscription (..), WSData (..),
                                                 WSMessage (..))

-- | 'CalculatorConfig' represents configuration data for calculator.
--
data CalculatorConfig = CalculatorConfig { first  :: Float
                                         , second :: Float
                                         , action :: String
                                         }
  deriving (Show, Generic)

instance ToJSON CalculatorConfig
instance FromJSON CalculatorConfig
instance MessageLike CalculatorConfig where
  props = Props "example_calculator" Config jsonEncoding
  pack = JSON.pack
  unpack = JSON.unpack

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
    -- initialize with "example_calculator" spec
    -- WS.sendTextData connection $ ("asdasd" :: BS.ByteString) --MP.pack $ WSPong 123 --  (JSON.pack $ ConnectionSetup ["example_calculator"])
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
            print tag'
            putStrLn "\nMESSAGE FROM MQ (HEX)"
            putStrLn $ unwords $ map (`showHex` "") (BS.unpack msg')
            putStrLn "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n"

        Just msgUnpacked -> do
            putStrLn "\nCOMMAND"
            print $ command msgUnpacked
            -- putStrLn "\nDATA"
            -- print $ wsMessage msgUnpacked
            -- putStrLn "\nMESSAGE (HEX)"
            -- putStrLn $ unwords $ map (`showHex` "") (BS.unpack $ wsMessage msgUnpacked)
            putStrLn "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n"

        Nothing -> do
            putStrLn "\nERROR: could not unpack WSMessage"
            putStrLn "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n"

speaker :: WS.ClientApp ()
speaker connection = forever $ do
    comm <- getLine
    case words comm of
        ["ping"] -> do
            now <- getTimeNano
            sendToServer $ WSPing now
        ["pong"] -> do
            now <- getTimeNano
            sendToServer $ WSPing now
        ["subscribe", spec', type'] -> do
            sendToServer $ WSSubscribe [Subscription (T.pack spec') (T.pack type')]
        ["unsubscribe", spec', type'] -> do
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
    {-putStrLn "Enter first number: "
    num1 <- read <$> getLine
    putStrLn "Enter second number: "
    num2 <- read <$> getLine
    putStrLn "Enter operation: "
    operation <- getLine
    let cConfig = CalculatorConfig num1 num2 operation
    print cConfig
    msg <- runMQMonad $ createMessage emptyHash "0000-0000-0000-websocket-tester" notExpires cConfig
    let tag = messageTag msg
    let wsMsg = WSMessage tag (MP.pack msg)
    let packedMessage = MP.pack wsMsg
    WS.sendTextData connection packedMessage
-}
help :: IO ()
help = putStrLn ""

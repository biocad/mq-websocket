{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns        #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module System.MQ.WebSocket.Protocol.Instances () where

import           Control.Monad                      ((>=>))
import           Data.Map.Strict                    (Map, fromList, member, (!))
import           Data.MessagePack.Types.Class       (MessagePack (..))
import           Data.MessagePack.Types.Object      (Object)
import           Data.Text                          (Text, unpack)
import           System.MQ.Protocol                 (Dictionary (..))
import           System.MQ.WebSocket.Protocol.Types

instance Dictionary WSMessage where
  toDictionary WSMessage{..} = fromList [ ("tag", toObject wsTag)
                                        , ("message", toObject wsMessage)
                                        ]
  fromDictionary dict = do
    wsTag     <- dict .! "tag"
    wsMessage <- dict .! "message"
    pure WSMessage{..}

instance MessagePack WSMessage where
  toObject = toObject . toDictionary
  fromObject = fromObject >=> fromDictionary

instance Dictionary Subscription where
  toDictionary Subscription{..} = fromList [ ("spec", toObject subSpec)
                                           , ("type", toObject subType)
                                           ]
  fromDictionary dict = do
    subSpec <- dict .! "spec"
    subType <- dict .! "type"
    pure Subscription{..}

instance MessagePack Subscription where
  toObject = toObject . toDictionary
  fromObject = fromObject >=> fromDictionary


instance CommandLike WSData where
  command (WSPing _)         = "ping"
  command (WSPong _)         = "pong"
  command (WSSubscribe _)    = "subscribe"
  command (WSSubscribed _)   = "subscribed"
  command (WSUnsubscribe _)  = "unsubscribe"
  command (WSUnsubscribed _) = "unsubscribed"
  command (WSPushToMQ _)     = "push_to_mq"
  command (WSPushedToMQ _)   = "pushed_to_mq"
  command (WSPushedFromMQ _) = "pushed_from_mq"

instance Dictionary WSData where
  toDictionary x@(WSPing y)         = prepare x y
  toDictionary x@(WSPong y)         = prepare x y
  toDictionary x@(WSSubscribe y)    = prepare x y
  toDictionary x@(WSSubscribed y)   = prepare x y
  toDictionary x@(WSUnsubscribe y)  = prepare x y
  toDictionary x@(WSUnsubscribed y) = prepare x y
  toDictionary x@(WSPushToMQ y)     = prepare x y
  toDictionary x@(WSPushedToMQ y)   = prepare x y
  toDictionary x@(WSPushedFromMQ y) = prepare x y


  fromDictionary dict = do
    command' :: Text <- dict .! "command"
    case command' of
        "ping"           -> WSPing         <$> dict .! "data"
        "pong"           -> WSPong         <$> dict .! "data"
        "subscribe"      -> WSSubscribe    <$> dict .! "data"
        "subscribed"     -> WSSubscribed   <$> dict .! "data"
        "unsubscribe"    -> WSUnsubscribe  <$> dict .! "data"
        "unsubscribed"   -> WSUnsubscribed <$> dict .! "data"
        "push_to_mq"     -> WSPushToMQ     <$> dict .! "data"
        "pushed_to_mq"   -> WSPushedToMQ   <$> dict .! "data"
        "pushed_from_mq" -> WSPushedFromMQ <$> dict .! "data"
        e -> error $ "Message with command <" ++ unpack e ++ "> is not allowed in MoniQue websocket protocol."

-- | Helpful function to convert 'WSData' into dictionary
prepare :: MessagePack y => WSData -> y -> Map Text Object
prepare (command -> x) y = fromList [ ("command", toObject x), ("data", toObject y)]

instance MessagePack WSData where
  toObject = toObject . toDictionary
  fromObject = fromObject >=> fromDictionary



-- | Internal helpful function
--
infix .!
(.!) :: (Monad m, MessagePack b) => Map Text Object -> Text -> m b
dict .! key | key `member` dict = fromObject $ dict ! key
            | otherwise = error $ "System.MQ.WebSocket.Protocol.Internal.Types: .! :: key " ++ show key ++ " is not an element of the dictionary."


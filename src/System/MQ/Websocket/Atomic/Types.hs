{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module System.MQ.Websocket.Atomic.Types
  (
    ClientId
  , Spec
  , Clients
  , ClientConnection
  , WSConnection (..)
  , WSMessage (..)
  , Timestamp
  , Specs
  ) where

import           Control.Monad                 ((>=>))
import           Data.ByteString               (ByteString)
import           Data.Map.Strict               (Map, fromList, member, (!))
import           Data.MessagePack.Types.Class  (MessagePack (..))
import           Data.MessagePack.Types.Object (Object)
import           Data.Text                     (Text)
import qualified Network.WebSockets            as WS
import           System.MQ.Protocol            (Dictionary (..), MessageTag,
                                                Spec)

type ClientId = Text

type Timestamp = Int

type ClientConnection = (ClientId, WSConnection)

type Clients = Map ClientId [WSConnection]

type Specs = Map Spec [ClientConnection]

-- | WebSocket connection wrapper type.
-- Creation time is used as an identifier which helps to distinguish connections.
data WSConnection = WSConnection { wsTime         :: Int           -- ^ Connection creation time. Acts as identifier.
                                 , wsConnection   :: WS.Connection -- ^ Connection itself
                                 , wsAcceptedSpec :: [Spec]        -- ^ Specs which creator of the connection accepts.
                                 }

instance Eq WSConnection where
  wsConn1 == wsConn2 = wsTime wsConn1 == wsTime wsConn2

instance Ord WSConnection where
  wsConn1 <= wsConn2 = wsTime wsConn1 <= wsTime wsConn2


data WSMessage = WSMessage { wsTag     :: MessageTag
                           , wsMessage :: ByteString
                           } deriving (Eq, Ord, Show)

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

infix .!
(.!) :: (Monad m, MessagePack b) => Map ByteString Object -> ByteString -> m b
dict .! key | key `member` dict = fromObject $ dict ! key
  | otherwise = error $ "System.MQ.Websocket.Atomic.Types: .! :: key " ++ show key ++ " is not an element of the dictionary."

{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module System.MQ.WebSocket.Atomic.Types
  (
    ClientId
  , Spec
  , Clients
  , ClientConnection
  , ConnectionSetup (..)
  , WSConnection (..)
  , WSMessage (..)
  , Timestamp
  , Specs
  , websocketName
  , pingMessage
  , pongMessage
  ) where

import           Control.Monad                 ((>=>))
import           Data.Aeson                    (FromJSON (..), ToJSON (..))
import           Data.ByteString               (ByteString)
import qualified Data.ByteString.Lazy          as BSL (ByteString)
import           Data.Map.Strict               (Map, fromList, member, (!))
import           Data.MessagePack.Types.Class  (MessagePack (..))
import           Data.MessagePack.Types.Object (Object)
import           Data.Text                     (Text)
import           GHC.Generics                  (Generic)
import qualified Network.WebSockets            as WS
import           System.MQ.Protocol            (Dictionary (..), MessageTag,
                                                Spec, MessageType)

-- | Name for the application
websocketName :: String
websocketName = "mq-websocket"

--------------------------------------------------------------------------------
-- Ping pong
--------------------------------------------------------------------------------

-- | Ping content
pingMessage :: BSL.ByteString
pingMessage = "ping"

-- | Pong content
pongMessage :: BSL.ByteString
pongMessage = "pong"

--------------------------------------------------------------------------------
-- Connections
--------------------------------------------------------------------------------

-- | 'ClientId' is used to parameterize connection, takes from Cookie.
type ClientId = Text

type Timestamp = Int

type ClientConnection = (ClientId, WSConnection)

-- | Map to represent 'ClientId' with corresponding connections.
type Clients = Map ClientId [WSConnection]

-- | Map to represent reseived 'Spec's with correctonding 'ClientConnection's.
type Specs = Map Spec [ClientConnection]

-- | WebSocket connection wrapper type.
-- Creation time is used as an identifier which helps to distinguish connections.
data WSConnection = WSConnection {-# UNPACK #-} !Timestamp     -- ^ Connection creation time. Acts as identifier.
                                 {-# UNPACK #-} !ClientId      -- ^ Client identificator
                                 {-# UNPACK #-} !WS.Connection -- ^ Connection itself
                                 

instance Eq WSConnection where
  (WSConnection t1 _ _) == (WSConnection t2 _ _) = t1 == t2

instance Ord WSConnection where
  (WSConnection t1 _ _) <= (WSConnection t2 _ _) = t1 <= t2

-- -- | 'MessageType' describes valid message types in Monique with additional .
-- --
-- data MessageType = Config | Result | Error | Data | AnyType
--   deriving (Eq, Generic)

-- instance Show MessageType where
--   show Config  = "config"
--   show Result  = "result"
--   show Error   = "error"
--   show Data    = "data"
--   show AnyType = "*"

-- instance Read MessageType where
--   readsPrec _ "config" = [(Config, "")]
--   readsPrec _ "result" = [(Result, "")]
--   readsPrec _ "error"  = [(Error, "")]
--   readsPrec _ "data"   = [(Data, "")]
--   readsPrec _ "*"      = [(AnyType, "")]
--   readsPrec _ _        = []

-- | Subscription is 
data Subscription = Subscription {-# UNPACK #-} Spec
                                 {-# UNPACK #-} MessageType




newtype ConnectionSetup = ConnectionSetup { specs :: [String] }
  deriving (Generic, Show)

instance ToJSON ConnectionSetup
instance FromJSON ConnectionSetup

--------------------------------------------------------------------------------
-- WebSocket message
--------------------------------------------------------------------------------

-- | 'WSMessage' represents data that sent via WebSocket connection.
--
data WSMessage = WSMessage { wsTag     :: MessageTag -- ^ tag in bytestring
                           , wsMessage :: ByteString -- ^ message content, packed in MessagePack
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
(.!) :: (Monad m, MessagePack b) => Map Text Object -> Text -> m b
dict .! key | key `member` dict = fromObject $ dict ! key
            | otherwise = error $ "System.MQ.WebSocket.Atomic.Types: .! :: key " ++ show key ++ " is not an element of the dictionary."

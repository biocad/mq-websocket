{-# LANGUAGE OverloadedStrings #-}

module System.MQ.WebSocket.Protocol.Types
  (
    Timestamp
  , Subscription (..)
  , WSMessage (..)
  , WSData (..)
  , CommandLike (..)
  , wildcard
  ) where

import           Data.ByteString    (ByteString)
import           Data.Text          (Text)
import           System.MQ.Protocol (MessageTag)

-- | Current timestamp in nanoseconds. Nanoseconds are used to decrease probability
-- that different connections will have the same identifier.
type Timestamp = Int

-- | This symbol is used to mark "any" @type@s or @spec@s.
--
wildcard :: Text
wildcard = "*"

-- | Describes which messages with @spec@ and @type@ are interested for the current connection.
-- To get all @spec@s wildcard symbol ("*") is used.
-- To get all @type@s the same symbol is used.
--
data Subscription = Subscription { subSpec :: Text -- ^ str; subscription specification
                                 , subType :: Text -- ^ str; subscription type
                                 }
  deriving (Eq, Ord, Show)

-- | 'WSMessage' represents data that sent via WebSocket connection to and from MoniQue system.
--
data WSMessage = WSMessage { wsTag     :: MessageTag -- ^ bin; tag in bytestring
                           , wsMessage :: ByteString -- ^ bin; message content, packed in MessagePack
                           }
  deriving (Eq, Ord, Show)

-- | Describes high level of websocket protocol.
--
data WSData = WSPing         Timestamp
            | WSPong         Timestamp
            | WSSubscribe    [Subscription]
            | WSSubscribed   [Subscription]
            | WSUnsubscribe  [Subscription]
            | WSUnsubscribed [Subscription]
            | WSPushToMQ     WSMessage
            | WSPushedToMQ   WSMessage
            | WSPushedFromMQ WSMessage
  deriving (Eq, Ord, Show)

-- | Tiny helpful class to marks messages with the command.
--
class CommandLike a where
    command :: a -> Text

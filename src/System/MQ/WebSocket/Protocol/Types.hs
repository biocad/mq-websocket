module System.MQ.WebSocket.Protocol.Types where

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
                                                MessageType, Spec)

-- | Current timestamp in nanoseconds. Nanoseconds are used to decrease probability
-- that different connections will have the same identifier.
type Timestamp = Int

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

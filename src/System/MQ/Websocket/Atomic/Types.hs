module System.MQ.Websocket.Atomic.Types
  (
    ClientId
  , Spec
  , Clients
  , ClientConnection
  , WSConnection (..)
  , Timestamp
  ) where

import           Data.Map.Strict    (Map)
import           Data.Text          (Text)
import qualified Network.WebSockets as WS
import           System.MQ.Protocol (Spec)

type ClientId = Text

type Timestamp = Int

type Clients = Map ClientId [WSConnection]

type ClientConnection = (ClientId, WSConnection)

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



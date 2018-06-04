{-# LANGUAGE OverloadedStrings #-}

module System.MQ.WebSocket.Connection.Types
  (
    ClientId
  , SubsMap
  , WSConnection (..)
  , websocketName
  ) where

import           Data.Map.Strict              (Map)
import           Data.Text                    (Text)
import qualified Network.WebSockets           as WS
import           System.MQ.WebSocket.Protocol (Subscription, Timestamp)

-- | Name for the application
websocketName :: String
websocketName = "mq-websocket"

-- | 'ClientId' is used to parameterize connection, takes from Cookie.
type ClientId = Text

-- | Map to represent subscriptions for the 'WSConnection's.
type SubsMap = Map Subscription [WSConnection]

-- | WebSocket connection wrapper type.
-- Creation time is used as an identifier which helps to distinguish connections.
data WSConnection = WSConnection {-# UNPACK #-} !Timestamp     -- ^ Connection creation time. Acts as identifier.
                                 {-# UNPACK #-} !ClientId      -- ^ Client identificator
                                 {-# UNPACK #-} !WS.Connection -- ^ Connection itself

instance Eq WSConnection where
  (WSConnection t1 _ _) == (WSConnection t2 _ _) = t1 == t2

instance Ord WSConnection where
  (WSConnection t1 _ _) <= (WSConnection t2 _ _) = t1 <= t2

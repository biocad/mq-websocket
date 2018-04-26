module System.MQ.Websocket.Atomic.Types
  (
    ClientId
  , Spec
  , Clients
  , ClientConnection
  , WSConnection (..)
  , packConnection
  , packConnectionWithSpec
  , clientsCount
  , clientExists
  , addConnection
  , removeConnection
  , allConnections
  , sharedClients
  ) where

import           Control.Concurrent.STM.TVar (TVar, newTVarIO)
import           Control.Monad.IO.Class      (MonadIO (..))
import           Data.List                   (union, (\\))
import           Data.Map.Strict             (Map, empty, insertWith, member,
                                              size, toList, update)
import           Data.Text                   (Text)
import qualified Network.WebSockets          as WS
import           System.Clock                (Clock (..), getTime, toNanoSecs)
import           System.IO.Unsafe            (unsafePerformIO)

type ClientId = Text

type Timestamp = Int

type Spec = String

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


-- | unsafePerformIO is adviced here by the authors of Control.Concurrent
--
sharedClients :: TVar Clients
sharedClients = unsafePerformIO . newTVarIO $ empty

packConnection :: MonadIO m => WS.Connection -> m WSConnection
packConnection connection = packConnectionWithSpec connection []

packConnectionWithSpec :: MonadIO m => WS.Connection -> [Spec] -> m WSConnection
packConnectionWithSpec connection specs = WSConnection <$> getTimeNano <*> pure connection <*> pure specs

clientsCount :: Clients -> Int
clientsCount = size

clientExists :: ClientId -> Clients -> Bool
clientExists = member

addConnection :: ClientConnection -> Clients -> Clients
addConnection (clientId, connection) = insertWith union clientId [connection]

removeConnection :: ClientConnection -> Clients -> Clients
removeConnection (userId, connection) = update searchAndRemove userId
  where searchAndRemove connections = Just $ connections \\ [connection]

allConnections :: Clients -> [WS.Connection]
allConnections = concatMap (fmap wsConnection) . fmap snd . toList

getTimeNano :: MonadIO m => m Timestamp
getTimeNano = liftIO $ fromIntegral . toNanoSecs <$> getTime Realtime

module System.MQ.WebSocket.Atomic.Functions
  (
    packConnection
  , packConnectionWithSpec
  , clientsCountM
  , clientExistsM
  , addConnectionM
  , removeConnectionM
  , allConnectionsM
  , sharedClients
  , sharedSpecs
  ) where

import           Control.Concurrent.STM.TVar      (TVar, modifyTVar', newTVarIO,
                                                   readTVarIO)
import           Control.Monad.IO.Class           (MonadIO (..))
import           Control.Monad.STM                (atomically)
import           Data.List                        (union)
import           Data.Map.Strict                  (empty, insertWith, member,
                                                   size, toList, update)
import qualified Network.WebSockets               as WS
import           System.Clock                     (Clock (..), getTime,
                                                   toNanoSecs)
import           System.IO.Unsafe                 (unsafePerformIO)
import           System.MQ.WebSocket.Atomic.Types (ClientConnection, ClientId,
                                                   Clients, Spec, Specs,
                                                   Timestamp, WSConnection (..))


-- | Shared between FromWS and FromMQ processes memory pointer with all connected clients and specs they have requested.
-- unsafePerformIO is adviced here by the authors of Control.Concurrent
--
sharedClients :: TVar Clients
sharedClients = unsafePerformIO . newTVarIO $ empty


-- | Shared between FromWS and FromMQ processes memory pointer with Map from Spec to clients which want to listen them.
--
sharedSpecs :: TVar Specs
sharedSpecs = unsafePerformIO . newTVarIO $ empty


-- | Pack a WebSocket connection into a wrapper which is Eq and Ord instance
-- and stores for each connection all specs that the client has requested.
--
packConnection :: MonadIO m => WS.Connection -> m WSConnection
packConnection connection = packConnectionWithSpec connection []

packConnectionWithSpec :: MonadIO m => WS.Connection -> [Spec] -> m WSConnection
packConnectionWithSpec connection specs = WSConnection <$> getTimeNano <*> pure connection <*> pure specs


-- | Pure and lifted versions of clients count check.
-- Lifted version uses @sharedClients@ `TVar` to obtain all connected clients.
--
clientsCount :: Clients -> Int
clientsCount = size

clientsCountM :: MonadIO m => m Int
clientsCountM = liftIO $ clientsCount <$> readTVarIO sharedClients


-- | Pure and lifted versions of client existance check.
-- Lifted version uses @sharedClients@ `TVar` to obtain all connected clients.
--
clientExists :: ClientId -> Clients -> Bool
clientExists = member

clientExistsM :: MonadIO m => ClientId -> m Bool
clientExistsM clientId = liftIO $ clientExists clientId <$> readTVarIO sharedClients


-- | Pure and lifted versions of connection addition.
-- Adds connection both to @sgaredClienys@ and @sharedSpecs@.
-- Lifted version uses shared `TVar` pointers to obtain all connected clients and their spec lists.
--
addConnection :: ClientConnection -> Clients -> Clients
addConnection (clientId, connection) = insertWith union clientId [connection]

addSpec :: ClientConnection -> Specs -> Specs
addSpec clientConn@(_, connection) oldSpecs = foldl foldFunc oldSpecs acceptedSpecs
  where
    foldFunc :: Specs -> Spec -> Specs
    foldFunc specMap spec = insertWith union spec [clientConn] specMap

    acceptedSpecs :: [Spec]
    acceptedSpecs | null (wsAcceptedSpec connection) = ["*"]
                  | otherwise = wsAcceptedSpec connection

addConnectionM :: MonadIO m => ClientConnection -> m ()
addConnectionM clientConn = liftIO . atomically $ do
    _ <- modifyTVar' sharedClients . addConnection $ clientConn
    _ <- modifyTVar' sharedSpecs   . addSpec       $ clientConn
    pure ()


-- | Pure and lifted versions of connection removal.
-- Removes connection both from @sharedClients@ and @sharedSpecs@
-- Lifted version uses shared `TVar` pointers to obtain all connected clients and their spec lists.
--
removeConnection :: ClientConnection -> Clients -> Clients
removeConnection (clientId, connection) = update searchAndRemove clientId
  where
    searchAndRemove :: [WSConnection] -> Maybe [WSConnection]
    searchAndRemove connections = Just $ filter (/= connection) connections

removeSpec :: ClientConnection -> Specs -> Specs
removeSpec clientConn = fmap searchAndRemove
  where
    searchAndRemove :: [ClientConnection] -> [ClientConnection]
    searchAndRemove = filter (/= clientConn)

removeConnectionM :: MonadIO m => ClientConnection -> m ()
removeConnectionM clientConn = liftIO . atomically $ do
    _ <- modifyTVar' sharedClients . removeConnection $ clientConn
    _ <- modifyTVar' sharedSpecs   . removeSpec       $ clientConn
    pure ()


-- | Pure and lifted versions of obtaining all WebSocket connections.
-- Lifted version uses @sharedClients@ `TVar` to obtain all connected clients.
--
allConnections :: Clients -> [WS.Connection]
allConnections = concatMap (fmap wsConnection) . fmap snd . toList

allConnectionsM :: MonadIO m => m [WS.Connection]
allConnectionsM = liftIO $ allConnections <$> readTVarIO sharedClients


-- | Get current Epoch time in nanoseconds.
--
getTimeNano :: MonadIO m => m Timestamp
getTimeNano = liftIO $ fromIntegral . toNanoSecs <$> getTime Realtime

module System.MQ.WebSocket.Connection.Functions
  (
    packConnection
  -- , clientsCountM
  -- , clientExistsM
  , addConnection
  , removeConnection
  -- , removeConnectionM
  -- , allConnectionsM
  , sharedSubs
  ) where

import           Control.Concurrent.STM.TVar          (TVar, modifyTVar',
                                                       newTVarIO, readTVarIO)
import           Control.Monad.IO.Class               (MonadIO (..))
import           Control.Monad.STM                    (atomically)
import           Data.List                            (union)
import           Data.Map.Strict                      (empty, insertWith,
                                                       member, size, toList,
                                                       update)
import qualified Network.WebSockets                   as WS
import           System.Clock                         (Clock (..), getTime,
                                                       toNanoSecs)
import           System.IO.Unsafe                     (unsafePerformIO)
import           System.MQ.WebSocket.Connection.Types (ClientId, SubsMap,
                                                       WSConnection (..))
import           System.MQ.WebSocket.Protocol

-- | Shared between FromWS and FromMQ processes memory pointer with Map from 'Subscription' to clients which want to listen them.
-- @unsafePerformIO@ is adviced here by the authors of Control.Concurrent
--
sharedSubs :: TVar SubsMap
sharedSubs = unsafePerformIO . newTVarIO $ empty


-- | Pack a WebSocket connection into a wrapper which is Eq and Ord instance
-- and stores for each connection all specs that the client has requested.
--
packConnection :: MonadIO m => ClientId -> WS.Connection -> m WSConnection
packConnection clientId connection = do
    now <- getTimeNano
    pure $ WSConnection now clientId connection

-- packConnectionWithSpec :: MonadIO m => WS.Connection -> [Spec] -> m WSConnection
-- packConnectionWithSpec connection specs = WSConnection <$> getTimeNano <*> pure connection <*> pure specs


-- -- | Pure and lifted versions of clients count check.
-- -- Lifted version uses @sharedClients@ `TVar` to obtain all connected clients.
-- --
-- clientsCount :: Clients -> Int
-- clientsCount = size

-- clientsCountM :: MonadIO m => m Int
-- clientsCountM = liftIO $ clientsCount <$> readTVarIO sharedClients


-- -- | Pure and lifted versions of client existance check.
-- -- Lifted version uses @sharedClients@ `TVar` to obtain all connected clients.
-- --
-- clientExists :: ClientId -> Clients -> Bool
-- clientExists = member

-- clientExistsM :: MonadIO m => ClientId -> m Bool
-- clientExistsM clientId = liftIO $ clientExists clientId <$> readTVarIO sharedClients


-- | Pure and lifted versions of connection addition.
-- Adds connection both to @sgaredClienys@ and @sharedSpecs@.
-- Lifted version uses shared `TVar` pointers to obtain all connected clients and their spec lists.
--
-- addConnection :: ClientConnection -> Clients -> Clients
-- addConnection (clientId, connection) = insertWith union clientId [connection]

-- addSubs :: WSConnection -> [Subscription] -> SubsMap -> SubsMap
-- addSubs wsConnection subscriptions oldSubs = foldl foldFunc oldSubs subscriptions
--   where
--     foldFunc :: SubsMap -> Subscription -> SubsMap
--     foldFunc subsMap subscription = insertWith union subscription [wsConnection] subsMap

addConnection :: MonadIO m => WSConnection -> [Subscription] -> m ()
addConnection wsConnection subscriptions = liftIO . atomically $ modifyTVar' sharedSubs addSubs
  where
    addSubs :: SubsMap -> SubsMap
    addSubs oldSubs = foldl foldFunc oldSubs subscriptions

    foldFunc :: SubsMap -> Subscription -> SubsMap
    foldFunc subsMap subscription = insertWith union subscription [wsConnection] subsMap



-- -- | Pure and lifted versions of connection removal.
-- -- Removes connection both from @sharedClients@ and @sharedSpecs@
-- -- Lifted version uses shared `TVar` pointers to obtain all connected clients and their spec lists.
-- --
-- removeConnection :: ClientConnection -> Clients -> Clients
-- removeConnection (clientId, connection) = update searchAndRemove clientId
--   where
--     searchAndRemove :: [WSConnection] -> Maybe [WSConnection]
--     searchAndRemove connections = Just $ filter (/= connection) connections

-- removeSpec :: ClientConnection -> Specs -> Specs
-- removeSpec clientConn = fmap searchAndRemove
--   where
--     searchAndRemove :: [ClientConnection] -> [ClientConnection]
--     searchAndRemove = filter (/= clientConn)

removeConnection :: MonadIO m => WSConnection -> m ()
removeConnection wsConnection = liftIO . atomically $ modifyTVar' sharedSubs removeSubs
  where
    removeSubs :: SubsMap -> SubsMap
    removeSubs = fmap (filter (/= wsConnection))

    -- searchAndRemove :: [WSConnection] -> [WSConnection]
    -- searchAndRemove  = filter (/= wsConnection)

{-
-- | Pure and lifted versions of obtaining all WebSocket connections.
-- Lifted version uses @sharedClients@ `TVar` to obtain all connected clients.
--
allConnections :: Clients -> [WS.Connection]
allConnections = concatMap (fmap wsConnection) . fmap snd . toList

allConnectionsM :: MonadIO m => m [WS.Connection]
allConnectionsM = liftIO $ allConnections <$> readTVarIO sharedClients
--}

-- | Get current Epoch time in nanoseconds.
--
getTimeNano :: MonadIO m => m Timestamp
getTimeNano = liftIO $ fromIntegral . toNanoSecs <$> getTime Realtime



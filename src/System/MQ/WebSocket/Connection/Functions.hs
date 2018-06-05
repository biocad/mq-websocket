module System.MQ.WebSocket.Connection.Functions
  (
    packConnection
  , subscribeConnection
  , unsubscribeConnection
  , closeConnection
  , sharedSubs
  , getTimeNano
  ) where

import           Control.Concurrent.STM.TVar          (TVar, modifyTVar',
                                                       newTVarIO)
import           Control.Monad.IO.Class               (MonadIO (..))
import           Control.Monad.STM                    (atomically)
import           Data.List                            (union)
import           Data.Map.Strict                      (empty, insertWith,
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

-- | Subscribes 'WSConnection' to 'Subscription's.
--
subscribeConnection :: MonadIO m => WSConnection -> [Subscription] -> m ()
subscribeConnection wsConnection subscriptions = liftIO . atomically $ modifyTVar' sharedSubs addSubs
  where
    addSubs :: SubsMap -> SubsMap
    addSubs oldSubs = foldl foldFunc oldSubs subscriptions

    foldFunc :: SubsMap -> Subscription -> SubsMap
    foldFunc subsMap subscription = insertWith union subscription [wsConnection] subsMap

-- | Unsubscribe 'WSConnection' from 'Subscription's.
--
unsubscribeConnection :: MonadIO m => WSConnection -> [Subscription] -> m ()
unsubscribeConnection wsConnection subscriptions = liftIO . atomically $ modifyTVar' sharedSubs cleanSubs
  where
    cleanSubs :: SubsMap -> SubsMap
    cleanSubs oldSubs = foldl foldFunc oldSubs subscriptions

    foldFunc :: SubsMap -> Subscription -> SubsMap
    foldFunc subsMap subscription = update searchAndRemove subscription subsMap

    searchAndRemove :: [WSConnection] -> Maybe [WSConnection]
    searchAndRemove wsConnections = Just $ filter (/= wsConnection) wsConnections

-- | Closes 'WSConnection', which is equally to remove all subscribtions for this connection.
--
closeConnection :: MonadIO m => WSConnection -> m ()
closeConnection wsConnection = liftIO . atomically $ modifyTVar' sharedSubs removeSubs
  where
    removeSubs :: SubsMap -> SubsMap
    removeSubs = fmap (filter (/= wsConnection))

-- | Get current Epoch time in nanoseconds.
--
getTimeNano :: MonadIO m => m Timestamp
getTimeNano = liftIO $ fromIntegral . toNanoSecs <$> getTime Realtime



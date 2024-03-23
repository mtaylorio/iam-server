module Lib.Command.Delete.Policy
  ( deletePolicy
  , deletePolicyOptions
  , DeletePolicy(..)
  ) where

import Control.Exception
import Data.Text
import Data.UUID
import Network.HTTP.Client
import Network.HTTP.Client.TLS
import Options.Applicative
import Servant.Client
import Text.Read

import Lib.Client.Auth
import Lib.Client.Util
import qualified Lib.Client


newtype DeletePolicy = DeletePolicy
  { deletePolicyPolicyId :: Text
  } deriving (Show)


deletePolicy :: DeletePolicy -> IO ()
deletePolicy deletePolicyInfo = do
  case readMaybe (unpack $ deletePolicyPolicyId deletePolicyInfo) of
    Just uuid -> deletePolicyByUUID uuid
    Nothing -> throw $ userError "Policy id must be a valid UUID."


deletePolicyByUUID :: UUID -> IO ()
deletePolicyByUUID polId = do
  url <- serverUrl
  auth <- clientAuthInfo
  mgr <- newManager tlsManagerSettings { managerModifyRequest = clientAuth auth }

  let polClient = Lib.Client.mkPolicyClient polId
  res <- runClientM (Lib.Client.deletePolicy polClient) $ mkClientEnv mgr url
  case res of
    Left err -> handleClientError err
    Right _ -> return ()


deletePolicyOptions :: Parser DeletePolicy
deletePolicyOptions = DeletePolicy
  <$> argument str
      ( metavar "POLICY_ID"
     <> help "The uuid of the policy to delete."
      )

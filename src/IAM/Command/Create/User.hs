{-# LANGUAGE OverloadedStrings #-}
module IAM.Command.Create.User
  ( createUser
  , createUserOptions
  , CreateUser(..)
  ) where

import Crypto.Sign.Ed25519
import Data.ByteString.Base64
import Data.Maybe
import Data.Text as T
import Data.Text.Encoding
import Data.UUID
import Data.UUID.V4
import Network.HTTP.Client
import Network.HTTP.Client.TLS
import Options.Applicative
import Servant.Client
import Text.Read

import IAM.Client.Auth
import IAM.Client.Util
import IAM.Config
import IAM.GroupIdentifier
import IAM.Policy
import IAM.User
import IAM.UserIdentifier
import qualified IAM.Client


data CreateUser = CreateUser
  { createUserUUIDOrEmail :: !(Maybe Text)
  , createUserDescription :: !(Maybe Text)
  , createUserPublicKey :: !(Maybe Text)
  , createUserPolicies :: ![Text]
  , createUserGroups :: ![Text]
  } deriving (Show)


createUser :: CreateUser -> IO ()
createUser createUserInfo =
  case createUserUUIDOrEmail createUserInfo of
    Nothing -> do
      uuid <- nextRandom
      createUserByUUID createUserInfo uuid Nothing
    Just userIdentifier ->
      case readMaybe (unpack userIdentifier) of
        Just uuid -> createUserByUUID createUserInfo uuid Nothing
        Nothing -> createUserByEmail createUserInfo userIdentifier


createUserByEmail :: CreateUser -> Text -> IO ()
createUserByEmail createUserInfo email = do
  uuid <- nextRandom
  createUserByUUID createUserInfo uuid $ Just email


createUserByUUID :: CreateUser -> UUID -> Maybe Text -> IO ()
createUserByUUID createUserInfo uuid maybeEmail = do
  let uid = UserUUID uuid
  case createUserPublicKey createUserInfo of
    Just pk -> do
      createUserById' createUserInfo uid maybeEmail pk
    Nothing -> do
      (pk, sk) <- createKeypair
      createUserById' createUserInfo uid maybeEmail $ encodeBase64 (unPublicKey pk)
      case maybeEmail of
        Just email -> printUserEmailShellVars email pk sk
        Nothing -> printUserUUIDShellVars uuid pk sk


createUserById' :: CreateUser -> UserId -> Maybe Text -> Text -> IO ()
createUserById' createUserInfo uid maybeEmail pk = do
  url <- serverUrl
  auth <- clientAuthInfo
  mgr <- newManager $ tlsManagerSettings { managerModifyRequest = clientAuth auth }
  case decodeBase64 (encodeUtf8 pk) of
    Left _ ->
      putStrLn "Invalid public key: base64 decoding failed"
    Right pk' -> do
      let upk' = upk (PublicKey pk') (createUserDescription createUserInfo)
      let gs = gid <$> createUserGroups createUserInfo
      let ps = pid <$> createUserPolicies createUserInfo
      let user = User uid maybeEmail gs ps [upk']
      let clientCommand = IAM.Client.createUser user
      result <- runClientM clientCommand $ mkClientEnv mgr url
      case result of
        Left err -> handleClientError err
        Right _ -> return ()
  where
    gid :: Text -> GroupIdentifier
    gid t = case readMaybe (unpack t) of
      Just uuid -> GroupId $ GroupUUID uuid
      Nothing -> GroupName t
    pid :: Text -> PolicyIdentifier
    pid t = case readMaybe (unpack t) of
      Just uuid -> PolicyId $ PolicyUUID uuid
      Nothing -> PolicyName t
    upk :: PublicKey -> Maybe Text -> UserPublicKey
    upk pk' = UserPublicKey pk' . fromMaybe "CLI"


createUserOptions :: Parser CreateUser
createUserOptions = CreateUser
  <$> optional ( argument str
      ( metavar "EMAIL | UUID"
     <> help "Email or UUID for user"
      ) )
  <*> optional ( argument str
      ( metavar "DESCRIPTION"
     <> help "Description for user's public key"
      ) )
  <*> optional ( strOption
      ( long "public-key"
     <> metavar "PUBLIC_KEY"
     <> help "Public key for user"
      ) )
  <*> many ( strOption
      ( long "policy"
      <> metavar "POLICY"
      <> help "Policy for user"
      ) )
  <*> many ( strOption
      ( long "group"
     <> metavar "GROUP"
     <> help "Group for user"
      ) )

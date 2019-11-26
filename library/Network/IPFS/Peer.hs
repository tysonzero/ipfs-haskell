module Network.IPFS.Peer
  ( all
  , rawList
  , connect
  , fission
  , getExternalAddress
  ) where

import qualified RIO.ByteString.Lazy as Lazy
import qualified RIO.Text            as Text
import qualified RIO.List            as List

import qualified Net.IPv4 as IPv4
import           Text.Regex

import           Network.IPFS.Prelude hiding (all)
import qualified Network.IPFS.Internal.UTF8       as UTF8

import qualified Network.IPFS.Types          as IPFS
import           Network.IPFS.Local.Class
import           Network.IPFS.Peer.Error     as IPFS.Peer
import           Network.IPFS.Peer.Types
import           Network.IPFS.Info.Types

all ::
  MonadLocalIPFS m
  => m (Either IPFS.Peer.Error [IPFS.Peer])
all = rawList <&> \case
  (ExitSuccess, allRaw, _) ->
    case UTF8.encode allRaw of
      Left  _    -> Left  <| DecodeFailure <| show allRaw
      Right text -> Right <| IPFS.Peer <$> Text.lines text

  (ExitFailure _, _, err) ->
    Left . UnknownErr <| UTF8.textShow err

rawList ::
  MonadLocalIPFS m
  => m (ExitCode, Lazy.ByteString, Lazy.ByteString)
rawList = ipfsRun ["bootstrap", "list"] ""

connect ::
  MonadLocalIPFS m
  => Peer
  -> m (Either IPFS.Peer.Error ())
connect peer@(Peer peerID) = ipfsRun ["swarm", "connect"] (UTF8.textToLazyBS peerID) >>= pure . \case
  (ExitFailure _ , _, _) -> Left <| CannotConnect peer
  (ExitSuccess   , _, _) -> Right ()

peerAddressRe :: Regex
peerAddressRe = mkRegex "^/ip[46]/([a-zA-Z0-9.:]*)/"

-- | Retrieve just the ip address from a peer address
extractIPfromPeerAddress :: String -> Maybe String
extractIPfromPeerAddress peer = matchRegex peerAddressRe peer >>= List.headMaybe

-- | True if a given peer address is externally accessable
isExternalIPv4 :: Text -> Bool
isExternalIPv4 ip = maybe False not isReserved
  where
    isReserved :: Maybe Bool
    isReserved = do
      ipAddress  <- extractIPfromPeerAddress <| Text.unpack ip
      normalized <- IPv4.decode <| Text.pack ipAddress
      return <| IPv4.reserved normalized

-- | Filter a list of peers to include only the externally accessable addresses
filterExternalPeers :: [Peer] -> [Peer]
filterExternalPeers = filter (isExternalIPv4 . peer)

-- | Get all external ipfs peer addresses
getExternalAddress ::
  MonadLocalIPFS m
  => m (Either IPFS.Peer.Error [Peer])
getExternalAddress = ipfsRun ["id"] "" >>= \case
    (ExitFailure _ , _, err) ->
      return <| Left <| UnknownErr <| UTF8.textShow err

    (ExitSuccess , rawOut, _) -> do
      rawOut
        |> decode
        |> maybe [] addresses
        |> Right . filterExternalPeers
        |> pure

fission :: Peer
fission = Peer "/ip4/3.215.160.238/tcp/4001/ipfs/QmVLEz2SxoNiFnuyLpbXsH6SvjPTrHNMU88vCQZyhgBzgw"
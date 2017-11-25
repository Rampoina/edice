module Backend.Types exposing (..)

import Tables exposing (Table)


type alias Model =
    { clientId : Maybe ClientId
    , subscribed : List Topic
    , status : ConnectionStatus
    , chatLog : List ChatLogEntry
    }


type ChatLogEntry
    = LogJoin User
    | LogLeave User
    | LogChat User String
    | LogError String


type alias ClientId =
    String


type Topic
    = Client ClientId
    | AllClients
    | Presence
    | Tables Table TopicDirection


type TopicDirection
    = ClientDirection
    | ServerDirection
    | Broadcast


type ConnectionStatus
    = Offline
    | Connecting
    | Reconnecting Int
    | Online


type ClientMessage
    = None


type AllClientsMessage
    = PresentYourself


type TableMessage
    = Join User
    | Chat User String
    | Leave User


type alias User =
    String

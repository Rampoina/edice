port module Backend exposing (..)

import String
import Http
import Navigation exposing (Location)
import Json.Decode exposing (list, string)
import Backend.Types exposing (..)
import Backend.Decoding exposing (..)
import Backend.Encoding exposing (..)
import Backend.MessageCodification exposing (..)
import Types exposing (Msg(..))
import Tables exposing (Table(..), decodeTable)
import Game.Types exposing (Player, PlayerAction(..))
import Land exposing (Color(..))
import Helpers exposing (find)


connect : Cmd msg
connect =
    mqttConnect ""


baseUrl : Location -> String
baseUrl location =
    if String.endsWith "herokuapp.com" location.hostname then
        "https://elm-dice-server.herokuapp.com"
    else
        location.protocol ++ "//" ++ location.hostname ++ ":5001"


init : Location -> Table -> ( Model, Cmd Msg )
init location table =
    ( { baseUrl = baseUrl location
      , jwt = ""
      , clientId = Nothing
      , subscribed = []
      , status = Offline
      , chatLog = []
      }
    , connect
    )


updateConnected : Types.Model -> String -> ( Types.Model, Cmd Msg )
updateConnected model clientId =
    let
        backend =
            model.backend
    in
        setStatus Subscribing ({ model | backend = { backend | clientId = Just clientId } })
            ! [ subscribe <| Client clientId
              , subscribe AllClients
              ]


updateSubscribed : Types.Model -> Topic -> ( Types.Model, Cmd Msg )
updateSubscribed model topic =
    case model.backend.clientId of
        Nothing ->
            model ! []

        Just clientId ->
            let
                model_ =
                    addSubscribed model topic

                subscribed =
                    model_.backend.subscribed
            in
                if
                    hasDuplexSubscribed
                        [ Client clientId
                        , AllClients
                        ]
                        subscribed
                        topic
                then
                    model_
                        ! [ subscribe <| Tables model_.game.table ClientDirection
                          , subscribe <| Tables model_.game.table ServerDirection
                          , subscribe <| Tables model_.game.table Broadcast
                          ]
                else
                    case topic of
                        Tables table direction ->
                            if
                                hasDuplexSubscribed
                                    [ Tables table ClientDirection
                                    , Tables table ServerDirection
                                    ]
                                    subscribed
                                    topic
                            then
                                setStatus Online model_
                                    ! [ publish <| TableMsg table <| Backend.Types.Join <| Types.getUsername model_
                                      , gameCommand model.backend model_.game.table Enter
                                      ]
                            else
                                model_ ! []

                        _ ->
                            model_ ! []


addSubscribed : Types.Model -> Topic -> Types.Model
addSubscribed model topic =
    let
        backend =
            model.backend

        subscribed =
            topic :: backend.subscribed
    in
        { model | backend = { backend | subscribed = subscribed } }


authenticate : Model -> String -> Cmd Msg
authenticate model code =
    let
        request =
            Http.post (model.baseUrl ++ "/login")
                (code |> Http.stringBody "text/plain")
            <|
                tokenDecoder
    in
        Http.send (GetToken) request


loadMe : Model -> Cmd Msg
loadMe model =
    Http.send GetProfile <|
        Http.request
            { method = "GET"
            , headers = [ Http.header "authorization" ("Bearer " ++ model.jwt) ]
            , url = (model.baseUrl ++ "/me")
            , body = Http.emptyBody
            , expect =
                Http.expectJson <| profileDecoder
            , timeout = Nothing
            , withCredentials = False
            }


gameCommand : Model -> Table -> PlayerAction -> Cmd Msg
gameCommand model table playerAction =
    Http.send (GameCommandResponse table playerAction) <|
        Http.request
            { method = "POST"
            , headers = [ Http.header "authorization" ("Bearer " ++ model.jwt) ]
            , url =
                (model.baseUrl
                    ++ "/tables/"
                    ++ (toString table)
                    ++ "/"
                    ++ (actionToString playerAction)
                )
            , body = Http.emptyBody
            , expect = Http.expectStringResponse (\_ -> Ok ())
            , timeout = Nothing
            , withCredentials = False
            }


attack : Model -> Table -> Land.Emoji -> Land.Emoji -> Cmd Msg
attack model table from to =
    Http.send (GameCommandResponse table <| Attack from to) <|
        Http.request
            { method = "POST"
            , headers = [ Http.header "authorization" ("Bearer " ++ model.jwt) ]
            , url =
                (model.baseUrl
                    ++ "/tables/"
                    ++ (toString table)
                    ++ "/Attack"
                )
            , body = Http.jsonBody <| attackEncoder from to
            , expect = Http.expectStringResponse (\_ -> Ok ())
            , timeout = Nothing
            , withCredentials = False
            }


updateChatLog : Types.Model -> ChatLogEntry -> ( Types.Model, Cmd Types.Msg )
updateChatLog model entry =
    let
        backend =
            model.backend

        chatLog =
            List.append model.backend.chatLog [ entry ]

        updated =
            { backend | chatLog = chatLog }
    in
        { model | backend = updated } ! [ scrollChat model.game.chatBoxId ]


subscriptions : Types.Model -> Sub Types.Msg
subscriptions model =
    Sub.batch
        [ mqttOnConnect StatusConnect
        , mqttOnReconnect StatusReconnect
        , mqttOnConnected Connected
        , mqttOnSubscribed <| decodeSubscribed model.backend.clientId
        , mqttOnMessage <| decodeMessage model.backend.clientId
        , onToken LoadToken
        ]


decodeSubscribed : Maybe ClientId -> String -> Msg
decodeSubscribed clientId stringTopic =
    case clientId of
        Nothing ->
            UnknownTopicMessage "no client id yet" stringTopic "-"

        Just clientId ->
            case decodeTopic clientId stringTopic of
                Just topic ->
                    Subscribed topic

                Nothing ->
                    UnknownTopicMessage "unknown topic" stringTopic "*subscribed"


decodeMessage : Maybe ClientId -> ( String, String ) -> Msg
decodeMessage clientId ( stringTopic, message ) =
    case clientId of
        Nothing ->
            UnknownTopicMessage "no client id yet" stringTopic "-"

        Just clientId ->
            case decodeTopic clientId stringTopic of
                Just topic ->
                    case decodeTopicMessage topic message of
                        Ok msg ->
                            msg

                        Err err ->
                            UnknownTopicMessage err stringTopic message

                Nothing ->
                    UnknownTopicMessage "unrecognized topic" stringTopic message


decodeTopic : ClientId -> String -> Maybe Topic
decodeTopic clientId string =
    if string == "clients/" ++ clientId then
        Just <| Client clientId
    else if String.startsWith "tables/" string then
        let
            parts =
                String.split "/" string |> List.drop 1

            tableName =
                List.head parts

            direction =
                parts |> List.drop 1 |> List.head
        in
            case tableName of
                Nothing ->
                    Nothing

                Just tableName ->
                    case decodeTable tableName of
                        Nothing ->
                            Nothing

                        Just table ->
                            case direction of
                                Nothing ->
                                    Nothing

                                Just direction ->
                                    case decodeDirection direction of
                                        Nothing ->
                                            Nothing

                                        Just direction ->
                                            Just <| Tables table direction
    else
        case string of
            "clients" ->
                Just AllClients

            _ ->
                let
                    _ =
                        Debug.log "Cannot decode topic" string
                in
                    Nothing


decodeDirection : String -> Maybe TopicDirection
decodeDirection string =
    case string of
        "clients" ->
            Just ClientDirection

        "server" ->
            Just ServerDirection

        "broadcast" ->
            Just Broadcast

        _ ->
            Nothing


setStatus : ConnectionStatus -> Types.Model -> Types.Model
setStatus status model =
    let
        backend =
            model.backend
    in
        { model | backend = { backend | status = status } }


hasDuplexSubscribed : List Topic -> List Topic -> Topic -> Bool
hasDuplexSubscribed topics subscribed topic =
    List.member topic topics
        && List.all (flip List.member <| subscribed) topics


port mqttConnect : String -> Cmd msg


publish : Msg -> Cmd msg
publish message =
    encodeTopicMessage message |> Debug.log "publish" |> mqttPublish


port mqttPublish : ( String, String ) -> Cmd msg


subscribe : Topic -> Cmd msg
subscribe topic =
    mqttSubscribe <| encodeTopic topic


actionToString : PlayerAction -> String
actionToString action =
    case action of
        Attack a b ->
            "Attack"

        _ ->
            toString action


toRollLog : Types.Model -> Game.Types.Roll -> Backend.Types.RollLog
toRollLog model roll =
    let
        lands =
            model.game.board.map.lands

        players =
            model.game.players

        attackerLand =
            find (\l -> l.emoji == roll.from.emoji) lands

        defenderLand =
            find (\l -> l.emoji == roll.to.emoji) lands

        neutralPlayer =
            { id = ""
            , name = "Neutral"
            , picture = ""
            , color = Land.Neutral
            }

        errorPlayer =
            { id = ""
            , name = "(⚠ unknown player)"
            , picture = ""
            , color = Land.Neutral
            }

        attacker =
            case attackerLand of
                Just land ->
                    if land.color == Land.Neutral then
                        Just neutralPlayer
                    else
                        find (\p -> p.color == land.color) players

                Nothing ->
                    Nothing

        defender =
            case defenderLand of
                Just land ->
                    if land.color == Land.Neutral then
                        Just neutralPlayer
                    else
                        find (\p -> p.color == land.color) players

                Nothing ->
                    Nothing
    in
        { attacker = Maybe.withDefault errorPlayer attacker |> .name
        , defender = Maybe.withDefault errorPlayer defender |> .name
        , attackRoll = List.sum roll.from.roll
        , attackDiesEmojis = toDiesEmojis roll.from.roll
        , defendRoll = List.sum roll.to.roll
        , defendDiesEmojis = toDiesEmojis roll.to.roll
        , success = List.sum roll.from.roll > List.sum roll.to.roll
        }


toDiesEmojis : List Int -> String
toDiesEmojis list =
    List.foldl (++) "" <| List.map toDie list


toDie : Int -> String
toDie face =
    case face of
        1 ->
            "⚀"

        2 ->
            "⚁"

        3 ->
            "⚂"

        4 ->
            "⚃"

        5 ->
            "⚄"

        6 ->
            "⚅"

        _ ->
            "🎲"


port onToken : (String -> msg) -> Sub msg


port mqttSubscribe : String -> Cmd msg


port mqttOnConnect : (String -> msg) -> Sub msg


port mqttOnReconnect : (Int -> msg) -> Sub msg


port mqttOnOffline : (String -> msg) -> Sub msg


port mqttOnConnected : (String -> msg) -> Sub msg


port mqttOnSubscribed : (String -> msg) -> Sub msg


port mqttOnMessage : (( String, String ) -> msg) -> Sub msg


port scrollChat : String -> Cmd msg

port module Edice exposing (..)

import Task
import Maybe
import Navigation exposing (Location)
import Routing exposing (parseLocation, navigateTo)
import Html
import Html.Lazy
import Html.Attributes
import Time
import Material
import Material.Layout as Layout
import Material.Icon as Icon
import Material.Options
import Types exposing (..)
import Game.Types exposing (PlayerAction(..))
import Game.State
import Game.View
import Game.Chat
import Board
import Board.Types
import Static.View
import Editor.Editor
import MyProfile.MyProfile
import Backend
import Backend.HttpCommands exposing (gameCommand, authenticate, loadMe, loadGlobalSettings)
import Backend.Types exposing (TableMessage(..), TopicDirection(..), ConnectionStatus(..))
import Tables exposing (Table(..), tableList)
import MyOauth
import Snackbar exposing (toast)


type alias Flags =
    { isTelegram : Bool
    }


main : Program Flags Model Msg
main =
    Navigation.programWithFlags OnLocationChange
        { init = init
        , view = view
        , update = updateWrapper
        , subscriptions = subscriptions
        }


init : Flags -> Location -> ( Model, Cmd Msg )
init flags location =
    let
        route =
            Routing.parseLocation location

        table =
            Maybe.withDefault Melchor <| currentTable route

        ( game, gameCmd ) =
            Game.State.init Nothing table

        ( editor, editorCmd ) =
            Editor.Editor.init

        ( backend, backendCmd ) =
            Backend.init location table

        ( oauth, oauthCmds ) =
            MyOauth.init location

        ( backend_, routeCmds ) =
            case route of
                TokenRoute token ->
                    let
                        backend_ =
                            { backend | jwt = token }
                    in
                        ( backend_
                        , [ auth [ token ]
                          , loadMe backend_
                          , navigateTo <| GameRoute Melchor
                          ]
                        )

                _ ->
                    ( backend, [ Cmd.none ] )

        model =
            { route = route
            , mdl = Material.model
            , oauth = oauth
            , game = game
            , editor = editor
            , myProfile = { name = Nothing }
            , backend = backend_
            , user = Types.Anonymous
            , tableList = []
            , time = 0
            , snackbar = Snackbar.init
            , isTelegram = flags.isTelegram
            }

        cmds =
            Cmd.batch <|
                List.concat
                    [ routeCmds
                    , [ gameCmd ]
                    , [ hide "peekaboo"
                      , Cmd.map EditorMsg editorCmd
                      , backendCmd
                      ]
                    , oauthCmds
                    , [ loadGlobalSettings backend ]
                    ]
    in
        ( model, cmds )


updateWrapper : Msg -> Model -> ( Model, Cmd Msg )
updateWrapper msg model =
    let
        ( model_, cmd ) =
            update msg model
    in
        ( model_, cmd )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Nop ->
            model ! []

        EditorMsg msg ->
            let
                ( editor, editorCmd ) =
                    Editor.Editor.update msg model.editor
            in
                ( { model | editor = editor }, Cmd.map EditorMsg editorCmd )

        MyProfileMsg msg ->
            MyProfile.MyProfile.update model msg

        GetGlobalSettings res ->
            case res of
                Err err ->
                    let
                        _ =
                            Debug.log "gloal settings error" err
                    in
                        toast model <| "Could not load global configuration!"

                Ok ( settings, tables ) ->
                    let
                        game =
                            model.game

                        game_ =
                            Game.State.updateGameInfo model.game tables
                    in
                        { model | tableList = tables, game = game_ } ! []

        GetToken res ->
            case res of
                Err err ->
                    let
                        oauth =
                            model.oauth

                        oauth_ =
                            { oauth | error = Just "unable to fetch user profile ¯\\_(ツ)_/¯" }
                    in
                        toast { model | oauth = oauth_ } <| "Could not load profile"

                Ok token ->
                    let
                        backend =
                            model.backend

                        backend_ =
                            { backend | jwt = token }
                    in
                        { model | backend = backend_ }
                            ! [ auth [ token ]
                              , loadMe backend_
                              ]

        GetProfile res ->
            let
                oauth =
                    model.oauth

                backend =
                    model.backend
            in
                case res of
                    Err err ->
                        let
                            oauth_ =
                                { oauth | error = Just "unable to fetch user profile ¯\\_(ツ)_/¯" }
                        in
                            { model | oauth = oauth_ } ! []

                    Ok profile ->
                        { model | user = Logged profile } ! []

        Authorize ->
            MyOauth.authorize model

        LoadToken token ->
            let
                backend =
                    model.backend

                backend_ =
                    { backend | jwt = token }
            in
                { model | backend = backend_ }
                    ! [ loadMe backend_ ]

        Authenticate code ->
            model ! [ authenticate model.backend code ]

        Logout ->
            let
                backend =
                    model.backend

                backend_ =
                    { backend | jwt = "" }
            in
                { model | user = Anonymous, backend = backend_ }
                    ! [ auth [] ]

        NavigateTo route ->
            model ! [ navigateTo route ]

        DrawerNavigateTo route ->
            model ! msgsToCmds [ Layout.toggleDrawer Mdl, NavigateTo route ]

        OnLocationChange location ->
            let
                newRoute =
                    parseLocation location

                model_ =
                    { model | route = newRoute }
            in
                case newRoute of
                    GameRoute table ->
                        Game.State.changeTable model_ table

                    _ ->
                        model_ ! []

        Mdl msg ->
            Material.update Mdl msg model

        Snackbar snackbarMsg ->
            let
                ( snackbar_, cmd ) =
                    Snackbar.update snackbarMsg model.snackbar
            in
                { model | snackbar = snackbar_ } ! [ Cmd.map Snackbar cmd ]

        BoardMsg boardMsg ->
            let
                game =
                    model.game

                ( board, newBoardMsg ) =
                    Board.update boardMsg model.game.board

                game_ =
                    { game | board = board }

                model_ =
                    { model | game = game_ }
            in
                case boardMsg of
                    Board.Types.ClickLand land ->
                        let
                            ( model, cmd ) =
                                Game.State.clickLand model_ land
                        in
                            ( model, cmd )

                    _ ->
                        model_ ! [ Cmd.map BoardMsg newBoardMsg ]

        InputChat text ->
            let
                game =
                    model.game

                game_ =
                    { game | chatInput = text }
            in
                { model | game = game_ } ! []

        SendChat string ->
            let
                game =
                    model.game
            in
                model
                    ! [ Backend.Types.Chat (Types.getUsername model) model.game.chatInput
                            |> TableMsg model.game.table
                            |> Backend.publish
                      , Task.perform (always ClearChat) (Task.succeed ())
                      ]

        ClearChat ->
            let
                game =
                    model.game

                game_ =
                    { game | chatInput = "" }
            in
                { model | game = game_ } ! []

        GameCmd playerAction ->
            model ! [ gameCommand model.backend model.game.table playerAction ]

        GameCommandResponse table action (Ok response) ->
            Game.State.updateCommandResponse table action model

        GameCommandResponse table action (Err err) ->
            Game.State.updateChatLog model <| Game.Types.LogError <| Game.Chat.toChatError table action err

        UnknownTopicMessage error topic message ->
            let
                _ =
                    Debug.log ("Error in message: \"" ++ error ++ "\"") topic
            in
                model ! []

        StatusConnect _ ->
            (Backend.setStatus Connecting model) ! []

        StatusReconnect attemptCount ->
            (Backend.setStatus (Reconnecting attemptCount) model) ! []

        StatusOffline _ ->
            (Backend.setStatus Offline model) ! []

        Connected clientId ->
            Backend.updateConnected model clientId

        Subscribed topic ->
            Backend.updateSubscribed model topic

        ClientMsg msg ->
            model ! []

        AllClientsMsg msg ->
            case msg of
                Backend.Types.TablesInfo tables ->
                    let
                        game =
                            model.game

                        game_ =
                            Game.State.updateGameInfo model.game tables
                    in
                        { model | tableList = tables, game = game_ } ! []

        TableMsg table msg ->
            Game.State.updateTable model table msg

        Tick newTime ->
            { model | time = newTime } ! []


msgsToCmds : List Msg -> List (Cmd Msg)
msgsToCmds msgs =
    List.map (\msg -> Task.perform (always msg) (Task.succeed ())) msgs


currentTable : Route -> Maybe Table
currentTable route =
    case route of
        GameRoute table ->
            Just table

        _ ->
            Nothing


type alias Mdl =
    Material.Model


lazyList : (a -> List (Html.Html Msg)) -> a -> List (Html.Html Msg)
lazyList view =
    Html.Lazy.lazy (\model -> Html.div [] (view model)) >> (\html -> [ html ])


view : Model -> Html.Html Msg
view model =
    Layout.render Mdl
        model.mdl
        [ Layout.fixedHeader, Layout.scrolling ]
        { header =
            (if not model.isTelegram then
                (lazyList header) model
             else
                []
            )
        , drawer =
            (if not model.isTelegram then
                (lazyList drawer) model
             else
                []
            )
        , tabs = ( [], [] )
        , main =
            [ Html.div [ Html.Attributes.class "Main" ] [ mainView model ]
            , Snackbar.view model.snackbar |> Html.map Snackbar
            ]
        }


header : Model -> List (Html.Html Msg)
header model =
    [ Layout.row
        [ Material.Options.cs "header" ]
        [ Layout.title [] [ Html.text "¡Qué Dice!" ]
        , Layout.spacer
        , Layout.navigation []
            [ Layout.link
                [ Material.Options.cs "header--profile-link"
                , Material.Options.onClick <|
                    case model.user of
                        Anonymous ->
                            Authorize

                        Logged _ ->
                            Logout
                ]
                (case model.user of
                    Logged user ->
                        [ Html.div [] [ Html.text <| user.name ]
                        , Html.img [ Html.Attributes.src user.picture ] []
                        ]

                    Anonymous ->
                        [ Icon.i "account_circle" ]
                )
            ]
        ]
    ]


drawer : Model -> List (Html.Html Msg)
drawer model =
    [ Layout.title [] [ Html.text "¡Qué Dice!" ]
    , Layout.navigation []
        (List.map
            (\( label, path ) ->
                Layout.link
                    [ {- Layout.href <| "#" ++ path, -} Material.Options.onClick <| DrawerNavigateTo path ]
                    [ Html.text label ]
            )
            [ ( "Play", GameRoute Melchor )
            , ( "My profile", MyProfileRoute )
            , ( "Help", StaticPageRoute Help )
            , ( "About", StaticPageRoute About )
            , ( "Editor (experimental)", EditorRoute )
            ]
        )
    ]


mainView : Model -> Html.Html Msg
mainView model =
    case model.route of
        GameRoute table ->
            Game.View.view model

        StaticPageRoute page ->
            Static.View.view model page

        EditorRoute ->
            Editor.Editor.view model

        NotFoundRoute ->
            Html.text "404"

        MyProfileRoute ->
            case model.user of
                Anonymous ->
                    Html.text "404"

                Logged user ->
                    MyProfile.MyProfile.view model user

        TokenRoute token ->
            Html.text "Getting user ready..."


mainViewSubscriptions : Model -> Sub Msg
mainViewSubscriptions model =
    case model.route of
        -- EditorRoute ->
        --     Editor.Editor.subscriptions model.editor |> Sub.map EditorMsg
        _ ->
            Sub.none


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ mainViewSubscriptions model
        , Backend.subscriptions model
        , Time.every (25) Tick
        ]


port hide : String -> Cmd msg


port auth : List String -> Cmd msg

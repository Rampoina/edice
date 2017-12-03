module MyOauth exposing (..)

import Http
import Navigation
import Json.Decode as Json
import OAuth
import OAuth.Implicit
import Types exposing (MyOAuthModel, Msg(..), LoggedUser)


profileEndpoint : String
profileEndpoint =
    "https://www.googleapis.com/oauth2/v1/userinfo"


authorizationEndpoint : String
authorizationEndpoint =
    "https://accounts.google.com/o/oauth2/v2/auth"


init : Navigation.Location -> ( MyOAuthModel, List (Cmd Msg) )
init location =
    let
        oauth =
            { clientId = "1000163928607-54qf4s6gf7ukjoevlkfpdetepm59176n.apps.googleusercontent.com"
            , redirectUri = location.origin ++ location.pathname
            , error = Nothing
            , token = Nothing
            }
    in
        case OAuth.Implicit.parse location of
            Ok { token } ->
                let
                    req =
                        Http.request
                            { method = "GET"
                            , body = Http.emptyBody
                            , headers = OAuth.use token []
                            , withCredentials = False
                            , url = profileEndpoint
                            , expect = Http.expectJson profileDecoder
                            , timeout = Nothing
                            }
                in
                    ( ({ oauth | token = Just token })
                    , [ Navigation.modifyUrl oauth.redirectUri
                      , Http.send GetProfile req
                      ]
                    )

            Err (OAuth.Empty) ->
                ( oauth, [] )

            Err (OAuth.OAuthErr err) ->
                ( { oauth | error = Just <| OAuth.showErrCode err.error }
                , [ Navigation.modifyUrl oauth.redirectUri ]
                )

            Err _ ->
                ( { oauth | error = Just "parsing error" }, [] )


profileDecoder : Json.Decoder LoggedUser
profileDecoder =
    Json.map3 LoggedUser
        (Json.field "email" Json.string)
        (Json.field "name" Json.string)
        (Json.field "picture" Json.string)


authorize model =
    model
        ! [ OAuth.Implicit.authorize
                { clientId = model.oauth.clientId
                , redirectUri = model.oauth.redirectUri
                , responseType = OAuth.Token
                , scope = [ "email", "profile" ]
                , state = Nothing
                , url = authorizationEndpoint
                }
          ]
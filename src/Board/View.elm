module Board.View exposing (view)

import String
import Board.Types exposing (..)
import Board.Colors
import Svg exposing (..)
import Svg.Attributes exposing (..)
import Svg.Events exposing (..)
import Html
import Html.Attributes
import Html.Lazy
import Board.Types exposing (Msg, Model, PathCache)
import Land exposing (Land, Map, Point, Layout, cellCenter, landCenter)


view : Model -> Html.Html Msg
view model =
    board
        model.map
        model.pathCache
        (case model.move of
            Idle ->
                []

            From land ->
                [ land ]

            FromTo from to ->
                [ from, to ]
        )
        model.hovered


board : Land.Map -> PathCache -> List Land -> Maybe Land -> Svg Msg
board map pathCache selected hovered =
    let
        ( layout, sWidth, sHeight ) =
            getLayout map

        landF =
            Html.Lazy.lazy <| landElement layout pathCache selected hovered
    in
        Html.div [ class "edBoard" ]
            [ Svg.svg
                [ width "100%"
                , height "100%"
                , viewBox ("0 0 " ++ sWidth ++ " " ++ sHeight)
                , preserveAspectRatio "none"
                , class "edBoard--svg"
                ]
                (List.concat
                    [ List.map landF map.lands
                    , [ Svg.defs []
                            [ Svg.radialGradient [ id "editorGradient" ]
                                [ Svg.stop [ offset "0.8", stopColor "gold" ] []
                                , Svg.stop [ offset "0.9", stopColor (landColor False False Land.Neutral) ] []
                                ]
                            , Svg.radialGradient [ id "selectedGradient" ]
                                [ Svg.stop [ offset "0.8", stopColor "gold" ] []
                                , Svg.stop [ offset "0.9", stopColor ("rgba(0,0,0,0)") ] []
                                ]
                            ]
                      , Svg.defs []
                            [ Svg.filter [ id "dropshadow", filterUnits "userSpaceOnUse", colorInterpolationFilters "sRGB" ]
                                [ Svg.feComponentTransfer [ Html.Attributes.attribute "in" "SourceAlpha" ]
                                    [ Svg.feFuncR [ Svg.Attributes.type_ "discrete", tableValues "0" ] []
                                    , Svg.feFuncG [ Svg.Attributes.type_ "discrete", tableValues "0" ] []
                                    , Svg.feFuncB [ Svg.Attributes.type_ "discrete", tableValues "0" ] []
                                    ]
                                , Svg.feGaussianBlur [ stdDeviation "1" ] []
                                , Svg.feOffset [ dx "0", dy "0", result "shadow" ] []
                                , Svg.feComposite [ Html.Attributes.attribute "in" "SourceGraphic", in2 "shadow", operator "over" ] []
                                ]
                            ]
                      ]
                    ]
                )
            ]


landElement : Layout -> PathCache -> List Land.Land -> Maybe Land -> Land.Land -> Svg Msg
landElement layout pathCache selected hovered land =
    let
        isSelected =
            List.member land selected

        isHovered =
            case hovered of
                Just l ->
                    l == land

                Nothing ->
                    False
    in
        g
            [ onClick (ClickLand land)
            , onMouseOver (HoverLand land)
            , onMouseOut (UnHoverLand land)
            ]
            [ polygon (polygonAttrs layout pathCache isSelected isHovered land) []
            , landDies layout land
            , landText layout land
            ]


polygonAttrs : Layout -> PathCache -> Bool -> Bool -> Land.Land -> List (Svg.Attribute Msg)
polygonAttrs layout pathCache selected hovered land =
    [ fill <| landColor selected hovered land.color
    , stroke "black"
    , strokeLinejoin "round"
    , strokeWidth (1 |> toString)
    , Html.Attributes.attribute "vector-effect" "non-scaling-stroke"
    , points <| pathCache layout land
    , class "edLand"
    ]


landDies : Layout -> Land.Land -> Svg Msg
landDies layout land =
    g [ color <| landColor False False land.color ] <|
        List.map
            (landDie
                (landCenter
                    layout
                    land.cells
                )
                land.points
            )
        <|
            List.range
                0
                (land.points - 1)


landDie : ( Float, Float ) -> Int -> Int -> Svg Msg
landDie ( cx, cy ) points index =
    let
        xOffset =
            if index >= 4 then
                1.0
            else
                2.75

        yOffset =
            if index >= 4 then
                1.15
            else
                1.5
    in
        --die
        --(toString <| cx - xOffset)
        --(toString <| cy - yOffset - (toFloat (index % 4) * 1.8))
        Svg.image
            [ x <| toString <| cx - xOffset
            , y <| toString <| cy - yOffset - (toFloat (index % 4) * 1.8)
            , textAnchor "middle"
            , alignmentBaseline "central"
            , class "edBoard--dies"
            , xlinkHref "die.svg"
            , height "3"
            , width "3"
            ]
            []


landText : Layout -> Land.Land -> Svg Msg
landText layout land =
    landCenter layout land.cells
        |> (\c ->
                let
                    ( cx, cy ) =
                        c
                in
                    g
                        [ transform <|
                            "translate("
                                ++ (toString <| cx - 1.75)
                                ++ ","
                                ++ (toString <| cy + 0.5)
                                ++ ")"
                          --x <| toString cx
                          --, y <| toString cy
                        ]
                        [ Svg.text_
                            [ textAnchor "middle"
                            , alignmentBaseline "central"
                            , class "edBoard--emoji"
                            ]
                            [ Html.text land.emoji ]
                        ]
           )


landColor : Bool -> Bool -> Land.Color -> String
landColor selected hovered color =
    case color of
        Land.EditorSelected ->
            "url(#editorGradient)"

        _ ->
            Board.Colors.base color
                |> (if selected then
                        Board.Colors.highlight
                    else
                        identity
                   )
                |> (if hovered then
                        Board.Colors.hover
                    else
                        identity
                   )
                |> Board.Colors.cssRgb

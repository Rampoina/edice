port module Helpers exposing (..)


port consoleDebug : String -> Cmd msg


port playSound : String -> Cmd msg


port setFavicon : String -> Cmd msg


findIndex : (a -> Bool) -> List a -> Int
findIndex f lst =
    findIndex_ lst f 0


findIndex_ : List a -> (a -> Bool) -> Int -> Int
findIndex_ lst f offset =
    case lst of
        [] ->
            -1

        x :: xs ->
            if f x then
                offset
            else
                findIndex_ xs f (offset + 1)


indexOf : a -> List a -> Int
indexOf a =
    findIndex <| (==) a


find : (a -> Bool) -> List a -> Maybe a
find f lst =
    List.filter f lst |> List.head


pipeUpdates : (a -> b -> ( a, Cmd c )) -> b -> ( a, Cmd c ) -> ( a, Cmd c )
pipeUpdates updater arg ( model, cmd ) =
    let
        ( model_, cmd_ ) =
            updater model arg
    in
        ( model_, Cmd.batch [ cmd, cmd_ ] )

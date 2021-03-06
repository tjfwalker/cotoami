module App.Views.Traversals exposing (..)

import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed
import Exts.Maybe exposing (isJust)
import Utils.UpdateUtil exposing (..)
import Utils.EventUtil exposing (onClickWithoutPropagation, onLinkButtonClick)
import Utils.HtmlUtil exposing (faIcon, materialIcon)
import App.Markdown
import App.Types.Coto exposing (Coto, CotoId, ElementId, Cotonoma, CotoSelection)
import App.Types.Connection exposing (Connection, InboundConnection, Reordering(..))
import App.Types.Graph exposing (Graph)
import App.Types.Traversal exposing (..)
import App.Submodels.Context exposing (Context)
import App.Submodels.Traversals
import App.Messages as AppMsg exposing (..)
import App.Views.TraversalsMsg as TraversalsMsg exposing (Msg(..))
import App.Views.ViewSwitchMsg exposing (ActiveView(..))
import App.Views.Coto
import App.Views.Reorder


type alias UpdateModel a =
    App.Submodels.Traversals.Traversals a


update : Context a -> TraversalsMsg.Msg -> UpdateModel b -> ( UpdateModel b, Cmd AppMsg.Msg )
update context msg ({ traversals } as model) =
    case msg of
        Traverse traversal nextCotoId stepIndex ->
            { model
                | traversals =
                    App.Types.Traversal.updateTraversal
                        traversal.start
                        (App.Types.Traversal.traverse stepIndex nextCotoId traversal)
                        traversals
            }
                |> withoutCmd

        TraverseToParent traversal parentId ->
            { model
                | traversals =
                    App.Types.Traversal.updateTraversal
                        traversal.start
                        (App.Types.Traversal.traverseToParent context.graph parentId traversal)
                        traversals
            }
                |> withoutCmd

        CloseTraversal cotoId ->
            { model | traversals = App.Types.Traversal.closeTraversal cotoId traversals }
                |> withoutCmd

        SwitchTraversal index ->
            { model | traversals = App.Types.Traversal.setActiveIndexOnMobile index traversals }
                |> withoutCmd


type alias ViewModel model =
    { model
        | activeView : ActiveView
        , traversals : Traversals
    }


view : Context a -> ViewModel model -> List (Html AppMsg.Msg)
view context ({ traversals } as model) =
    traversals.order
        |> List.filterMap
            (\cotoId ->
                Dict.get cotoId traversals.entries
                    |> Maybe.andThen
                        (\traversal ->
                            maybeTraversalDiv context traversal
                        )
            )
        |> List.reverse
        |> List.indexedMap
            (\index traversalDiv ->
                let
                    active =
                        (model.activeView == TraversalsView)
                            && (isActiveIndex index traversals)
                in
                    div
                        [ classList
                            [ ( "main-column", True )
                            , ( "main-traversal", True )
                            , ( "main-traversal-" ++ (toString index), True )
                            , ( "active-in-narrow-viewport", active )
                            , ( "animated", active )
                            , ( "fadeIn", active )
                            , ( "not-in-active-page", not (isActiveIndex index traversals) )
                            ]
                        ]
                        [ traversalDiv ]
            )
        |> (::) (traversalsPaginationDiv context.graph traversals)


maybeTraversalDiv : Context a -> Traversal -> Maybe (Html AppMsg.Msg)
maybeTraversalDiv context traversal =
    Dict.get traversal.start context.graph.cotos
        |> Maybe.map
            (\startCoto ->
                traversalDiv
                    context
                    traversal
                    (Dict.get startCoto.id context.graph.connections
                        |> Maybe.withDefault []
                    )
                    startCoto
            )


type alias TraversalStep =
    { traversal : Traversal
    , index : Int
    , cotoId : CotoId
    }


getElementId : TraversalStep -> String
getElementId step =
    "traversal-" ++ step.traversal.start ++ "-step-" ++ (toString step.index)


traversalDiv : Context a -> Traversal -> List Connection -> Coto -> Html AppMsg.Msg
traversalDiv context traversal connections startCoto =
    div [ class "traversal" ]
        [ div
            [ class "column-header" ]
            [ span [ class "description" ] [ faIcon "sitemap" Nothing ]
            , a
                [ class "tool-button close-traversal"
                , href "/"
                , onLinkButtonClick (AppMsg.TraversalsMsg (CloseTraversal traversal.start))
                ]
                [ materialIcon "close" Nothing ]
            ]
        , div
            [ class "column-body" ]
            [ div [ class "traversal-start" ]
                [ parentsDiv context.graph traversal startCoto.id
                , stepCotoDiv
                    context
                    connections
                    (TraversalStep traversal -1 startCoto.id)
                    startCoto
                ]
            , div [ class "steps" ]
                (traversal.steps
                    |> List.reverse
                    |> List.indexedMap
                        (\index codoId ->
                            stepDiv context (TraversalStep traversal index codoId)
                        )
                    |> List.filterMap identity
                )
            ]
        ]


parentsDiv : Graph -> Traversal -> CotoId -> Html AppMsg.Msg
parentsDiv graph traversal childId =
    let
        parents =
            App.Types.Graph.getParents childId graph
    in
        if List.isEmpty parents then
            div [] []
        else
            div [ class "parents-of-start" ]
                [ div [ class "parents" ]
                    (List.map
                        (\parent ->
                            div
                                [ class "parent"
                                , onClick
                                    (AppMsg.TraversalsMsg
                                        (TraverseToParent traversal parent.id)
                                    )
                                ]
                                [ text (App.Views.Coto.abbreviate parent) ]
                        )
                        parents
                    )
                , div
                    [ class "arrow" ]
                    [ materialIcon "arrow_downward" Nothing ]
                ]


stepCotoDiv : Context a -> List Connection -> TraversalStep -> Coto -> Html AppMsg.Msg
stepCotoDiv context connections step coto =
    let
        elementId =
            getElementId step
    in
        div
            [ App.Views.Coto.cotoClassList context elementId (Just coto.id) []
            , onClickWithoutPropagation (CotoClick elementId coto.id)
            , onMouseEnter (CotoMouseEnter elementId coto.id)
            , onMouseLeave (CotoMouseLeave elementId coto.id)
            ]
            [ div [ class "coto-inner" ]
                [ App.Views.Coto.headerDiv context Nothing elementId coto
                , App.Views.Coto.bodyDivByCoto context Nothing elementId coto
                , div [ class "main-sub-border" ] []
                , if App.Submodels.Context.hasSubCotosInReordering elementId context then
                    App.Views.Reorder.closeButtonDiv context
                  else
                    Utils.HtmlUtil.none
                , connectionsDiv
                    context
                    step
                    elementId
                    coto
                    connections
                ]
            ]


stepDiv : Context a -> TraversalStep -> Maybe (Html AppMsg.Msg)
stepDiv context step =
    let
        connections =
            Dict.get step.cotoId context.graph.connections
                |> Maybe.withDefault []
    in
        context.graph.cotos
            |> Dict.get step.cotoId
            |> Maybe.map
                (\coto ->
                    div [ class ("step step-" ++ (toString step.index)) ]
                        [ div
                            [ class "arrow" ]
                            [ materialIcon "arrow_downward" Nothing ]
                        , stepCotoDiv context connections step coto
                        ]
                )


connectionsDiv : Context a -> TraversalStep -> ElementId -> Coto -> List Connection -> Html AppMsg.Msg
connectionsDiv context step parentElementId parentCoto connections =
    connections
        |> List.reverse
        |> List.indexedMap
            (\connIndex connection ->
                context.graph.cotos
                    |> Dict.get connection.end
                    |> Maybe.map
                        (\coto ->
                            ( connection.key
                            , div
                                [ classList
                                    [ ( "outbound-conn", True )
                                    , ( "traversed"
                                      , traversed step.index coto.id step.traversal
                                      )
                                    ]
                                ]
                                [ subCotoDiv
                                    context
                                    step
                                    parentElementId
                                    (InboundConnection
                                        (Just parentCoto)
                                        (Just parentElementId)
                                        connection
                                        (List.length connections)
                                        connIndex
                                        (App.Submodels.Context.hasSubCotosInReordering
                                            parentElementId
                                            context
                                        )
                                    )
                                    coto
                                ]
                            )
                        )
                    |> Maybe.withDefault
                        ( connection.key, div [] [] )
            )
        |> Html.Keyed.node "div" [ class "sub-cotos" ]


subCotoDiv : Context a -> TraversalStep -> ElementId -> InboundConnection -> Coto -> Html AppMsg.Msg
subCotoDiv context traversalStep parentElementId inbound coto =
    let
        elementId =
            parentElementId ++ "-" ++ coto.id

        maybeParentId =
            inbound.parent |> Maybe.map (\parent -> parent.id)
    in
        div
            [ App.Views.Coto.cotoClassList context elementId (Just coto.id) []
            , onClickWithoutPropagation (CotoClick elementId coto.id)
            , onMouseEnter (CotoMouseEnter elementId coto.id)
            , onMouseLeave (CotoMouseLeave elementId coto.id)
            ]
            [ div
                [ class "coto-inner" ]
                [ App.Views.Coto.headerDiv context (Just inbound) elementId coto
                , App.Views.Coto.parentsDiv context.graph maybeParentId coto.id
                , div [ class "sub-coto-body" ]
                    [ App.Views.Coto.bodyDivByCoto context (Just inbound) elementId coto
                    , traverseButtonDiv context.graph traversalStep coto
                    ]
                ]
            ]


traversalsPaginationDiv : Graph -> Traversals -> Html AppMsg.Msg
traversalsPaginationDiv graph model =
    if App.Types.Traversal.isEmpty model then
        div [] []
    else
        model.order
            |> List.reverse
            |> List.indexedMap
                (\index cotoId ->
                    let
                        defaultPageLabel =
                            toString (index + 1)

                        pageLabel =
                            App.Types.Graph.getCoto cotoId graph
                                |> Maybe.map (toPageLabel defaultPageLabel)
                                |> Maybe.withDefault defaultPageLabel
                    in
                        div [ class "button-container" ]
                            [ button
                                [ class "button"
                                , disabled (model.activeIndexOnMobile == index)
                                , onClickWithoutPropagation
                                    (AppMsg.TraversalsMsg (SwitchTraversal index))
                                ]
                                [ text pageLabel ]
                            ]
                )
            |> div [ id "traversals-pagination" ]


toPageLabel : String -> Coto -> String
toPageLabel defaultLabel { content, summary } =
    summary
        |> Maybe.withDefault
            (App.Markdown.extractTextFromMarkdown content
                |> List.head
                |> Maybe.withDefault defaultLabel
            )
        |> (String.left 8)


traverseButtonDiv : Graph -> TraversalStep -> Coto -> Html AppMsg.Msg
traverseButtonDiv graph { traversal, index } coto =
    div [ class "sub-cotos-button" ]
        [ if isJust coto.asCotonoma then
            openTraversalButton coto.id
          else if App.Types.Graph.hasChildren coto.id graph then
            a
                [ class "tool-button traverse"
                , onLinkButtonClick
                    (AppMsg.TraversalsMsg (Traverse traversal coto.id index))
                ]
                [ materialIcon "arrow_downward" Nothing ]
          else
            Utils.HtmlUtil.none
        ]


openTraversalButton : CotoId -> Html AppMsg.Msg
openTraversalButton cotoId =
    a
        [ class "tool-button open-traversal"
        , onLinkButtonClick (OpenTraversal cotoId)
        ]
        [ materialIcon "arrow_forward" Nothing ]

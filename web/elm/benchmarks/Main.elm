module Main exposing (main)

import Benchmark
import Benchmark.Runner exposing (BenchmarkProgram, program)
import Concourse
import Concourse.BuildStatus
import Dashboard.DashboardPreview as DP
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes exposing (attribute, class, classList, href)
import Routes


main : BenchmarkProgram
main =
    program <|
        Benchmark.compare "view"
            "with topological sort"
            (\_ -> DP.view sampleJobs)
            "straight recursion"
            (\_ -> view sampleJobs)


sampleJob : String -> List String -> Concourse.Job
sampleJob name passed =
    { pipeline = pipelineId
    , name = name
    , pipelineName = "pipeline"
    , teamName = "team"
    , nextBuild = Nothing
    , finishedBuild = Nothing
    , transitionBuild = Nothing
    , paused = False
    , disableManualTrigger = False
    , inputs =
        [ { name = "input"
          , resource = "resource"
          , passed = passed
          , trigger = True
          }
        ]
    , outputs = []
    , groups = []
    }


sampleJobs : List Concourse.Job
sampleJobs =
    [ sampleJob "job1" []
    , sampleJob "job2a" [ "job1" ]
    , sampleJob "job2b" [ "job1" ]
    , sampleJob "job3" [ "job2a" ]
    , sampleJob "job4" [ "job3" ]
    ]


pipelineId : Concourse.PipelineIdentifier
pipelineId =
    { pipelineName = "pipeline", teamName = "team" }


view : List Concourse.Job -> Html msg
view jobs =
    let
        groups =
            jobGroups jobs

        width =
            Dict.size groups

        height =
            Maybe.withDefault 0 <| List.maximum (List.map List.length (Dict.values groups))
    in
    Html.div
        [ classList
            [ ( "pipeline-grid", True )
            , ( "pipeline-grid-wide", width > 12 )
            , ( "pipeline-grid-tall", height > 12 )
            , ( "pipeline-grid-super-wide", width > 24 )
            , ( "pipeline-grid-super-tall", height > 24 )
            ]
        ]
    <|
        List.map
            (\js ->
                List.map viewJob js
                    |> Html.div [ class "parallel-grid" ]
            )
            (Dict.values groups)


viewJob : Concourse.Job -> Html msg
viewJob job =
    let
        jobStatus =
            case job.finishedBuild of
                Just fb ->
                    Concourse.BuildStatus.show fb.status

                Nothing ->
                    "no-builds"

        isJobRunning =
            job.nextBuild /= Nothing

        latestBuild =
            if job.nextBuild == Nothing then
                job.finishedBuild

            else
                job.nextBuild
    in
    Html.div
        [ classList
            [ ( "node " ++ jobStatus, True )
            , ( "running", isJobRunning )
            , ( "paused", job.paused )
            ]
        , attribute "data-tooltip" job.name
        ]
    <|
        case latestBuild of
            Nothing ->
                [ Html.a [ href <| Routes.toString <| Routes.jobRoute job ] [ Html.text "" ] ]

            Just build ->
                [ Html.a [ href <| Routes.toString <| Routes.buildRoute build ] [ Html.text "" ] ]


jobGroups : List Concourse.Job -> Dict Int (List Concourse.Job)
jobGroups jobs =
    let
        jobLookup =
            jobByName <| List.foldl (\job byName -> Dict.insert job.name job byName) Dict.empty jobs
    in
    Dict.foldl
        (\jobName depth byDepth ->
            Dict.update depth
                (\jobsA ->
                    Just (jobLookup jobName :: Maybe.withDefault [] jobsA)
                )
                byDepth
        )
        Dict.empty
        (jobDepths jobs Dict.empty)


jobByName : Dict String Concourse.Job -> String -> Concourse.Job
jobByName jobs job =
    case Dict.get job jobs of
        Just a ->
            a

        Nothing ->
            { pipeline = { pipelineName = "", teamName = "" }
            , name = ""
            , pipelineName = ""
            , teamName = ""
            , nextBuild = Nothing
            , finishedBuild = Nothing
            , transitionBuild = Nothing
            , paused = False
            , disableManualTrigger = False
            , inputs = []
            , outputs = []
            , groups = []
            }


jobDepths : List Concourse.Job -> Dict String Int -> Dict String Int
jobDepths jobs dict =
    case jobs of
        [] ->
            dict

        job :: otherJobs ->
            let
                passedJobs =
                    List.concatMap .passed job.inputs
            in
            case List.length passedJobs of
                0 ->
                    jobDepths otherJobs <| Dict.insert job.name 0 dict

                _ ->
                    let
                        passedJobDepths =
                            List.map (\passedJob -> Dict.get passedJob dict) passedJobs
                    in
                    if List.member Nothing passedJobDepths then
                        jobDepths (List.append otherJobs [ job ]) dict

                    else
                        let
                            depths =
                                List.map (\depth -> Maybe.withDefault 0 depth) passedJobDepths

                            maxPassedJobDepth =
                                Maybe.withDefault 0 <| List.maximum depths
                        in
                        jobDepths otherJobs <| Dict.insert job.name (maxPassedJobDepth + 1) dict

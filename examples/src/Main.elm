module Main exposing (main)

import Angle
import Axis3d
import Browser
import Camera3d
import Color exposing (Color)
import Direction3d
import Frame3d exposing (Frame3d)
import Html exposing (Html)
import Http
import Length exposing (Meters)
import Obj.Decode exposing (Decoder, ObjCoordinates)
import Pixels
import Point3d
import Scene3d
import Scene3d.Material exposing (Texture)
import Scene3d.Mesh exposing (Shadow, Textured)
import Task
import Viewpoint3d
import WebGL.Texture


meshParts : Decoder a -> Decoder a
meshParts =
    Obj.Decode.filter
        (\{ object } ->
            case object of
                Just o ->
                    List.member o
                        [ "pod_Cube.001"
                        , "Wheel.front.L_Cylinder"
                        , "Wheel.front.R_Cylinder.006"
                        , "Wheel.rear.L_Cylinder.005"
                        , "Wheel.rear.R_Cylinder.007"
                        , "lid-left_Cube.002"
                        , "right_lid_Cube.003"
                        , "swivel_Cube"
                        ]

                Nothing ->
                    False
        )


guns : Decoder a -> Decoder (List a)
guns decoder =
    [ "PlasmaTurret_Cube.010"
    , "Laser_Cube.007"
    , "Launcher_Cube.009"
    , "TeslaGun_Cube.008"
    ]
        |> List.map Obj.Decode.object
        |> List.map ((|>) decoder)
        |> Obj.Decode.combine


shadowParts : Decoder a -> Decoder a
shadowParts =
    Obj.Decode.filter
        (\{ object } ->
            case object of
                Just o ->
                    List.member o
                        [ "pod_Cube.001"
                        , "Wheel.front.L_Cylinder"
                        , "Wheel.front.R_Cylinder.006"
                        , "Wheel.rear.L_Cylinder.005"
                        , "Wheel.rear.R_Cylinder.007"
                        ]

                Nothing ->
                    False
        )


type MeshCoordinates
    = MeshCoordinates


yUpToZUpFrame : Frame3d Meters MeshCoordinates { defines : ObjCoordinates }
yUpToZUpFrame =
    Frame3d.atOrigin
        |> Frame3d.rotateAround Axis3d.x (Angle.degrees 90)


pod : Decoder { mesh : Textured MeshCoordinates, guns : List (Textured MeshCoordinates), shadow : Shadow MeshCoordinates }
pod =
    Obj.Decode.map3
        (\mesh shadow guns_ ->
            { mesh = Scene3d.Mesh.texturedFaces mesh
            , shadow = Scene3d.Mesh.shadow (Scene3d.Mesh.indexedTriangles shadow)
            , guns = List.map Scene3d.Mesh.texturedFaces guns_
            }
        )
        (meshParts (Obj.Decode.texturedFacesIn yUpToZUpFrame))
        (shadowParts (Obj.Decode.trianglesIn yUpToZUpFrame))
        (guns (Obj.Decode.texturedFacesIn yUpToZUpFrame))


type alias Model =
    { texture : Maybe (Texture Color)
    , mesh :
        Maybe
            { mesh : Textured MeshCoordinates
            , guns : List (Textured MeshCoordinates)
            , shadow : Shadow MeshCoordinates
            }
    }


type Msg
    = LoadedTexture (Result WebGL.Texture.Error (Texture Color))
    | LoadedMesh
        (Result Http.Error
            { mesh : Textured MeshCoordinates
            , guns : List (Textured MeshCoordinates)
            , shadow : Shadow MeshCoordinates
            }
        )


init : () -> ( Model, Cmd Msg )
init () =
    ( { texture = Nothing, mesh = Nothing }
    , Cmd.batch
        [ Scene3d.Material.loadWith Scene3d.Material.nearestNeighborFiltering "Pod.png"
            |> Task.attempt LoadedTexture
        , Http.get
            { url = "Pod.obj.txt"
            , expect = Obj.Decode.expectObj LoadedMesh Length.meters pod
            }
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LoadedTexture result ->
            ( { model | texture = Result.toMaybe result }, Cmd.none )

        LoadedMesh mesh ->
            ( { model | mesh = Result.toMaybe mesh }, Cmd.none )


view : Model -> Html Msg
view model =
    let
        camera =
            Camera3d.perspective
                { viewpoint =
                    Viewpoint3d.orbitZ
                        { focalPoint = Point3d.meters -0.5 0.5 0
                        , azimuth = Angle.degrees -45
                        , elevation = Angle.degrees 35
                        , distance = Length.meters 16
                        }
                , verticalFieldOfView = Angle.degrees 30
                }
    in
    case ( model.texture, model.mesh ) of
        ( Just texture, Just mesh ) ->
            Scene3d.sunny
                { upDirection = Direction3d.z
                , sunlightDirection = Direction3d.negativeZ
                , shadows = True
                , camera = camera
                , dimensions = ( Pixels.int 640, Pixels.int 640 )
                , background = Scene3d.transparentBackground
                , clipDepth = Length.meters 0.1
                , entities =
                    [ Scene3d.meshWithShadow
                        (Scene3d.Material.texturedMatte texture)
                        mesh.mesh
                        mesh.shadow
                    , case mesh.guns of
                        gun :: _ ->
                            Scene3d.mesh (Scene3d.Material.texturedMatte texture) gun

                        [] ->
                            Scene3d.nothing
                    , Scene3d.quad (Scene3d.Material.matte Color.blue)
                        (Point3d.meters -5 5 0)
                        (Point3d.meters 5 5 0)
                        (Point3d.meters 5 -5 0)
                        (Point3d.meters -5 -5 0)
                    ]
                }

        _ ->
            Html.text "Loading…"


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = always Sub.none
        }

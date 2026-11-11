shader_type spatial;
// Season-coloured (season.gdshaderinc), the see-through copy of an eye-cut
// tree or stand (326 amended (2), Client3D.eye_cut_material): faded as
// season_near.gdshader's, and not drawn within eye_cut metres of the camera.

#define NEAR
#define EYE_CUT
#include "res://client3d/season.gdshaderinc"

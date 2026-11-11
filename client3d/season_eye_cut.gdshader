shader_type spatial;
// Season-coloured (season.gdshaderinc), the border canopy (TerrainBorder,
// 326 amended): not drawn within eye_cut metres of the camera, dithered at
// its edge, so it never stands between the low camera and the player.

#define EYE_CUT
#include "res://client3d/season.gdshaderinc"

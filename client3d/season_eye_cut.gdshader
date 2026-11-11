shader_type spatial;
// Season-coloured (season.gdshaderinc), the border canopy (TerrainBorder,
// 326 amended) and the forest's trees and near stands (326 amended (2),
// Client3D.eye_cut_material): not drawn within eye_cut metres of the
// camera, dithered at its edge, so they never stand before the low camera.

#define EYE_CUT
#include "res://client3d/season.gdshaderinc"

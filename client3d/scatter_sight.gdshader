shader_type spatial;
// The soft scatter with the sight-line cut-out (decision 549 amended): swapped in by
// Client3D only while the ground hides the player (sight_cut over 0).
#define SIGHT
#include "res://client3d/scatter.gdshaderinc"

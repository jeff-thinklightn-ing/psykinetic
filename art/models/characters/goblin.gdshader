// The goblin (decision 494): its own paint, varied per goblin by instance parameters, so one
// material draws a whole raid (they batch): its skin's greens shifted (hue, saturation,
// value: skin), its gear (the paint's browns and greys: hood, wraps, leather) tinted toward a
// palette swatch (gear, its amount in .a), and one of three marks (goblin_marks.png's
// channels: a scar, cheek stripes, a red hand) drawn or none (mark, one-hot).
shader_type spatial;

#include "res://art/models/characters/goblin.gdshaderinc"

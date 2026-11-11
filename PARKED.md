# PARKED: 702 amended (3), a routed band's way out by the routes' distance field

Parked 2026-11-11 on the coordinator's ruling. The crypt's band fights to the last, as it does today. Nobody has asked for robbers who flee, the knight's quest wants them fallen, and a last man slipping out by the breach would take a kill and its loot from the player for no gain. The label was given back to tools/decision_number.sh. A future landing takes a new label.

Branch ea-field, commit 085eebcfa, built on maps' 832 take d7ba20f62 (it needs 832's breach link). monster_test passed it on 245adf5fc; 085eebcfa adds only WorldRaids.routes_if_made.

## What it does

- **The band's own way out.** Of a level's ways out, the band's own are those within Level.BAND_DOOR_TILES (3) of the regenerate block's "foes_door" arrival: the barrow's from_breach (29, 53), so the breach (31, 52). They are terrain "band_ways_out" (World.band_ways_out). A routed band fighter (Monster._pick_way_out) runs for those alone, never the temple stair (40, 1).
- **The walk.** The breach is a link, so its exit is a WorldRoutes portal whose distance field the routes already make on their pool. Public WorldRoutes.field_to(area, cell), at and down read it, server side only, never in Fields. World.way_routes is Main's, the raid groups' routes, read through WorldRaids.routes_if_made: a rout never makes them (perf's ruling: making them copies the whole world on the tick). World.way_field, field_at and way_down hand the field to a monster. _pick_way_out reads the steps where the robber stands and walks the field's cells down for the not-past-the-foe check. _escape_tick steps down it (Monster._field_step: the free neighbour nearest the way, so a body in the way is stepped round). Until the field is in, today's 1000-tile search.
- **Cornered.** The last of a pack with a band way out and no way to it fights on (Monster._fights_on_cornered at the last-of-pack line, kept NO_WAY_TICKS 10). It never takes the stair and never stands idle.

## What it measured (monster_test, barrow generation 1)

| what | cost |
|---|---|
| one rout by the field | 0.63 ms |
| six routs in one tick | 3.38 ms (the 4000-tile search: 4.05 and 21.96 ms) |
| a cornered fighter's look | 0.03 ms |
| the barrow's fields | 53 ms (unthreaded in the test; on the pool on the box) |
| today's 1000-tile search from the same cell | 3.09 ms, no way found |

The breach is 79 cells from the stair on generation 1 and 80 on generation 118, past the 1000-tile search.

## Why it does nothing today

It runs only once a band fighter can take a way out. Today none can:

- Only the "robber" row has band_fights, and no robber row has a "pack". The last-of-pack break (824, Monster._sim_tick, the `_pack_seen > 0 and alive == 0` line) needs a pack_id, so it never runs for the crypt band.
- _breaks gives a band fighter only the call run (806 amended (9)): to a mate and back, with _way_out cleared. With no mate near, it fights on.
- _heard_rout ignores a rout cry for a band fighter.

So no crypt robber ever leaves the barrow, by either way. Unpark it if a ruling ever lets the last of a band break. That would also need a "last" of the band's own, since robbers have no pack.

## To unpark

- Rebase onto main, where 832 is. The test overlaps maps' 256d854ed (_test_rout_way_out's ways_out check): keep this branch's version.
- Take a new label from the script. Rewrite the decisions paragraph's label and its "inside 702 after (2)" place.
- Run monster_test, then land.

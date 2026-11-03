"""Voice check: fixed lines that break docs/voice.md's rules. Report only.

Reads the same lines tools/voice_inventory.py lists (the game's scripts and the
levels/ data) and flags, by speaker:
  - an exclamation mark,
  - a modern word (okay, guys, awesome, ...),
  - a game word in the world's mouth (level, quest, spawn, loot, player, ...),
  - a dash in place of the house colon or semicolon,
  - an explaining gloss: a caption that says what a label means ("what you give and to
    whom", "Trust: how much they rely on you", "This shows ..."); Jeff, 2026-11-01. Checked
    in system text too, since hints and window captions are shown; not in model prompts.
Jeff's lines (quoted in lore's pages, or marked [Jeff] in docs/voice.md) are listed apart, never
to be reworded without asking him. System text (hints, admin commands, prompts
to the voice model) is skipped as best a heuristic can; a stray one is noise.

It never fails anything: exit 0 always. Not part of land.sh (decision 748).
Run: python -B tools/voice_check.py [--out PATH]   (default: print to stdout)
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_inventory as inv  # noqa: E402

MODERN = ["okay", "ok", "guys", "awesome", "team", "stress", "stressed", "hey", "hi", "hello",
          "yeah", "yep", "nope", "gonna", "wanna", "gotta", "dude", "cool", "fine-tuned",
          "random", "weird", "basically", "literally", "totally", "super", "stuff"]
GAME = ["level", "levels", "quest", "quests", "spawn", "spawns", "respawn", "loot", "looted",
        "xp", "boss", "dungeon", "player", "players", "npc", "npcs", "game", "companion",
        "companions", "owner", "buff", "aggro", "cooldown", "resurrect", "resurrected", "hp"]
# Senses of a flagged word that are the world's own.
ALLOWED = [r"\bcool (air|draft|draught|wind|water|night|of)", r"\bscare the game\b",
           r"\bhunt(s|ed)? game\b", r"\bno game\b", r"\ba game of\b", r"\bgame of\b", r"\bgame (birds?|trail)\b"]
# Functions and constants whose text is out of the world: hints, admin, the model's prompts.
SYSTEM_CONTEXT = re.compile(
    r"(_command|hint|_help|usage|admin|prompt|system_for|VOICE_|_RULES|ORDER_|_ask\(|"
    r"facts_now|sentences|hail_ask|card_words|plain_card|_errand_verbs|STANCE|situation|"
    r"server_status|screenshot|_resend_offers|_regenerate|_quests_reset|_mind_claude|_update|refusal|authenticate)", re.I)
SYSTEM_TEXT = re.compile(r"\b(launch\.bat|press|click|settings\.cfg|screenshot|restart|reconnect|F\d+)\b", re.I)
# Debug, tool and file-check text a player never reads.
CHECK_SKIP_FILES = {"entities/entity_factory.gd", "sim/curves.gd", "sim/relief.gd", "sim/world_map.gd",
                    "sim/world_routes.gd", "sim/tuning.gd", "client3d/sound_kit.gd",
                    "render/admin_panel.gd", "render/tuning_panel.gd"}
# Data keys that are prompts or rules, not lines.
DATA_SKIP = re.compile(r"(summary|words|voice|look_words|asks\.|kinds\[|_about)", re.I)

# Model prompts are never shown, so even the gloss check skips them.
PROMPT_CONTEXT = re.compile(r"(prompt|system_for|VOICE_|_RULES|ORDER_|_ask\(|facts_now|sentences|"
                            r"hail_ask|card_words|plain_card|_errand_verbs|STANCE|situation)", re.I)
GLOSS = [
    re.compile(r"^(what|how|who|whom|where|which|when) (you|they|we|it|he|she|your|the)\b", re.I),
    re.compile(r"^[A-Z][\w' -]{0,30}: (what|how|who|where|which|the (amount|number|measure)|a measure)\b"),
    re.compile(r"\b(this|it|these) (shows?|means|tells you|lists?|measures?)\b", re.I),
    re.compile(r"\b(shows|tells you) (how|what|who|where|which)\b", re.I),
]

WORD_RE = {w: re.compile(r"\b%s\b" % re.escape(w), re.I) for w in MODERN + GAME}


def problems(text):
    low = re.sub(r"\{\w+\}", "", text)  # {player}, {her}: placeholders, not words
    for pat in ALLOWED:
        low = re.sub(pat, "", low, flags=re.I)
    out = []
    if "!" in text:
        out.append("exclamation")
    hits = [w for w in MODERN if WORD_RE[w].search(low)]
    if hits:
        out.append("modern: " + ", ".join(hits))
    hits = [w for w in GAME if WORD_RE[w].search(low)]
    if hits:
        out.append("game word: " + ", ".join(hits))
    if re.search(r"\s[-\u2013\u2014]\s|\u2014", text):
        out.append("dash")
    return out


# Captions live in the windows and the HUD (render/, client/, client3d/); elsewhere a "what you..." is a prompt fragment.
GLOSS_DIRS = {"client", "client3d", "render"}
GLOSS_KEYS = re.compile(r"(caption|subtitle|legend|desc|blurb|hint|label|title)", re.I)


def gloss(text):
    return any(g.search(text) for g in GLOSS)


def looks_like_code(text):
    if text.startswith("<!--") or re.search(r"<\w[\w ]*>|\[\w[\w|<> ]*\]|\w\.json|\.png", text):
        return True
    return bool(re.search(r"\\[bdsw]|\(\?|\[\^|\|\w+\|", text)) or text.startswith("^")


def jeff_lines():
    """Quoted lines in docs/voice.md bullets marked [Jeff]."""
    out = set()
    with open(os.path.join(inv.ROOT, "docs", "voice.md"), encoding="utf-8") as f:
        text = f.read()
    for para in re.split(r"\n(?=\s*- |\s*\n)", text):
        if "[Jeff]" in para:
            for q in re.findall(r'"([^"]+)"', re.sub(r"\s+", " ", para)):
                out.add(q.strip())
    return out


def is_jeff(text, lore, jeff):
    return inv.quoted(text, lore) or text in jeff


def collect():
    lore = inv.lore_text()
    jeff = jeff_lines()
    found = []  # (speaker, where, text, problems, jeff)
    for rel in inv.gd_files():
        if rel in CHECK_SKIP_FILES:
            continue
        for f, line, ctx, text in inv.scan_gd(rel):
            if looks_like_code(text):
                continue
            system = SYSTEM_CONTEXT.search(ctx) or SYSTEM_TEXT.search(text)
            if system and PROMPT_CONTEXT.search(ctx):
                continue
            p = [] if system else problems(text)
            if rel.split("/")[0] in GLOSS_DIRS and gloss(text):
                p.append("gloss")
            if p:
                spk = inv.SPEAKER_BY_FILE.get(rel, "server and windows" if rel == "main.gd" else "other (" + rel.split("/")[0] + ")")
                found.append((spk, "%s:%d %s" % (f, line, ctx), text, p, is_jeff(text, lore, jeff)))
    for rel in inv.json_files():
        import json
        with open(os.path.join(inv.ROOT, rel), encoding="utf-8") as fh:
            try:
                data = json.load(fh)
            except ValueError:
                continue
        rows = []
        inv.walk_json(data, "", rows)
        for path, text in rows:
            if DATA_SKIP.search(path) or looks_like_code(text):
                continue
            p = problems(text)
            if GLOSS_KEYS.search(path) and gloss(text):
                p.append("gloss")
            if p:
                found.append((rel, path, text, p, is_jeff(text, lore, jeff)))
    return found


def report(found):
    out = ["# Voice check", "",
           "Report only (`python -B tools/voice_check.py`): fixed lines that break `docs/voice.md`'s",
           "rules. A heuristic: some flags are system text or a word in its world sense; voice",
           "reads each before proposing a change, and the owning tree says yes.", ""]
    jeff = [r for r in found if r[4]]
    rest = [r for r in found if not r[4]]
    kinds = {}
    for r in rest:
        for p in r[3]:
            k = p.split(":")[0]
            kinds[k] = kinds.get(k, 0) + 1
    out.append("%d lines flagged (%s); %d of them Jeff's, listed apart." % (
        len(found), ", ".join("%s %d" % kv for kv in sorted(kinds.items())) or "none", len(jeff)))
    out.append("")
    by = {}
    for r in rest:
        by.setdefault(r[0], []).append(r)
    for spk in sorted(by):
        out.append("## %s (%d)" % (spk, len(by[spk])))
        out.append("")
        for _, where, text, p, _ in by[spk]:
            out.append("- %s: \"%s\" `%s`" % ("; ".join(p), text, where))
        out.append("")
    if jeff:
        out.append("## Jeff's lines (quoted in lore's pages or marked [Jeff] in docs/voice.md; never reworded without asking him)")
        out.append("")
        for spk, where, text, p, _ in jeff:
            out.append("- %s: \"%s\" `%s`" % ("; ".join(p), text, where))
        out.append("")
    return "\n".join(out) + "\n"


def main():
    text = report(collect())
    if "--out" in sys.argv:
        path = sys.argv[sys.argv.index("--out") + 1]
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("wrote " + path)
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(text)
    sys.exit(0)


if __name__ == "__main__":
    main()

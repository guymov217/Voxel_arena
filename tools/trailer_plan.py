"""WRECKSMITH / Make it. Break it. / 75-second director's cut.

Times are editorial seconds; source anchors refer to observed gameplay events.
Keep the action at normal speed except for the two short impact ramps.
"""

LENGTH = 75.0
END_START = 70.0
# [id, in, out, direction, recording, anchor, optional speed ramp]
SHOTS = [
    [1, 0, 1.3, "Cold open: medium side view; both fighters and the full axe arc stay readable", "1", ("key", 0.65), None],
    [2, 1.3, 4, "Pull out to the fighters: keep the reaction and the next attack readable", "3", ("key", -0.65), None],
    [3, 4, 6, "Crane over the duel to establish the arena and its scale", "4", ("key", 0.65), None],
    [4, 6, 7.5, "Push into the real forge; make the building tool recognizable", "14f", ("t", 0.0), None],
    [5, 7.5, 10.5, "Three rhythmic inserts: haft, head, cutting edge; each block visibly placed", None, None, None],
    [6, 10.5, 12, "Product orbit: hold on the completed custom axe", "16", ("key", 0.0), None],
    [7, 12, 16, "Match the finished axe to the same design in hand; pull back for the blow", "17", ("key", 2.2), None],
    [8, 16, 19, "Side tracking two-shot: a fast forehand and returning backhand, with recovery", "combo", ("t", 0.35), None],
    [9, 19, 21, "Same take, tighter three-quarter camera: step in and kick; hold the recoil", "combo_close", ("t", 3.35), None],
    [10, 21, 23, "Low hammer impact; a brief slow-motion accent, then normal speed", "7", ("key", 0.65), [(-0.02, 0.45), (0.20, 0.45), (0.36, 1.0)]],
    [11, 23, 25, "Close on a real sever: show the wound and the limb's departure", "9", ("key", 0.7), None],
    [12, 25, 28, "Full bodies: the left hand grabs, the body lifts, the throw follows", "11", ("key", 0.6), None],
    [13, 28, 33, "Comedy held in one wide shot: axe sticks, a beat of hesitation, pull it free", "lodge_wide", ("key", 0.65), None],
    [14, 33, 35, "The reversal: a heavy enemy cracks the champion's armour", "20", ("key", 0.55), None],
    [15, 35, 38, "Injury has consequences: the physician treats a missing forearm", "27", ("t", 0.45), None],
    [16, 38, 40, "Hold on the fitted hook as the champion lifts it to inspect it", "27", ("key", -0.20), None],
    [17, 40, 42, "Tracking wide: walk through the yard between fights", "25", ("t", 0.6), None],
    [18, 42, 44, "Training insert: controlled attacks, preparing to return", "28", ("t", 0.35), None],
    [19, 44, 47.5, "Worm's-eye reveal: rise from the champion to the approaching cyclops", "21", ("t", 0.0), None],
    [20, 47.5, 50, "Side wide: the giant's whole swing and the champion's reaction", "22", ("key", 0.65), None],
    [21, 50, 53, "Over the shoulder: another encounter, the champion cuts at the giant's knee", "23", ("mark", "cut giant", 0.65), None],
    [22, 53, 55, "Low wide: a charging lion meets the spear and shield", "24b", ("key", 0.6), None],
    [23, 55, 57, "Three-quarter low: minotaur axe against a raised shield", "24c", ("key", 0.6), None],
    [24, 57, 60, "Wide ensemble: six fighters, three separate lanes of action", "29", ("t", 0.3), None],
    [25, 60, 62, "Low side insert: a heavy sweep takes the legs out", "10", ("key", 0.55), None],
    [26, 62, 65, "Final axe strike; short ramp at impact, preserve the follow-through", "30", ("key", 0.65), [(-0.03, 0.35), (0.28, 0.35), (0.45, 1.0)]],
    [27, 65, 67, "Victory breath: the champion stands over his fallen opponent", "32", ("key", -1.5), None],
    [28, 67, 70, "Comic button: cut from the victory pose to the lion's very different verdict", "24b", ("key", 0.9), None],
    [33, 70, 75, "Five-second end card: WRECKSMITH, Make it. Break it., optional verified CTA", None, None, None],
]
CUTS = {
    5: [["15", ("t", 1.0), 1.0], ["15", ("t", 3.2), 1.0], ["15", ("t", 5.1), 1.0]],
}
TEXT = [
    (6.2, 10.4, "MAKE IT."),
    (12.2, 15.8, "BREAK IT."),
    (21.2, 24.8, "EVERY HIT LEAVES A MARK."),
    (29.4, 32.4, "MINOR COMPLICATION."),
    (35.2, 39.8, "REBUILD YOURSELF."),
    (44.2, 47.4, "THINK BIGGER."),
]
END_LINES = ["MAKE IT. BREAK IT."]
# Set TRAILER_CTA explicitly once the store page is public. No unverified release/date claim.
END_CALL = ""
MUSIC_PLAN = [
    (0, 6, "boss2", "hard"),
    (6, 12, "forge", "mid"),
    (12, 28, "fight3", "hard"),
    (28, 33, "forge", "soft"),
    (33, 40, "yard", "soft"),
    (40, 44, "fight", "mid"),
    (44, 67, "boss2", "hard"),
    (67, 70, "yard", "soft"),
    (70, 75, "victory", "start"),
]
# Music yields to real foley in the two comic holds, and before the finale.
DROPS = [(29.1, 32.6, 0.06), (61.65, 62.65, 0.15), (67.0, 69.8, 0.04)]
# Editorial accents only; combat accents are placed on the actual recorded hits.
BOOMS = [12.0, 44.0, 70.0]
RISES = [(11.2, 12.0), (43.1, 44.0), (60.7, 62.0)]
NEEDS = {
    "1": ["KEY", "hook return"], "3": ["KEY", "hook return"], "4": ["KEY"],
    "14f": ["KEY"], "15": ["KEY"], "16": ["KEY"], "17": ["KEY"],
    "combo": ["combo first", "combo return", "combo kick"],
    "combo_close": ["combo first", "combo return", "combo kick"],
    "7": ["KEY", "down foe"], "9": ["KEY", "severed foe"],
    "11": ["KEY", "grab", "down foe"],
    "lodge_wide": ["KEY", "lodged", "free"], "20": ["KEY"],
    "27": ["KEY", "prosthetic"], "28": ["KEY"],
    "21": ["KEY"], "22": ["KEY"], "23": ["cut giant"],
    "24b": ["KEY"], "24c": ["KEY"], "29": ["KEY"],
    "10": ["KEY", "down foe"], "30": ["KEY", "down foe"], "32": ["KEY"],
}
GROUPS = [["1", "3"], ["14f", "15", "16"], ["combo", "combo_close"], ["21", "22"], ["30", "32"]]
TAKES = [11, 12, 13, 14, 15]
# Events that must occur INSIDE an edited shot, not merely somewhere in its source recording.
VISIBLE = {
    2: ["hook return"],
    8: ["combo first", "combo return"], 9: ["combo kick"],
    10: ["down foe"], 11: ["severed foe"], 12: ["grab", "down foe"],
    13: ["lodged", "free"], 15: ["prosthetic"], 21: ["cut giant"],
    25: ["down foe"], 26: ["down foe"],
}

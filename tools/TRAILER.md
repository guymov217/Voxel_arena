# WRECKSMITH — Make it. Break it.

75-second director's cut, staged and recorded inside the game. The combat engine,
character assets and damage rules are unchanged. The timeline is `tools/trailer_plan.py`.

## Run

- Windows: `tools\make_trailer75.bat`
- Other systems: `python tools/make_trailer75.py` (Godot, display, ffmpeg, numpy, Pillow).
- `--preview`: 640×360 review render. `TRAILER_FPS=60`: 60 fps delivery.
- `--plan`: print the shot list. `--audit`: headless choreography/event timing audit.
- `--shots combo`: rerecord that scene and all its matching camera angles.
- `--fake --preview`: synthetic test patterns, NOT a gameplay trailer.
- `TRAILER_CTA="WISHLIST NOW ON STEAM"`: enable only when the store page is public.

Outputs: `docs/store/trailer75.mp4`, `trailer75_clean.mp4`, `trailer75_cut.json`.
The isolated capture copy uses its own save directory. Full-quality capture uses
Forward+ at 120 fps; preview is 30 fps. Render duration depends heavily on hardware.

## Direction

Immediate physical action; reveal the forge early; match the custom weapon to its
use in combat. Keep the five-second combination at real speed and preserve screen
direction across its two cameras. Both strokes and the kick require real contacts.
The lodged-axe gag holds both bodies in a wide frame and gives foley room to breathe.
The injury/physician beat leads back to preparation, then giants and the final burst.
The victory pose is undercut by the lion; the logo remains readable for five seconds.
Different opponents/arenas are montage encounters, not a claim of one continuous fight.

## Shot list

| Shot | Seconds | Direction |
|---|---|---|
| 1 | 0–1.3 | Cold open: low side close-up; a readable wind-up and axe impact |
| 2 | 1.3–4 | Pull out to the fighters: keep the reaction and the next attack readable |
| 3 | 4–6 | Crane over the duel to establish the arena and its scale |
| 4 | 6–7.5 | Push into the real forge; make the building tool recognizable |
| 5 | 7.5–10.5 | Three rhythmic inserts: haft, head, cutting edge; each block visibly placed |
| 6 | 10.5–12 | Product orbit: hold on the completed custom axe |
| 7 | 12–16 | Match the finished axe to the same design in hand; pull back for the blow |
| 8 | 16–19 | Side tracking two-shot: a fast forehand and returning backhand, with recovery |
| 9 | 19–21 | Same take, tighter three-quarter camera: step in and kick; hold the recoil |
| 10 | 21–23 | Low hammer impact; a brief slow-motion accent, then normal speed |
| 11 | 23–25 | Close on a real sever: show the wound and the limb's departure |
| 12 | 25–28 | Full bodies: the left hand grabs, the body lifts, the throw follows |
| 13 | 28–33 | Comedy held in one wide shot: axe sticks, a beat of hesitation, pull it free |
| 14 | 33–35 | The reversal: a heavy enemy cracks the champion's armour |
| 15 | 35–38 | Injury has consequences: the physician treats a missing forearm |
| 16 | 38–40 | Hold on the fitted hook as the champion lifts it to inspect it |
| 17 | 40–42 | Tracking wide: walk through the yard between fights |
| 18 | 42–44 | Training insert: controlled attacks, preparing to return |
| 19 | 44–47.5 | Worm's-eye reveal: rise from the champion to the approaching cyclops |
| 20 | 47.5–50 | Side wide: the giant's whole swing and the champion's reaction |
| 21 | 50–53 | Over the shoulder: another encounter, the champion cuts at the giant's knee |
| 22 | 53–55 | Low wide: a charging lion meets the spear and shield |
| 23 | 55–57 | Three-quarter low: minotaur axe against a raised shield |
| 24 | 57–60 | Wide ensemble: six fighters, three separate lanes of action |
| 25 | 60–62 | Low side insert: a heavy sweep takes the legs out |
| 26 | 62–65 | Final axe strike; short ramp at impact, preserve the follow-through |
| 27 | 65–67 | Victory breath: the champion stands over his fallen opponent |
| 28 | 67–70 | Comic button: cut from the victory pose to the lion's very different verdict |
| 33 | 70–75 | Five-second end card: WRECKSMITH, Make it. Break it., optional verified CTA |

## Sound

The game's own recorded combat, exertion, crowd and forge audio stays synchronized
through speed ramps. Existing game music is arranged into nine cues, with smooth
transitions, sidechain-style ducking, two comic drops and a final ring-out. Original
procedural risers and sparse low-frequency accents support transitions. Combat
accents are mapped from observed high-energy hits through the actual edit clock;
no arbitrary impact sound is used to disguise a missed blow. Target: -14 LUFS,
-1.5 dBTP before AAC encoding. Listen on speakers and headphones before publication.
No third-party trailer music or footage is included.

## Quality gates

Missing footage, missing actions, insufficient lead-in or tail, out-of-window events,
mixed take seeds and camera-event drift stop export. No black substitutes or frozen
padding. All camera angles retry as a group. Both encodes must pass frame count,
dimensions, duration and audio-stream verification before replacing previous masters.
Cache invalidation includes game sources, native binaries, artwork, engine and capture settings.
A passed headless audit proves contacts/timing, not visual quality. Review the complete
render for occlusion, clipping, camera cuts, captions and audio before publishing.

Tests: `python -m unittest discover -s tools -p 'test_trailer*.py'` and `sh run_tests.sh`.

## References reviewed

Sampled footage from the official Steam trailers for
[Teardown](https://store.steampowered.com/app/1167630/Teardown/) and
[Half Sword](https://store.steampowered.com/app/2397300/Half_Sword/): readable physical
cause/effect, feature contrast, and alternating deliberate setup with chaotic payoff.
Editing principles: Derek Lieu's
[The Trailer Line of Rising Action](https://www.derek-lieu.com/blog/2018/9/16/the-trailer-line-of-rising-action)
and [Secrets to Trailer Sound Design](https://www.derek-lieu.com/blog/2022/1/17/secrets-to-trailer-sound-design).
Use an immediate hook, local peaks and valleys, a twist and a final button; keep sound purposeful.

## Validation in the editing workspace

Godot available here: 4.6.3 (the project targets 4.7). The 10 Python contract tests
pass. Headless takes passed for the opening, forge, combo, hammer, sever, grab,
armour, physician, yard, training, giants, lion, minotaur, melee and leg sweep.
The lodged-axe setup was corrected and its retest passed. Combo review frames were
rendered with software OpenGL; that renderer reports the existing fog shader as
unsupported, so these are framing checks, not a final Forward+ quality approval.
The full game suite was attempted and already reports failures in
`test_arms.test_a_blade_pulled_out_of_a_head_comes_free` and
`test_camera.test_in_a_fight_he_stays_solid` on the unchanged gameplay code.
It did not complete in this session. No full gameplay master is certified here.

class_name MonsterLook
## The giants of myth, not big men: the Cyclops (and Polyphemus) with the one eye in the middle
## of the brow, the Minotaur's bull head, the troll's tusks, ears and great nose, the Titan's
## bronze skin, crown and burning eyes. Only how they look: cosmetic pieces on the head (cells
## on the body's coarse grid, worn like a hat) and a repaint of the face. DOM-free.

## The look for each campaign enemy type that has one.
const LOOKS := {"cyclops": "cyclops", "giant": "cyclops", "minotaur": "minotaur", "troll": "troll", "titan": "titan"}

## Skin by look (0xRRGGBB).
const SKIN := {"cyclops": 0xb88a68, "minotaur": 0x6a4430, "troll": 0x6f8458, "titan": 0xb98a4a}

## The pieces each look wears.
const WEARS := {"cyclops": [], "minotaur": ["mon_horns", "mon_muzzle", "mon_ring"], "troll": ["mon_troll_nose", "mon_troll_ears", "mon_tusks", "mon_moss"], "titan": ["hat_crown", "beard_braided"]}

## The head is 5 wide (x), 6 high (y), 5 deep (z, the face at z = 4).
const PIECES := {
	"mon_horns": {"name": "Bull horns", "mat": "bone", "color": 0xe6d8b8, "parts": {"head": [[-1, 4, 2], [-2, 5, 2], [-3, 6, 2], [-3, 7, 3], [5, 4, 2], [6, 5, 2], [7, 6, 2], [7, 7, 3]]}},
	"mon_muzzle": {"name": "Bull muzzle", "mat": "leather", "color": 0x9a7660, "parts": {"head": [[1, 1, 5], [2, 1, 5], [3, 1, 5], [1, 2, 5], [2, 2, 5], [3, 2, 5], [2, 1, 6]]}},
	"mon_ring": {"name": "Nose ring", "mat": "gold", "color": 0xd8b040, "parts": {"head": [[2, 0, 6]]}},
	"mon_troll_nose": {"name": "Troll nose", "mat": "leather", "color": 0x5d7048, "parts": {"head": [[2, 2, 5], [2, 3, 5], [2, 2, 6]]}},
	"mon_troll_ears": {"name": "Troll ears", "mat": "leather", "color": 0x5d7048, "parts": {"head": [[-1, 3, 2], [-2, 4, 2], [5, 3, 2], [6, 4, 2]]}},
	"mon_tusks": {"name": "Tusks", "mat": "bone", "color": 0xe8e0c8, "parts": {"head": [[1, 0, 5], [3, 0, 5], [1, 1, 5], [3, 1, 5]]}},
	"mon_moss": {"name": "Moss hair", "mat": "feather", "color": 0x3e5a2a, "parts": {"head": [[1, 6, 1], [2, 6, 2], [3, 6, 1], [2, 6, 0], [0, 5, 0], [4, 5, 0]]}},
}

static func look_of(enemy_type: String) -> String:
	return LOOKS.get(enemy_type, "")

## Repaints the face for a look (the fighter is built; the head's voxels are on the fine grid,
## twice the coarse one).
static func paint_face(f, look: String) -> void:
	var head: VoxelPart = f.head
	if head == null:
		return
	var res := int(Data.body_res)
	var front := head.dims.z * res - 1
	var changed := []
	for i in head.fx.size():
		if head.fz[i] != front:
			continue
		var x: int = head.fx[i]
		var y: int = head.fy[i]
		var c = null
		match look:
			"cyclops":
				# The two eyes closed over with skin; one great eye in the middle of the brow.
				if y >= 6 and y <= 7 and (x <= 3 or x >= 6):
					c = f.skin.darkened(0.08)
				if x >= 3 and x <= 6 and y >= 5 and y <= 8:
					c = Color(0.93, 0.91, 0.84)
				if x >= 4 and x <= 5 and y >= 6 and y <= 7:
					c = Color(0.35, 0.05, 0.04)
				if x >= 2 and x <= 7 and y == 9:
					c = f.skin.darkened(0.45)   # one heavy brow over it
			"titan":
				if y >= 6 and y <= 7 and ((x >= 2 and x <= 3) or (x >= 6 and x <= 7)):
					c = Color(1.0, 0.78, 0.25)   # eyes that burn like the forge
			"minotaur":
				if y >= 6 and y <= 7 and ((x >= 2 and x <= 3) or (x >= 6 and x <= 7)):
					c = Color(0.75, 0.08, 0.05)
			"troll":
				if y >= 6 and y <= 7 and ((x >= 2 and x <= 3) or (x >= 6 and x <= 7)):
					c = Color(0.95, 0.85, 0.2)
		if c != null:
			head.colors[i] = c
			changed.append(i)
	if not changed.is_empty():
		head.refresh_colors(changed)

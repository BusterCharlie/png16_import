**16-bit PNG Import**  
*or: The Soft Machine That Remembers What Godot Forgot*

Godot’s native PNG loader is a polite, well-behaved functionary. It sees sixteen bits of reality and, with the quiet efficiency of a Ministry clerk, discards half of them. Eight bits remain. Enough for most citizens. Not enough for heightmaps. Not enough for the masks that decide who lives and who is erased.

This addon refuses the reduction.

It has no dependencies. No friends in high places. Simply drop the folder into any Godot 4.7 project and the truth remains intact: all sixteen bits, preserved like a forbidden memory.

**In the editor**  
Enable the plugin. Select a PNG. In the Import dock’s **Import As** menu you will find two new choices, two slightly different ways of looking at the same hidden data:

| Importer                      | Resource                    | Use                                |
| ----------------------------- | --------------------------- | ---------------------------------- |
| 16-bit PNG as Image (float)   | `Image`, `FORMAT_RF`        | Terrain3D `import_images`, scripts |
| 16-bit PNG as Texture (float) | `ImageTexture`, `FORMAT_RF` | shader uniforms, materials         |

Options appear like questions you are not supposed to ask:

- `normalized` — on: divide by 65535, force the world into the comfortable range 0–1. Off: keep the raw numbers, 0–65535, exact, unrepentant.  
- `scale` — applied afterward. Metres per step, or whatever unit the simulation currently pretends is real.  
- `allow_8bit` — import ordinary 8-bit PNGs as 0–1 instead of rejecting them. Mercy, or contamination? You decide.

Every other PNG continues through the official channels. Values are taken from the first channel only. The other channels are still there, of course. Watching.

**At run time**  
(Exported games too. The plugin is no longer required. The knowledge has already been absorbed.)

```gdscript
var heights: Image = Png16BitLoader.load_image("user://maps/h.png", false) # raw 0–65535 floats
var raw: Png16BitLoader.LoadResult = Png16BitLoader.load_16bit_png(path) # big-endian bytes
```

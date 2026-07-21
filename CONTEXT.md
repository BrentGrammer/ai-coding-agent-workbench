# Sonic Playground

A system for composing music from reusable musical material and transformations.

## Language

**Preview Sound**:
Required sound used when previewing a motif from the Motif Library. Defaults to Grand Piano. It does not affect phrases, voices, or the full composition.
_UI label_: Preview Sound
_Avoid_: Motif Sound (ambiguous — sounds like it orchestrates the piece)

**Sound Override**:
Optional sound on a phrase that overrides the voice sound for every motif in that phrase. Motif library sounds are ignored. None means use the voice sound.
_Avoid_: Inherit, inherited sound

**Custom Transform**:
A reusable user-authored transform definition kept in a personal registry and referenced by a stable Custom Transform ID.

**Custom Transform ID**:
A browser-generated UUID that identifies a Custom Transform within one registry. The same ID may appear in different users' registries when a composition is shared or imported.
_Avoid_: Custom ID

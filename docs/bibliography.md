# Bibliography

External datasets, papers, formats and software that Ourcraft uses, or that
were seriously considered. Each entry notes its license and status. Add new
sources in the same change that introduces them.

Status: **used** (code or data in this repository depends on it),
**considered** (evaluated, not used yet).

## Language data

**Open English WordNet, 2025 edition.** Open English Wordnet Community.
<https://en-word.net/>. JSON export:
<https://en-word.net/downloads/english-wordnet-2025-json.zip>.
License: CC-BY 4.0. Status: **used.** `tools/fetch-wordnet.sh` downloads it,
and `tools/wordnet-world.sh` builds a test world from its part-of
(meronym) relations. The data itself isn't committed.

> McCrae, J. P., Rademaker, A., Bond, F., Rudnicka, E., & Fellbaum, C.
> (2019). English WordNet 2019 – An Open-Source WordNet for English.
> *Proceedings of the 10th Global WordNet Conference (GWC 2019).*

**Princeton WordNet.** <https://wordnet.princeton.edu/>. License: WordNet
License (permissive, commercial use allowed with notice;
<https://wordnet.princeton.edu/node/10>). Status: used indirectly; Open
English WordNet is derived from it.

> Miller, G. A. (1995). WordNet: A Lexical Database for English.
> *Communications of the ACM, 38*(11), 39–41.
>
> Fellbaum, C. (Ed.). (1998). *WordNet: An Electronic Lexical Database.*
> MIT Press.

**ConceptNet 5.5.** <https://conceptnet.io/>. Common-sense relations
including PartOf and AtLocation. License: believed CC BY-SA 4.0 (not
confirmed). Status: considered, for deeper chains such as fork › kitchen ›
house.

> Speer, R., Chin, J., & Havasi, C. (2017). ConceptNet 5.5: An Open
> Multilingual Graph of General Knowledge. *Proceedings of AAAI 2017.*
> arXiv:1612.03975.

## 3D shape and scene data

**PartNet.** <https://partnet.cs.stanford.edu/>. Hierarchical part
annotations for 26,671 ShapeNet models in 24 categories. License: ShapeNet
terms, non-commercial, registration required, redistribution only to
research colleagues. Status: considered, for internal hierarchy testing.

> Mo, K., Zhu, S., Chang, A. X., Yi, L., Tripathi, S., Guibas, L. J., &
> Su, H. (2019). PartNet: A Large-scale Benchmark for Fine-grained and
> Hierarchical Part-level 3D Object Understanding. *CVPR 2019.*
>
> Chang, A. X., et al. (2015). ShapeNet: An Information-Rich 3D Model
> Repository. arXiv:1512.03012.

**CraftAssist house and segmentation data.**
<https://github.com/facebookresearch/craftassist> (archived 2021). 2,050
Minecraft houses with 1,038 sub-component labels. License: code MIT; data
license not stated. Status: considered.

> Gray, J., Srinet, K., Jernite, Y., et al. (2019). CraftAssist: A Framework
> for Dialogue-enabled Interactive Agents. arXiv:1907.08584.

**3D-FRONT and 3D-FUTURE.** Furnished houses built from a shared furniture
catalog. License: not confirmed. Status: considered.

> Fu, H., et al. (2021). 3D-FRONT: 3D Furnished Rooms with layOuts and
> semaNTics. *ICCV 2021.* arXiv:2011.09127.

**Objaverse.** 800,000+ models, dataset under ODC-BY with a per-object
Creative Commons license. There are open questions about how it was
collected and how creators are credited. Status: considered, set aside.

> Deitke, M., et al. (2023). Objaverse: A Universe of Annotated 3D Objects.
> *CVPR 2023.*

## Voxel formats and assets

**MagicaVoxel .vox format.** ephtracy,
<https://github.com/ephtracy/voxel-model>; formal description at
<https://formats.kaitai.io/magicavoxel_vox/>. Status: considered, for an
importer.

**Voxel Art pack, FuzzyManStudios.** <https://fuzzymanstudios.itch.io/voxel-art>.
363 MagicaVoxel models. License: free for commercial use and modification,
credit appreciated. Status: considered, for import testing.

## Software

**Godot Engine 4.7.** <https://godotengine.org/>. MIT. Status: **used.**

**godot-cpp.** <https://github.com/godotengine/godot-cpp>. MIT. Status:
**used** (submodule, native extension bindings).

**Zstandard (zstd).** <https://facebook.github.io/zstd/>. BSD. Status:
**used** through Godot's `PackedByteArray.compress` for chunk storage.

# Third-party references

This proof-of-concept is an independent Theos tweak. It does not vendor third-party source files.
The Scene-hosting design was informed by these public projects/research:

- Konban — MIT — https://github.com/nicho1asdev/Konban
  - Historical `FBScene` foregrounding and `_UISceneLayerHostContainerView` approach.
- FrontBoardAppLauncher — Apache-2.0 — https://github.com/khanhduytran0/FrontBoardAppLauncher
  - Modern FrontBoard/UIKit private-API scene presentation reference.
- Zetsu — https://dcsyhi1998.github.io/depiction/zetsu
  - iOS 16 compatibility reference and Konban lineage.
- RootHide Developer documentation — https://github.com/roothide/Developer
  - RootHide Theos package scheme and build guidance.

If future revisions copy or vendor source from any upstream project, retain the applicable upstream license and notices in the repository.

# External Source License Policy

Reference repositories may have different licenses.

Before directly reusing source code:

1. identify exact repository
2. identify exact license
3. identify license version
4. confirm reuse obligations
5. record required attribution
6. determine whether the license is compatible with TalaanScan distribution

General guidance:

MIT / BSD / Apache-style licenses are usually permissive but still require compliance with their terms.

GPL-family licenses may impose additional distribution/source obligations.

A repository with no explicit license should be treated as NOT licensed for source-code reuse.

Architecture, general algorithms, and ideas may be studied separately from copying copyrighted implementation.

This repository should prefer original implementations informed by documented research.

## Bundled Fonts

P12.1 bundles Roboto Regular and Roboto Bold from the Flutter 3.41.0 SDK's
material-font artifacts. Roboto is distributed under the Apache License 2.0.
The required license text is retained at
`assets/fonts/LICENSE-Roboto.txt`. The fonts are packaged inside the app and
PDF documents; they are never fetched dynamically.

Noto Sans Symbols 2 is bundled as the symbol fallback under the SIL Open Font
License 1.1. Its license is retained at
`assets/fonts/LICENSE-NotoSansSymbols2.txt`. The source is the official Google
Fonts/notofonts distribution; it is packaged offline and never downloaded at
runtime.

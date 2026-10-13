# Engine Boundaries

## Template Engine

Owns survey semantics.

Does not own print positions.

## Layout Engine

Owns deterministic geometry.

Does not draw PDFs.

Does not inspect camera images.

## PDF Engine

Owns rendering.

Does not calculate independent layout.

## Camera Engine

Owns camera hardware/session behavior.

Does not classify survey answers.

## ArUco Engine

Owns fiducial detection/alignment.

Does not classify bubbles.

## Preprocessing Engine

Owns image normalization.

Does not know question semantics.

## Recognition Engine

Owns bubble measurement and response classification.

Consumes PageLayout.

Does not configure camera hardware.

## Scanner Engine

Owns pipeline orchestration.

Avoid implementing algorithms already owned by another engine.

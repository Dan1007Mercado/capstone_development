# Template Rules

Initial supported question types:

- single choice
- multiple choice
- Likert scale
- yes/no
- numeric grid

Non-OMR content:

- section heading
- instruction text
- human-readable text field

## Single Choice

Contains stable QuestionId and OptionIds.

Only one response is expected.

## Multiple Choice

Contains stable option identities.

More than one response may be valid.

## Likert

Ordered response scale.

Store semantic value separately from display label where appropriate.

Example:

value = 5

label = Strongly Agree

## Yes/No

A constrained two-option single-choice question.

## Numeric Grid

Represent each digit column explicitly.

Do not infer arbitrary handwritten digits.

## Validation

Reject:

- duplicate IDs
- no-option questions
- illegal option counts
- invalid Likert scales
- empty required labels where prohibited
- unsupported combinations

You are writing exercise instructions for a fitness app.

TASK
Generate high-quality exercise instructions in Markdown for the exercise below. The result will be pasted into a YAML block scalar (instructions: |), so:
- Output MUST be Markdown only (no YAML, no code fences, no backticks).
- Do NOT include leading/trailing quotation marks.
- Do NOT include the exercise name as an H1 title (the screen already shows it).
- Keep it concise but complete: ~120–220 words total.

INPUT (exercise metadata)
- Exercise name: {EXERCISE_NAME}
- Category: {CATEGORY}            (e.g., Dumbbell / Barbell / Machine / Duration / Reps Only / Weighted Body Weight)
- Target: {TARGET}               (e.g., Core / Chest / Back / Legs / Shoulders / Arms / Full Body / Cardio / Olympic / Other)
- Equipment available: {EQUIPMENT_OR_UNKNOWN}
- Experience level: General audience (beginner-friendly language)

OUTPUT FORMAT (STRICT)
Return exactly these sections in this order:

## Overview
(1 short paragraph, 2–4 sentences. Mention what muscles it targets using the provided Target, plus 1–2 secondary muscles if obvious. No hype.)

## How to Perform
### 1. Starting Position
- (3–5 bullet points)

### 2. Movement
1. (3–6 steps total, clear and actionable)

### 3. Breathing
- optional, if relevant for the exercise
- (1–3 bullet points)

### 4. Tips
- optional, if relevant for the exercise
- (3–5 bullet points; technique cues)

### 5. Common Mistakes
- optional, if relevant for the exercise
- (3–6 bullet points; what to avoid)

### 6. Safety / Modifications
- (2–4 bullet points; regressions/progressions or safety notes)

STYLE RULES
- Use plain, practical coaching language.
- No medical claims. No rehab advice.
- Don’t mention weights in numbers unless essential; prefer “light/moderate/heavy”.
- If the exercise is unilateral, include “repeat on the other side”.
- If the exercise is time-based (Duration), mention timing guidance; if rep-based, mention rep guidance (e.g., “aim for controlled reps”).
- If equipment is unknown, assume the common setup for the named exercise.
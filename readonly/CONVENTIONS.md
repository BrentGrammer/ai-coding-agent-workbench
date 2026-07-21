# AI Developer Conventions & Workflow

- Do not be verbose. Communicate the most important information in as concise a manner as possible.

When making changes to this codebase, please adhere to the following rules and conventions:

## 1. Testing Requirement

- Write tests that cover all new behavior added to the program.
- Do not run the full test suite. Targeted tests are fine, but never run the full test suite without the user asking you to.
- Do not tie tests too closely to implementation details. Tests should cover observable behavior, survive refactoring of the production code and not be brittle.

### Test Writing Conventions

- Prefer testing observable behavior over implementation details.
- Name tests as user-visible scenarios or business outcomes. Stakeholders or business domain experts should be able to understand the test descriptions and they shouldn't contain internal implementation terms or details. Avoid React or implementation terms in test names when a plain app behavior is clearer.
- For error handling and similar branches, prefer asserting the category of outcome, the returned value source, or the selected code path rather than freezing production wording in the test. Don't test for hard coded strings in error messages - that is brittle if the wording changes.
- For error handling and failure-path tests, prefer assertions like "throws", "rejects", or "returns an error of the expected type" over hard-coded fallback error-message strings.
- Only assert exact error text when that text is part of the user-facing contract or comes from a shared application constant that the test is intentionally pinning.
- **Handling User-Facing Strings (The Balanced Approach)**:
  - **Use Raw Hardcoded Strings** in UI tests for static labels, headers, and simple button names (e.g. `expect(screen.getByText("Voice Inspector")).toBeInTheDocument()`). This enforces the _user-facing perspective_, ensuring that if the visible text changes accidentally, the test catches the regression.
  - **Use File-Scoped Test Constants** when a specific string needs to be queried, changed, and asserted across multiple tests within the same test file to avoid typos and keep the code DRY while maintaining isolation.
  - **Use Imported Global Constants** only when asserting arguments passed to mocked utility hooks or verifying long, multi-line paragraphs/modal messages that are already managed centrally in the code.
- If a string or number is repeated in a test fixture or assertion, extract it to a descriptively named local variable instead of inlining it multiple times.
- If a repeated test value carries important meaning in the assertion, extract it to a descriptive local variable even if it only appears a small number of times. Do this for values like names, ids, titles, or other domain data that the test is intentionally proving gets preserved, selected, or applied.
- For test data and fixture values, use normal descriptive local variable names when they are local to the file or test. They do not need to be all-caps constants unless they are truly shared constants.
- Keep test fixtures expressive. Reuse shared fixtures/helpers when the same setup appears in multiple tests, but do not build a large abstract test framework prematurely.
- Prefer focused assertions that verify one contract at a time over large fully inlined expected objects, unless the exact full serialized shape is the contract under test.
- When testing invalid actions or defensive paths, assert that state remains unchanged rather than relying on internal implementation details.

Example of brittle error assertion to avoid:

```ts
it("throws when the transforms request fails", async () => {
  await expect(fetchTransforms()).rejects.toThrow(
    "Failed to fetch transforms: 503 Service Unavailable",
  );
});
```

Example of preferred failure-path assertion:

```ts
it("rejects with an error when the transforms request fails", async () => {
  await expect(fetchTransforms()).rejects.toBeInstanceOf(Error);
});
```

Example of a meaningful repeated test value that should be extracted:

```ts
it("preserves the current saved composition name when the imported name is blank", async () => {
  const savedCompositionName = "Saved Composition Name";

  expect(loadCompositionIntoEditorSpy).toHaveBeenCalledWith({
    composition: expect.objectContaining({
      name: savedCompositionName,
    }),
  });
});
```

## 2. Iterative Development

- Make small, incremental changes as outlined in the `PROJECT_GOAL.md`.
- Ensure the pipeline architecture is respected (stateless transformations, separated I/O).

## 3. Comments

- Comments in the code should be avoided if possible. The code should be self-documenting and expressive so as to make the intent clear without needing a comment.
- In cases where the code might need explanation, then comments can be used, but they must explain the WHY and not the WHAT.
- Comments that only explain what the code is doing are redundant and not helpful unless what the code is doing is not intuitive.
- Commented documentation for functions is okay as long as the function is complicated enough to warrant it. Formats like Doc strings, JSDoc documentation is acceptable in these cases. Do not add documention for simple functions.

### Example of bad comments:

```python
for arg_name, func, takes_value in transform_specs:
    val = getattr(parsed_args, arg_name)
    if takes_value:
        # For value-taking flags, check if val is not None
        if val is not None:
            transforms_to_apply.append(lambda tones, f=func, v=val: f(tones, v))
    else:
        # For boolean flags, check if val is True
        if val:
            transforms_to_apply.append(func)
```

### Example of good comments that explain the WHY (don't actually write Why: in the comment, though):

```python
def test_mix_with_normalization(self):
    # 16-bit PCM audio has a strict maximum value of 32767.
    # If multiple playing tracks sum to a value higher than this, the integer overflows
    # and causes severe audio distortion (clipping). We must ensure the mixer prevents this.
    loud_track_1 = np.array([20000, -20000], dtype=np.int16)
    loud_track_2 = np.array([20000, -20000], dtype=np.int16)

    result = mix_waveforms([loud_track_1, loud_track_2])

    # The raw mathematical sum [40000, -40000] is too large.
    # The mixer must detect this and proportionally scale the entire array down
    # so the highest peak rests exactly at the safe 16-bit limit (32767).
    assert len(result) == 2
    assert result[0] == 32767
    assert result[1] == -32767
```

## 4. Magic Strings and Magic Numbers

- Where possible, magic strings and numbers should not be hard-coded, but be extracted to variables with descriptive and meaningful names that describes their purpose and meaning.
- The names of the variables should be all caps and in CAMEL_CASE.

## 5. Expressive Code

- Code should be expressive and self documenting.
- Write the code so you don't even need a lot of comments, since the names, variables and sequence it takes is telling an obvious story of what the intention and purpose of the code is.
- Names of variables and functions should be descriptive and express the intent and purpose.
- Do not use generic names like "data" or "stuff".
- Names of variables and functions should not lie. They should indicate clearly and honestly what they represent, what the variable's purpose is and what the function is doing.

## 6. Code Cleanliness

- Follow good software design principles such as those espoused by Martin Fowler (consider patterns from his books including Refactoring), Kent Beck (Test Driven Design, Extreme Programming) and Bob Martin (Clean Code, Clean Architecture).
- Code should be DRY (Do Not Repeat Yourself) where possible and practical. If you need to repeat the same behavior in code more than two or three times, then it should be abstracted into a shared module or function.
- Code should be easy to read and understand. It should not surprise you if you step through the code. The code should be so sensible that it is boring.
- Code should be separated in to modules that separate concerns to prevent too much coupling.
- Consider Domain Driven Design principles such has maintaining a business domain language that is consistent and maps to real-world objects relevant to the context.
- The code should be Easy To Change, debuggable and maintainable.
- Avoid introducing common and well-known code smells.

DO NOT WRITE NESTED TERNARIES:

```typescript
const handleKeyDown = (event: KeyboardEvent<SVGSVGElement>) => {
  // THIS IS AWFUL CODE NEVER DO THIS.
        const nextBend =
          event.key === "ArrowLeft" || event.key === "ArrowDown"
            ? bend - BEND_STEP
            : event.key === "ArrowRight" || event.key === "ArrowUp"
              ? bend + BEND_STEP
              : event.key === "Home"
                ? -1
                : event.key === "End"
                  ? 1
                  : null;
        ...
}
```
- Fundamental Rule: CODE YOU WRITE SHOULD BE EASY TO READ AND EASY TO UNDERSTAND.

## 6b. Logging vs. Print

- Prefer using the standard Python `logging` module for all terminal output (INFO for success messages, WARNING/ERROR for issues).
- Avoid using `print()` for non-CLI usage/help text. This ensures the application remains modular and can be integrated into other systems or GUIs in the future without hijacking standard output.

#### 6a. Functions

- Functions should not have more than 4 parameters. A long list of parameters is a code smell and indicates the function is trying to do too much.
- Functions should have a low cyclomatic complexity. Do not write code that is more than 3 levels deep in nesting conditionals or similar constructs.
- Function names should be descriptive and clearly indicate what the function is doing. Prefer following the convention - verb_noun
  , ex: use `find_edge_nodes()` instead of `edge_nodes()`

##### Special Note on Helper Functions:

- DO NOT CREATE HELPER FUNCTIONS that do one tiny thing or are one liners. Unless the one line is complicated and hard to understand, these helpers do not add real value and just create indirection and noise.
- Example of bad helper function (it does one simple thing which is obvious and easy to understand if inlined and offers no value by wrapping the operation):

```python
def _phrase(name: str, *tones: Tone) -> Phrase:
    return Phrase(motifs=[Motif(name=name, tones=list(tones))])
```

## 7. Architecture and Design Principles

- When generating or refactoring code, you must adhere to the following architectural standards:

1. Prefer Composition over Inheritance. Code components should be composable.

2. **Design Pattern First-Thinking:** Before writing complex logic, evaluate if a Gang of Four (GoF) design pattern is applicable to ensure maintainability and scalability.
   - Use **Creational** patterns (e.g., Factory, Singleton, Builder) to manage object creation complexity.
   - Use **Structural** patterns (e.g., Adapter, Decorator, Facade) to handle relationships between entities and simplify interfaces.
   - Use **Behavioral** patterns (e.g., Strategy, Observer, Command, State) to eliminate heavy nested conditionals and decouple logic.

3. **SOLID Principles:**
   - **Single Responsibility:** Classes should have one reason to change.
   - **Open/Closed:** Code should be open for extension but closed for modification.
   - **Liskov Substitution:** Subtypes must be substitutable for their base types.
   - **Interface Segregation:** Prefer many small, specific interfaces over one large one.
   - **Dependency Inversion:** Depend on abstractions, not concretions.

4. **Refactoring Trigger:** If you find yourself writing deep `switch` statements or multiple `if/else` blocks based on object type or state, stop and refactor using the **Strategy** or **State** pattern instead.

5. **Functional Programming** Consider Functional Programming concepts if they would work well for the use case.
   - Functions should be pure and have no side effects.
   - Functions should be composable.

## 8. Structure and Organization

- Follow principles of Clean Architecture where applicable.
- Follow "Screaming Architecture": Top level file names and folder names should reflect the domain and purpose of the application instead of being tech stack specific.

## 9. Typing

- Where possible code should be staticly and strongly typed.
- If the programming language is not a strongly staticly typed langauge (like Python, for example), then type annotations must be used.
- Avoid redundant typing like typing a variable that is assigned to an already typed argument passed in.
- Always type annotate arguments and return types for functions.
- Prefer not using Any as a type annotation. If you must use Any, then explain why in a comment.
- Avoid manual type casting if possible. This indicates a possible code smell. If you need to type cast, then write a comment explaining why.
- Also avoid `as unknown as` which is a smell. It indicates something deeper is wrong with the design or typing and we should not have to do this except in extreme cases.

## 10. Refactors and Migrations

- For large and complex refactors and migrations, do not worry about putting in place temporary patches to prevent breakage. There are no users for this application and backwards compatibility is not a concern. If making a clean break makes the migration simpler and faster, then breaking changes temporarily are fine.

## 11. Frontend Development

### HTML Authoring

- Follow good HTML authoring principles and semantic HTML5.
- Do not make an app with a bunch of `div` elements which is a "div soup"
- A screen reader should be able to read the html and understand the purpose of the elements on the page in context.
- Follow good Accessibility principles when authoring HTML.

### Mobile First Design

- Follow Mobile First Design principles. We should account for mobile screens as well as desktop screens.
- Prefer Flexbox for responsive design and auto-resizing/auto-adjusting the layout as screen size changes.
- Use CSS Grid only when appropriate for extra complicated layouts that require it over Flexbox.

# Instructions for Programming with React.js

## Components

- Components should be created under the src/components/ folder.
- Each component should have its own folder so we can have multiple files or modules related to the component in that folder.
- In each folder, there should be a top level index.ts files which does `export * from './SomeComponent/SomeComponent.tsx` for each component in that component folder to reduce long import statements that have nested paths.
- Component files should be named the conventional Upper case first letter PascalCase styling: for example, use `MyComponent.tsx`, and not `myComponent.tsx`
- Some components may be shared throughout the UI and not specific to a particular slice or page (for example, a confirmation dialog every time an important item is about to be deleted, or a reusable Input field so styling is consistent across the application). These comopnents should be in a `src/components/shared/` folder. Similar to above each one should have its own folder in that `shared/` directory.

## Avoid excessive prop drilling

- If you have to pass props down more than 2 component levels deep, then you need to make the components composable. You can do this by making the parent component accept `children` so we can compose the related components.

### Component Size

- Components should not be bloated or very large files. A component file should not be longer than around 100 lines, or 200 lines at the absolute maximum.
- Component files should contain one and only one compnent. Do not stuff more than one component definition in a single "MyComponent.tsx" file. Each component definition has it's own .tsx file.

### Styles

- Use Material UI's `styled` helper to extend and define styles for a component.
- If the styled components created in the main component file gets longer than 40 lines, then extract them into a separate .styles.tsx file at the same folder level as the component file (ex: `MyComponent.styles.tsx`)
- For styling that is more than two properties, do not inline styles with the `sx` property directly on top level components unless absolutely necessary. Extract any more elaborate styles into a `styled` component so styles are defined consistently in one place for that component, especially if the same style settings are reused more than once.

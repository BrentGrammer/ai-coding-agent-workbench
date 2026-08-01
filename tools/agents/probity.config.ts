import { defineConfig, enforceTdd } from "@nizos/probity";

export default defineConfig({
  rules: [
    {
      files: [
        "**/*.{ts,tsx,js,jsx,mjs,cjs,py,go,rs}",
        "!**/node_modules/**",
        "!**/dist/**",
        "!**/build/**",
        "!**/.next/**",
        "!**/vendor/**",
      ],
      rules: [enforceTdd()],
    },
  ],
});

// https://docs.expo.dev/guides/using-eslint/
const { defineConfig } = require("eslint/config");
const expoConfig = require("eslint-config-expo/flat");
const importPlugin = require("eslint-plugin-import");

module.exports = defineConfig([
	expoConfig,
	{
		plugins: {
			import: importPlugin,
		},
		settings: {
			"import/resolver": {
				typescript: {},
			},
		},
		languageOptions: {
			parserOptions: {
				project: "./tsconfig.json",
				tsconfigRootDir: __dirname,
			},
		},
		rules: {
			// Type-checked rules (previously from @typescript-eslint/recommended-requiring-type-checking)
			"@typescript-eslint/await-thenable": "error",
			"@typescript-eslint/no-floating-promises": "error",
			"@typescript-eslint/no-misused-promises": "error",
			"@typescript-eslint/no-unsafe-assignment": "error",
			"@typescript-eslint/no-unsafe-call": "error",
			"@typescript-eslint/no-unsafe-member-access": "error",
			"@typescript-eslint/no-unsafe-return": "error",
			"@typescript-eslint/no-unsafe-argument": "error",
			"@typescript-eslint/require-await": "error",
			"@typescript-eslint/restrict-plus-operands": "error",
			"@typescript-eslint/restrict-template-expressions": "error",
			"@typescript-eslint/unbound-method": "error",
			// Import hygiene
			"import/no-unresolved": "error",
			"import/no-duplicates": "error",
		},
		ignores: ["dist/**", "output/**", "dependencies/**"],
	},
]);

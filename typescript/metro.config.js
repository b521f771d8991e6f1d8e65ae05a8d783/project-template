const { getDefaultConfig } = require("expo/metro-config");
const { withNativeWind } = require("nativewind/metro");
const path = require("path");

if (
	process.env.NODE_ENV === "production" &&
	process.env.npm_lifecycle_event === "start"
) {
	throw new Error(
		"Do not start the dev server (npm run dev, expo start, ...) in production mode, it will fail",
	);
}

const config = getDefaultConfig(__dirname);
config.watchFolders = [
	...config.watchFolders,
	path.resolve(__dirname, "../target/npm-pkg"),
];

// Add wasm asset support
config.resolver.assetExts.push("wasm");

// Add COEP and COOP headers to support SharedArrayBuffer
config.server.enhanceMiddleware = (middleware) => {
	return (req, res, next) => {
		res.setHeader("Cross-Origin-Embedder-Policy", "credentialless");
		res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
		middleware(req, res, next);
	};
};

module.exports = withNativeWind(config, {
	input: path.resolve(__dirname, "./src/global.css"),
});

console.log("Exporting config", module.exports);

import {
	createRequestHandler,
	type RequestHandler,
} from "expo-server/adapter/workerd";

const handler: RequestHandler = createRequestHandler({
	build: "./dist/server",
});

export default { fetch: handler };

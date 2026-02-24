import { ImmutableRequest } from "expo-server/build/types";

export const unstable_settings = {
	matcher: { patterns: ["/api/private/[...slug]"] },
};

export default async function middleware(request: ImmutableRequest) {
	if ("DISABLE_AUTH" in process.env) {
		console.warn("⚠️ Authentication disabled");
	} else {
	}
}

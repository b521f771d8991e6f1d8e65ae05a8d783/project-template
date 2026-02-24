import { createApi, fetchBaseQuery } from "@reduxjs/toolkit/query/react";

export const apiSlice = createApi({
	reducerPath: "api",
	baseQuery: fetchBaseQuery({
		baseUrl: "/api",
	}),
	endpoints: (builder) => ({
		getBackendVersion: builder.query<string, void>({
			query: () => {
				return {
					url: "/version",
					method: "GET",
					responseHandler: (response) => response.text(),
				};
			},
		}),
		getBackendStatus: builder.query<boolean, void>({
			query: () => {
				return {
					url: "/status",
					method: "GET",
					responseHandler: (response) => response.text(),
				};
			},
			transformResponse: (response: string) => response === "👌",
		}),
		getAppConfig: builder.query<unknown, void>({
			query: () => {
				return {
					url: "/app-config.json",
				};
			},
		}),
	}),
});

export const {
	useGetBackendVersionQuery,
	useGetBackendStatusQuery,
	useGetAppConfigQuery,
} = apiSlice;

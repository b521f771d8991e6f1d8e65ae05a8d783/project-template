import { apiSlice } from "@/redux/state/apiSlice";
import {
	Action,
	configureStore,
	isPlain,
	ThunkAction,
} from "@reduxjs/toolkit";
import { useDispatch, useSelector } from "react-redux";

/**
 * Retrieves the entries of an object, with special handling for objects that implement a `toJson` method.
 *
 * If the input object has a `toJson` method, this method is invoked to retrieve the entries.
 * Otherwise, the method falls back to using `Object.entries` to get the key-value pairs.
 *
 * @param x - The input object to retrieve entries from. It can be any type.
 * @returns An array of key-value pairs representing the entries of the object.
 */

function getEntriesWithToJsonSupport(x: any): [string, any][] {
	if ("toJson" in x) {
		return Object.entries(JSON.parse(x.toJson()));
	} else {
		console.assert(isPlain(x));
		return Object.entries(x);
	}
}

/**
 * Determines if a given value is serializable, including support for objects
 * that implement a `toJson` method.
 *
 * @param x - The value to check for serializability.
 * @returns `true` if the value is a plain object or has a `toJson` method, otherwise `false`.
 */

function isSerializableWithToJsonSupport(x: any): boolean {
	return isPlain(x) || "toJson" in x;
}

export const store = configureStore({
	reducer: {
		[apiSlice.reducerPath]: apiSlice.reducer,
	},
	middleware: (getDefaultMiddleware) =>
		getDefaultMiddleware({
			serializableCheck: {
				getEntries: getEntriesWithToJsonSupport,
				isSerializable: isSerializableWithToJsonSupport,
			},
		}).concat(apiSlice.middleware),
	devTools: process.env.NODE_ENV === "development",
});

// Infer the type of `store`
export type AppStore = typeof store;
// Infer the `AppDispatch` type from the store itself
export type AppDispatch = typeof store.dispatch;
// Same for the `RootState` type
export type AppState = ReturnType<typeof store.getState>;
// Define a reusable type describing thunk functions
export type AppThunk<ThunkReturnType = void> = ThunkAction<
	ThunkReturnType,
	AppState,
	unknown,
	Action
>;

// Typed hooks — use these throughout the app instead of plain useDispatch/useSelector
export const useAppDispatch = useDispatch.withTypes<AppDispatch>();
export const useAppSelector = useSelector.withTypes<AppState>();

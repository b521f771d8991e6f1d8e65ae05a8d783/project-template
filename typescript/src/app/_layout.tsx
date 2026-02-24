import { useEffect } from "react";
import "../global.css";
import "../i18n";
import { Platform, View } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { Provider } from "react-redux";
import { store } from "@/redux/store";
import { Stack, usePathname } from "expo-router";

export default function RootLayout() {
	const path = usePathname();
	const isEmbedded = path.startsWith("/internal");

	useEffect(() => {
		if (Platform.OS == "web") {
			document.title = process.env.EXPO_PUBLIC_APP_NAME ?? "App";
			document.addEventListener("contextmenu", (event) =>
				event.preventDefault(),
			);
		}
	}, []);

	return (
		<SafeAreaProvider>
			<Provider store={store}>
				<View className="select-none">
					<Stack screenOptions={{
						headerShown: isEmbedded ? false : true
					}}/>
				</View>
			</Provider>
		</SafeAreaProvider>
	);
}

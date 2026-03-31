import React from "react";
import { useTranslation } from "react-i18next";
import { HelloWave } from "@/components/hello-wave";
import { View, Text, Image } from "react-native";
import icon from "@assets/images/icon.png";

export default function RootNode() {
	const { t } = useTranslation();
	return (
		<View className="flex min-h-screen items-center justify-center bg-gray-50 p-6">
			{/* Card container for even spacing */}
			<View className="w-full max-w-md space-y-6 rounded-xl bg-white p-8 shadow-lg">
				{/* Title */}
				<Text className="text-center text-2xl font-semibold text-gray-800 underline">
					{t("home.welcome")}
				</Text>

				{/* Image – centered */}
				<View className="flex items-center">
					<Image
						source={icon}
						style={{ width: 120, height: 120, resizeMode: "contain" }}
					/>
				</View>

				{/* HelloWave – centered */}
				<View className="flex items-center">
					<HelloWave />
				</View>
			</View>
		</View>
	);
}

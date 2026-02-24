import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import { getLocales } from "expo-localization";

import en from "./locales/en.json";
import de from "./locales/de.json";
import he from "./locales/he.json";
import la from "./locales/la.json";
import fr from "./locales/fr.json";
import es from "./locales/es.json";
import ar from "./locales/ar.json";
import zh from "./locales/zh.json";
import ru from "./locales/ru.json";
import pt from "./locales/pt.json";

const resources = {
	en: { translation: en },
	de: { translation: de },
	he: { translation: he },
	la: { translation: la },
	fr: { translation: fr },
	es: { translation: es },
	ar: { translation: ar },
	zh: { translation: zh },
	ru: { translation: ru },
	pt: { translation: pt },
};

const languageTag = getLocales()[0]?.languageTag ?? "en";

i18n.use(initReactI18next).init({
	resources,
	lng: languageTag,
	fallbackLng: "en",
	interpolation: {
		escapeValue: false,
	},
});

export default i18n;

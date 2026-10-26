import { enUs } from "./en-us.js";
import { ptBr } from "./pt-br.js";
import type { TranslationMessages } from "./types.js";

export type { TranslationMessages } from "./types.js";
export const translations = {
  "en-us": enUs,
  "pt-br": ptBr,
} satisfies Record<string, TranslationMessages>;

export type SupportedLocale = keyof typeof translations;
export type TranslationDictionary = (typeof translations)[SupportedLocale];

const supportedLocales = Object.keys(translations) as SupportedLocale[];

function isSupportedLocale(locale: string): locale is SupportedLocale {
  return Object.prototype.hasOwnProperty.call(translations, locale);
}

export function resolveLocale(
  preferredLanguages: readonly string[],
): SupportedLocale {
  for (const preferredLanguage of preferredLanguages) {
    const normalizedLanguage = preferredLanguage
      .trim()
      .replace(/_/g, "-")
      .toLowerCase();

    if (isSupportedLocale(normalizedLanguage)) {
      return normalizedLanguage;
    }

    const languageCode = normalizedLanguage.split("-")[0];
    const matchingLocale = supportedLocales.find(
      (locale) => locale.split("-")[0] === languageCode,
    );
    if (matchingLocale) {
      return matchingLocale;
    }
  }

  return "en-us";
}

export function formatTranslation(
  template: string,
  values: Readonly<Record<string, string | number>> = {},
): string {
  return template.replace(/\{([^{}]+)\}/g, (placeholder, key: string) => {
    if (!Object.prototype.hasOwnProperty.call(values, key)) {
      throw new Error(`Missing value for translation placeholder "${key}".`);
    }

    return String(values[key]);
  });
}

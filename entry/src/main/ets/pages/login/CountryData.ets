import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';

export interface CountryOption {
  iso2: string;
  name: string;
  englishName: string;
  callingCode: string;
  flag: string;
}

function flagForIso(iso2: string): string {
  const upper = iso2.toUpperCase();
  if (upper.length !== 2) { return '🌐'; }
  return String.fromCodePoint(
    127397 + upper.charCodeAt(0),
    127397 + upper.charCodeAt(1)
  );
}

function country(
  iso2: string, name: string, englishName: string, callingCode: string
): CountryOption {
  return { iso2, name, englishName, callingCode, flag: flagForIso(iso2) };
}

// Immediate offline choices while TDLib loads its complete, server-maintained
// country list. The online result replaces this list and includes every code.
export const FALLBACK_COUNTRIES: CountryOption[] = [
  country('CN', '中国大陆', 'China', '86'),
  country('HK', '中国香港', 'Hong Kong', '852'),
  country('MO', '中国澳门', 'Macao', '853'),
  country('TW', '中国台湾', 'Taiwan', '886'),
  country('SG', '新加坡', 'Singapore', '65'),
  country('MY', '马来西亚', 'Malaysia', '60'),
  country('JP', '日本', 'Japan', '81'),
  country('KR', '韩国', 'South Korea', '82'),
  country('TH', '泰国', 'Thailand', '66'),
  country('VN', '越南', 'Vietnam', '84'),
  country('PH', '菲律宾', 'Philippines', '63'),
  country('ID', '印度尼西亚', 'Indonesia', '62'),
  country('IN', '印度', 'India', '91'),
  country('AE', '阿联酋', 'United Arab Emirates', '971'),
  country('SA', '沙特阿拉伯', 'Saudi Arabia', '966'),
  country('TR', '土耳其', 'Türkiye', '90'),
  country('RU', '俄罗斯', 'Russia', '7'),
  country('UA', '乌克兰', 'Ukraine', '380'),
  country('GB', '英国', 'United Kingdom', '44'),
  country('FR', '法国', 'France', '33'),
  country('DE', '德国', 'Germany', '49'),
  country('IT', '意大利', 'Italy', '39'),
  country('ES', '西班牙', 'Spain', '34'),
  country('PT', '葡萄牙', 'Portugal', '351'),
  country('NL', '荷兰', 'Netherlands', '31'),
  country('BE', '比利时', 'Belgium', '32'),
  country('CH', '瑞士', 'Switzerland', '41'),
  country('AT', '奥地利', 'Austria', '43'),
  country('SE', '瑞典', 'Sweden', '46'),
  country('NO', '挪威', 'Norway', '47'),
  country('FI', '芬兰', 'Finland', '358'),
  country('DK', '丹麦', 'Denmark', '45'),
  country('PL', '波兰', 'Poland', '48'),
  country('CZ', '捷克', 'Czechia', '420'),
  country('GR', '希腊', 'Greece', '30'),
  country('US', '美国', 'United States', '1'),
  country('CA', '加拿大', 'Canada', '1'),
  country('MX', '墨西哥', 'Mexico', '52'),
  country('BR', '巴西', 'Brazil', '55'),
  country('AR', '阿根廷', 'Argentina', '54'),
  country('CL', '智利', 'Chile', '56'),
  country('CO', '哥伦比亚', 'Colombia', '57'),
  country('AU', '澳大利亚', 'Australia', '61'),
  country('NZ', '新西兰', 'New Zealand', '64'),
  country('ZA', '南非', 'South Africa', '27'),
  country('EG', '埃及', 'Egypt', '20'),
  country('NG', '尼日利亚', 'Nigeria', '234'),
  country('KE', '肯尼亚', 'Kenya', '254'),
  country('IL', '以色列', 'Israel', '972'),
  country('PK', '巴基斯坦', 'Pakistan', '92'),
  country('BD', '孟加拉国', 'Bangladesh', '880')
];

function parseCountries(response: TdObject): CountryOption[] {
  const rawCountries = (response['countries'] as TdObject[] | undefined) ?? [];
  const result: CountryOption[] = [];
  const seen: Set<string> = new Set();
  for (const raw of rawCountries) {
    if ((raw['is_hidden'] as boolean | undefined) === true) { continue; }
    const iso2 = (raw['country_code'] as string | undefined) ?? '';
    const name = (raw['name'] as string | undefined) ??
      (raw['default_name'] as string | undefined) ?? '';
    const englishName = (raw['english_name'] as string | undefined) ?? name;
    const callingCodes = (raw['calling_codes'] as string[] | undefined) ?? [];
    for (const callingCode of callingCodes) {
      const key = `${iso2}:${callingCode}`;
      if (callingCode === '' || seen.has(key)) { continue; }
      seen.add(key);
      result.push(country(iso2, name !== '' ? name : englishName, englishName, callingCode));
    }
    // Compatibility with the older Telegram country-list shape used by some
    // TDLib builds, where codes were objects rather than strings.
    const legacyCodes = (raw['country_codes'] as TdObject[] | undefined) ?? [];
    for (const calling of legacyCodes) {
      const callingCode = (calling['calling_code'] as string | undefined) ??
        (calling['country_code'] as string | undefined) ?? '';
      const key = `${iso2}:${callingCode}`;
      if (callingCode === '' || seen.has(key)) { continue; }
      seen.add(key);
      result.push(country(iso2, name !== '' ? name : englishName, englishName, callingCode));
    }
  }
  result.sort((left: CountryOption, right: CountryOption): number =>
    left.name.localeCompare(right.name));
  return result;
}

export async function loadCountries(): Promise<CountryOption[]> {
  try {
    const request: TdRequest = { '@type': 'getCountries' };
    const response = await getTdClient().send(request, 20000);
    const countries = parseCountries(response);
    return countries.length > 0 ? countries : FALLBACK_COUNTRIES;
  } catch (caught) {
    const error = caught as Error;
    console.error(`CountryData.loadCountries failed: ${error.message}`);
    return FALLBACK_COUNTRIES;
  }
}

export function filterCountries(
  countries: CountryOption[], query: string
): CountryOption[] {
  const normalized = query.trim().toLowerCase().replace('+', '');
  if (normalized === '') { return countries; }
  return countries.filter((item: CountryOption): boolean =>
    item.name.toLowerCase().includes(normalized) ||
    item.englishName.toLowerCase().includes(normalized) ||
    item.iso2.toLowerCase().includes(normalized) ||
    item.callingCode.includes(normalized)
  );
}

import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../../tdkit/Globals';
import { TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  CountryOption, FALLBACK_COUNTRIES, filterCountries, loadCountries
} from './CountryData';
import { LoginHero } from './LoginHero';

@Preview
@Component
export struct PhoneNumberPage {
  @State phoneDigits: string = '';
  @State errorText: string = '';
  @State busy: boolean = false;
  @State pickerOpen: boolean = false;
  @State pickerReady: boolean = false;
  @State countrySearch: string = '';
  @State countries: CountryOption[] = FALLBACK_COUNTRIES;
  @State selectedCountry: CountryOption = {
    iso2: 'CN',
    name: '中国大陆',
    englishName: 'China',
    callingCode: '86',
    flag: '🇨🇳'
  };

  aboutToAppear(): void {
    loadCountries().then((countries: CountryOption[]): void => {
      this.countries = countries;
      const china = countries.find(
        (item: CountryOption): boolean => item.iso2 === 'CN' && item.callingCode === '86'
      );
      if (china !== undefined && this.phoneDigits === '') {
        this.selectedCountry = china;
      }
    });
  }

  private onPhoneChange(value: string): void {
    const digits = value.replace(/[^0-9]/g, '');
    this.phoneDigits = digits.substring(0, Math.min(15, digits.length));
    this.errorText = '';
  }

  private submitPhone(): void {
    if (this.busy) { return; }
    if (this.phoneDigits.length < 4) {
      this.errorText = '请输入正确的手机号码';
      return;
    }
    this.busy = true;
    this.errorText = '';
    const fullPhone = `+${this.selectedCountry.callingCode}${this.phoneDigits}`;
    getAuthService().submitPhone(fullPhone).catch((caught: TdError): void => {
      this.errorText = caught.message;
    }).finally((): void => {
      this.busy = false;
    });
  }

  private selectCountry(country: CountryOption): void {
    if (!this.pickerReady) { return; }
    this.selectedCountry = country;
    this.countrySearch = '';
    this.pickerReady = false;
    this.pickerOpen = false;
    this.errorText = '';
  }

  private openCountryPicker(): void {
    this.pickerReady = false;
    this.pickerOpen = true;
    setTimeout((): void => {
      if (this.pickerOpen) { this.pickerReady = true; }
    }, 800);
  }

  @Builder
  countryPickerSheet() {
    Column() {
      Row() {
        Text('选择国家或地区')
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1);
      }
      .padding({ left: 18, right: 58, bottom: 12 })
      .margin({left: 12, right: 12, bottom: 12, top: 12})
      .alignItems(VerticalAlign.Center);

      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17).fontColor([COLOR_TEXT_SECONDARY]);
        TextInput({ text: this.countrySearch, placeholder: '搜索国家、地区或区号' })
          .fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .height(42)
          .onChange((value: string): void => { this.countrySearch = value; });
      }
      .padding({ left: 13, right: 10 })
      .margin({ left: 14, right: 14, bottom: 8 })
      .borderRadius(13)
      .backgroundColor($r('app.color.page_bg'));

      List() {
        ForEach(
          filterCountries(this.countries, this.countrySearch),
          (country: CountryOption) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(country.flag).fontSize(27).width(36).textAlign(TextAlign.Center);
                Column({ space: 2 }) {
                  Text(country.name)
                    .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  if (country.englishName !== '' && country.englishName !== country.name) {
                    Text(country.englishName)
                      .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1);
                Text(`+${country.callingCode}`).fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
                if (country.iso2 === this.selectedCountry.iso2 &&
                  country.callingCode === this.selectedCountry.callingCode) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(16).fontColor([COLOR_PRIMARY]);
                }
              }
              .width('100%')
              .padding({ left: 16, right: 18, top: 10, bottom: 10 })
              .onClick((): void => this.selectCountry(country));
            }
          },
          (country: CountryOption): string => `${country.iso2}_${country.callingCode}`
        );
      }
      .layoutWeight(1)
      .enabled(this.pickerReady)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring);
    }
    .width('100%').height('100%')
    .padding({ top: 12, bottom: 12 });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        LoginHero({ mode: 'phone' });

        Text('你的手机号')
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text('请选择国家或地区，并输入用于登录 Telegram 的手机号码。')
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .lineHeight(21)
          .padding({ left: 20, right: 20 });

        Row({ space: 10 }) {
          Text(this.selectedCountry.flag).fontSize(24);
          Text(this.selectedCountry.name)
            .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text(`+${this.selectedCountry.callingCode}`)
            .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width('100%').height(54)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(13)
        .border({ width: 1, color: '#263390EC' })
        .onClick((): void => this.openCountryPicker());

        Row({ space: 10 }) {
          Row() {
            Text(`+${this.selectedCountry.callingCode}`)
              .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          }
          .height(54).padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(13)
          .border({ width: 1, color: '#263390EC' });

          TextInput({ text: this.phoneDigits, placeholder: '手机号码' })
            .type(InputType.PhoneNumber)
            .fontSize(17).fontColor(COLOR_TEXT_PRIMARY)
            .placeholderColor(COLOR_TEXT_SECONDARY)
            .caretColor(COLOR_PRIMARY)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(13)
            .border({ width: 1, color: this.errorText !== '' ? '#FF3B30' : '#263390EC' })
            .height(54).padding({ left: 14, right: 14 })
            .layoutWeight(1)
            .enterKeyType(EnterKeyType.Go)
            .onChange((value: string): void => this.onPhoneChange(value))
            .onSubmit((): void => this.submitPhone());
        }
        .width('100%');

        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%')
            .fontSize(13).fontColor('#FF3B30')
            .padding({ left: 4, right: 4 });
        }

        Button(this.busy ? '正在发送验证码…' : '继续')
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(14)
          .enabled(!this.busy && this.phoneDigits.length >= 4)
          .onClick((): void => this.submitPhone());

        if (canReturnToPreviousTdAccount()) {
          Button('返回原账号')
            .width('100%').height(46)
            .fontColor(COLOR_PRIMARY)
            .backgroundColor(Color.Transparent)
            .enabled(!this.busy)
            .onClick((): void => {
              this.busy = true;
              returnToPreviousTdAccount().catch((caught: Error): void => {
                this.errorText = caught.message;
                this.busy = false;
              });
            });
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 430 })
      .padding({ left: 24, right: 24, top: 28, bottom: 28 });
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_bg'))
    .bindSheet($$this.pickerOpen, this.countryPickerSheet(), {
      height: '82%',
      backgroundColor: $r('app.color.surface'),
      dragBar: true
    });
  }
}

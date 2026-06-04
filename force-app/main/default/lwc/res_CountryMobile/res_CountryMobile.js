import { LightningElement, api, track } from 'lwc';
import countryData from '@salesforce/resourceUrl/RES_AllCountryDialCode';

export default class Res_CountryMobile extends LightningElement {
    @api label = 'Mobile Number';
    @api placeholder = 'Enter mobile number';
    @api required = false;

    @api phone = '';
    @api countryCode = '+966';
    @api fullPhoneNumber = '';

    @track showDropdown = false;
    @track countries = [];
    @track filteredCountries = [];
    @track errorMessage = '';

    @track selectedCountry = {
        flag: '🇸🇦',
        dial_code: '+966',
        name: 'Saudi Arabia',
        code: 'SA'
    };

    connectedCallback() {
        this.loadCountryData();
        this.handleOutsideClick = this.handleOutsideClick.bind(this);
        document.addEventListener('click', this.handleOutsideClick);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.handleOutsideClick);
    }

    get arrowClass() {
        return this.showDropdown ? 'arrow arrow-up' : 'arrow arrow-down';
    }

    async loadCountryData() {
        try {
            const response = await fetch(countryData);
            const data = await response.json();

            this.countries = Array.isArray(data) ? data : [];
            this.filteredCountries = [...this.countries];

            const matchedCountry = this.countries.find(
                (country) => country.dial_code === this.countryCode
            );

            if (matchedCountry) {
                this.selectedCountry = matchedCountry;
            }

            this.prepareFullPhoneNumber();
            this.notifyParent();
        } catch (error) {
            this.errorMessage = 'Unable to load country codes.';
            // eslint-disable-next-line no-console
            console.error('Error loading country data:', error);
        }
    }

    handleOutsideClick() {
        this.showDropdown = false;
    }

    toggleDropdown(event) {
        event.stopPropagation();
        this.showDropdown = !this.showDropdown;
    }

    stopPropagateParent(event) {
        event.stopPropagation();
    }

    handleSearch(event) {
        const searchTerm = (event.target.value || '').toLowerCase().trim();

        this.filteredCountries = this.countries.filter((country) => {
            const countryName = (country.name || '').toLowerCase();
            const dialCode = (country.dial_code || '').toLowerCase();
            const isoCode = (country.code || '').toLowerCase();

            return (
                countryName.includes(searchTerm) ||
                dialCode.includes(searchTerm) ||
                isoCode.includes(searchTerm)
            );
        });
    }

    handleCountrySelect(event) {
        event.stopPropagation();

        const selectedCode = event.currentTarget.dataset.code;
        const matchedCountry = this.countries.find(
            (country) => country.code === selectedCode
        );

        if (matchedCountry) {
            this.selectedCountry = matchedCountry;
            this.countryCode = matchedCountry.dial_code;
            this.showDropdown = false;
            this.filteredCountries = [...this.countries];

            this.prepareFullPhoneNumber();
            this.validateInput();
            this.notifyParent();
        }
    }

    handlePhoneChange(event) {
        this.phone = (event.target.value || '').replace(/[^\d]/g, '');
        this.prepareFullPhoneNumber();
        this.validateInput();
        this.notifyParent();
    }

    handleBlur() {
        this.validateInput();
        this.notifyParent();
    }

    prepareFullPhoneNumber() {
        const safeCountryCode = this.countryCode || '';
        const safePhone = this.phone || '';
        this.fullPhoneNumber = `${safeCountryCode}${safePhone}`;
    }

    validateInput() {
        this.errorMessage = '';

        if (this.required && !this.phone) {
            this.errorMessage = 'Phone is required.';
            return false;
        }

        if (this.phone && !this.isValidE164(this.fullPhoneNumber)) {
            this.errorMessage =
                'Mobile number must be in E.164 format (e.g., +1234567890)';
            return false;
        }

        return true;
    }

    isValidE164(phoneNumber) {
        const e164Regex = /^\+[1-9]\d{6,14}$/;
        return e164Regex.test(phoneNumber);
    }

    notifyParent() {
        this.dispatchEvent(
            new CustomEvent('phonechange', {
                detail: {
                    phone: this.phone,
                    countryCode: this.countryCode,
                    fullPhoneNumber: this.fullPhoneNumber
                },
                bubbles: true,
                composed: true
            })
        );
    }

    @api validate() {
        const isValid = this.validateInput();

        return {
            isValid,
            errorMessage: isValid ? null : this.errorMessage
        };
    }
}
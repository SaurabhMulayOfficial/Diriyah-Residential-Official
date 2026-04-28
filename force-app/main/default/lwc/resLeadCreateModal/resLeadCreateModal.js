import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import getPicklistValues from '@salesforce/apex/RES_LeadCreateController.getPicklistValues';
import isSystemAdmin from '@salesforce/apex/RES_LeadCreateController.isSystemAdmin';
import hasLeadSourceAccessByRole from '@salesforce/apex/RES_LeadCreateController.hasLeadSourceAccessByRole';
import createLead from '@salesforce/apex/RES_LeadCreateController.createLead';
import getFilteredLeadSourceValues from '@salesforce/apex/RES_LeadCreateController.getFilteredLeadSourceValues';
import getFilteredIdentificationTypeValues from '@salesforce/apex/RES_LeadCreateController.getFilteredIdentificationTypeValues';
import getCityscapeYearValues from '@salesforce/apex/RES_LeadCreateController.getCityscapeYearValues';
import getRecordTypeById from '@salesforce/apex/RES_LeadCreateController.getRecordTypeById';

import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';

export default class ResLeadCreateModal extends NavigationMixin(LightningElement) {
    @api showButton = false;

    @track showLeadFormModal = false;

    @track _rtId = '';
    @track _rtDevName = '';
    @track _rtName = '';

    @track salutationOptions = [];
    @track genderOptions = [];
    @track identificationTypeOptions = [];
    @track corporateTitleOptions = [];
    @track filteredLeadSourceOptions = [];
    @track cityscapeYearOptions = [];

    @track salutationValue = '';
    @track firstNameValue = '';
    @track middleNameValue = '';
    @track lastNameValue = '';
    @track fullArabicNameValue = '';
    @track mobileValue = '';
    @track emailValue = '';
    @track leadSourceValue = '';
    @track cityscapeYearValue = '';
    @track genderValue = '';
    @track identificationTypeValue = '';
    @track identificationNumberValue = '';
    @track companyValue = '';
    @track websiteValue = '';
    @track corporateTitleValue = '';
    @track crNumberValue = '';

    @track errors = {};
    @track isSaving = false;
    @track canSeeLeadSource = false;
    @track showCityscapeYear = false;
    @track showIdentificationNumber = false;
    @track currentUserName = '';

    _dataLoaded = false;

    userId = USER_ID;

    @wire(getRecord, { recordId: '$userId', fields: [NAME_FIELD] })
    wiredUser({ data }) {
        if (data) {
            this.currentUserName = getFieldValue(data, NAME_FIELD) || '';
        }
    }

    @wire(CurrentPageReference)
    async pageRefHandler(pageRef) {
        if (!pageRef) {
            return;
        }

        const isLeadNew =
            pageRef.type === 'standard__objectPage' &&
            pageRef.attributes?.objectApiName === 'Lead' &&
            pageRef.attributes?.actionName === 'new';

        if (!isLeadNew || this.showLeadFormModal) {
            return;
        }

        let rtId = pageRef.state?.recordTypeId || pageRef.state?.RecordTypeId || '';

        if (!rtId) {
            try {
                const search = window.location.search + window.location.hash;
                const match = search.match(/[?&#]recordTypeId=([a-zA-Z0-9]{15,18})/i);
                if (match) {
                    rtId = match[1];
                }
            } catch (error) {
                // Ignore URL parsing error.
            }
        }

        if (!this._dataLoaded) {
            await this.loadInitialData();
        }

        await this.openWithRecordType(rtId);
    }

    @api
    async invoke(rtId, rtDevName, rtName) {
        if (this.showLeadFormModal) {
            return;
        }

        const id = (rtId || '').trim();
        const developerName = (rtDevName || '').trim();
        const name = (rtName || '').trim();

        if (!this._dataLoaded) {
            await this.loadInitialData();
        }

        if (id && developerName) {
            this._rtId = id;
            this._rtDevName = developerName;
            this._rtName = name;

            this.clearForm();
            this.showLeadFormModal = true;
        } else {
            await this.openWithRecordType(id);
        }
    }

    @api
    openModal() {
        this.openWithRecordType('');
    }

    connectedCallback() {
        if (!this._dataLoaded) {
            this.loadInitialData();
        }
    }

    async loadInitialData() {
        try {
            const [
                salutationValues,
                genderValues,
                allLeadSourceValues,
                filteredLeadSourceValues,
                identificationTypeValues,
                corporateTitleValues,
                cityscapeYearValues,
                adminUser,
                hasLeadSourceAccess
            ] = await Promise.all([
                getPicklistValues({ fieldApiName: 'Salutation' }),
                getPicklistValues({ fieldApiName: 'GenderIdentity' }),
                getPicklistValues({ fieldApiName: 'LeadSource' }),
                getFilteredLeadSourceValues(),
                getFilteredIdentificationTypeValues(),
                getPicklistValues({ fieldApiName: 'RES_Corporate_Title__c' }),
                getCityscapeYearValues(),
                isSystemAdmin(),
                hasLeadSourceAccessByRole()
            ]);

            this.salutationOptions = salutationValues || [];
            this.genderOptions = genderValues || [];
            this.identificationTypeOptions = identificationTypeValues || [];
            this.corporateTitleOptions = corporateTitleValues || [];
            this.cityscapeYearOptions = cityscapeYearValues || [];
            this.canSeeLeadSource = adminUser || hasLeadSourceAccess;

            if (adminUser) {
                this.filteredLeadSourceOptions = allLeadSourceValues || [];
            } else if (hasLeadSourceAccess) {
                this.filteredLeadSourceOptions = filteredLeadSourceValues || [];
            } else {
                this.filteredLeadSourceOptions = [];
            }

            this._dataLoaded = true;
        } catch (error) {
            this.showToast(
                'Error',
                `Failed to load form data: ${this.getErrorMessage(error)}`,
                'error'
            );
        }
    }

    async openWithRecordType(rtId) {
        this._rtId = rtId || '';
        this._rtDevName = '';
        this._rtName = '';

        if (rtId) {
            try {
                const recordType = await getRecordTypeById({ recordTypeId: rtId });

                if (recordType) {
                    this._rtId = recordType.id || rtId;
                    this._rtDevName = recordType.developerName || '';
                    this._rtName = recordType.name || '';
                }
            } catch (error) {
                // Keep recordTypeId minimum so save can still work.
            }
        }

        this.clearForm();
        this.showLeadFormModal = true;
    }

    handleNewClick() {
        this.openModal();
    }

    handleClose() {
        this.showLeadFormModal = false;
        this.dispatchEvent(new CustomEvent('close'));

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Lead',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value || '';

        this.setField(field, value);
        this.clearFieldError(field);
    }

    handleIdentificationTypeChange(event) {
        const value = event.target.value || '';

        this.identificationTypeValue = value;
        this.identificationNumberValue = '';
        this.showIdentificationNumber = value !== '';

        const updatedErrors = { ...this.errors };
        delete updatedErrors.RES_Identification_Type__c;
        delete updatedErrors.RES_Identification_Number__c;
        this.errors = updatedErrors;
    }

    handleLeadSourceChange(event) {
        const value = event.target.value || '';

        this.leadSourceValue = value;
        this.showCityscapeYear = value === 'Cityscape';

        this.clearFieldError('LeadSource');

        if (value !== 'Cityscape') {
            this.cityscapeYearValue = '';
            this.clearFieldError('RES_Cityscape_Year__c');
        }
    }

    handleSave() {
        this.save(false);
    }

    handleSaveAndNew() {
        this.save(true);
    }

    async save(andNew) {
        if (!this.validateForm()) {
            return;
        }

        if (!this._rtId) {
            this.showToast(
                'Error',
                'Record type could not be determined. Please close and try again.',
                'error'
            );
            return;
        }

        this.isSaving = true;

        try {
            const result = await createLead({
                fieldValues: this.buildPayload(),
                recordTypeId: this._rtId
            });

            const fullName =
                result.Name ||
                `${result.FirstName || ''} ${result.LastName || ''}`.trim();

            this.showToast('Success', `Lead "${fullName}" was created.`, 'success');

            if (andNew) {
                this.clearForm();
            } else {
                this.showLeadFormModal = false;

                this.dispatchEvent(
                    new CustomEvent('recordsaved', {
                        detail: {
                            recordId: result.Id
                        }
                    })
                );

                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result.Id,
                        actionName: 'view'
                    }
                });
            }
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    validateForm() {
        const validationErrors = {};
        let isValid = true;

        if (!this.firstNameValue.trim()) {
            validationErrors.FirstName = 'First Name is required.';
            isValid = false;
        }

        if (!this.lastNameValue.trim()) {
            validationErrors.LastName = 'Last Name is required.';
            isValid = false;
        }

        const mobileNumber = this.mobileValue.trim();

        if (!mobileNumber) {
            validationErrors.MobilePhone = 'Mobile is required.';
            isValid = false;
        } else if (!/^\+[1-9]\d{7,14}$/.test(mobileNumber)) {
            validationErrors.MobilePhone =
                'Mobile number must be in E.164 format, for example +1234567890.';
            isValid = false;
        }

        const emailVal = this.emailValue.trim();

        if (emailVal) {
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

            if (!emailRegex.test(emailVal)) {
                validationErrors.Email = 'Please enter a valid email address.';
                isValid = false;
            }
        }

        if (this.canSeeLeadSource && !this.leadSourceValue) {
            validationErrors.LeadSource = 'Lead Source is required.';
            isValid = false;
        }

        if (this.showCityscapeYear && !this.cityscapeYearValue) {
            validationErrors.RES_Cityscape_Year__c =
                'Cityscape Year is required when Lead Source is Cityscape.';
            isValid = false;
        }

        if (this.isResidentialIndividual === true) {
            const hasSalutation = !!this.salutationValue;
            const hasGender = !!this.genderValue;
            const isKnownSalutation = this.isMaleSalutation() || this.isFemaleSalutation();
            const selectedGenderLabel = this.getGenderLabelByValue(this.genderValue).toLowerCase();

            if (hasSalutation && !hasGender && !isKnownSalutation) {
                validationErrors.GenderIdentity =
                    'Gender Type is required for the selected Salutation.';
                isValid = false;
            }

            if (!hasSalutation && hasGender) {
                validationErrors.Salutation =
                    'Kindly select the appropriate salutation based on gender.';
                isValid = false;
            }

            if (hasSalutation && hasGender && isKnownSalutation) {
                const isMaleMismatch =
                    selectedGenderLabel === 'male' && !this.isMaleSalutation();

                const isFemaleMismatch =
                    selectedGenderLabel === 'female' && !this.isFemaleSalutation();

                if (isMaleMismatch || isFemaleMismatch) {
                    validationErrors.Salutation =
                        'Kindly select the appropriate salutation based on gender.';
                    isValid = false;
                }
            }

            if (this.showIdentificationNumber) {
                const idType = this.identificationTypeValue;
                const idNumber = this.identificationNumberValue.trim();

                if (!idNumber) {
                    validationErrors.RES_Identification_Number__c =
                        'Identification Number is required.';
                    isValid = false;
                }

                if (idNumber && idType === 'ZIT01') {
                    if (!idNumber.startsWith('1') || !/^\d{10}$/.test(idNumber)) {
                        validationErrors.RES_Identification_Number__c =
                            'National ID must start with 1 and consist of exactly 10 digits.';
                        isValid = false;
                    }
                }

                if (idNumber && idType === 'ZIT02') {
                    if (!idNumber.startsWith('2') || !/^\d{10}$/.test(idNumber)) {
                        validationErrors.RES_Identification_Number__c =
                            'Iqama No. must start with 2 and consist of exactly 10 digits.';
                        isValid = false;
                    }
                }
            }
        } else {
            this.genderValue = '';
        }

        if (this.isResidentialCompany === true) {
            if (!this.companyValue.trim()) {
                validationErrors.Company = 'Company is required.';
                isValid = false;
            }
        }

        this.errors = validationErrors;
        return isValid;
    }

    setField(field, value) {
        switch (field) {
            case 'Salutation':
                this.salutationValue = value;
                this.setGenderFromSalutation(value);
                break;
            case 'FirstName':
                this.firstNameValue = value;
                break;
            case 'MiddleName':
                this.middleNameValue = value;
                break;
            case 'LastName':
                this.lastNameValue = value;
                break;
            case 'RES_Full_Arabic_Name__c':
                this.fullArabicNameValue = value;
                break;
            case 'MobilePhone':
                this.mobileValue = value;
                break;
            case 'Email':
                this.emailValue = value;
                break;
            case 'LeadSource':
                this.leadSourceValue = value;
                break;
            case 'RES_Cityscape_Year__c':
                this.cityscapeYearValue = value;
                break;
            case 'GenderIdentity':
                this.genderValue = value;
                break;
            case 'RES_Identification_Type__c':
                this.identificationTypeValue = value;
                break;
            case 'RES_Identification_Number__c':
                this.identificationNumberValue = value;
                break;
            case 'Company':
                this.companyValue = value;
                break;
            case 'Website':
                this.websiteValue = value;
                break;
            case 'RES_Corporate_Title__c':
                this.corporateTitleValue = value;
                break;
            case 'RES_CR_Number__c':
                this.crNumberValue = value;
                break;
            default:
                break;
        }
    }

    setGenderFromSalutation(salutation) {
        if (!this.isResidentialIndividual) {
            this.genderValue = '';
            return;
        }

        const selectedSalutation = (salutation || '').toLowerCase();

        if (!selectedSalutation) {
            this.genderValue = '';
            this.updateGenderFieldOnUi();
            this.clearFieldError('GenderIdentity');
            this.clearFieldError('Salutation');
            return;
        }

        if (this.isMaleSalutation()) {
            this.genderValue = this.getGenderValueByLabel('Male');
            this.updateGenderFieldOnUi();
            this.clearFieldError('GenderIdentity');
            this.clearFieldError('Salutation');
            return;
        }

        if (this.isFemaleSalutation()) {
            this.genderValue = this.getGenderValueByLabel('Female');
            this.updateGenderFieldOnUi();
            this.clearFieldError('GenderIdentity');
            this.clearFieldError('Salutation');
            return;
        }

        this.clearFieldError('Salutation');
    }

    isMaleSalutation() {
        const salutation = (this.salutationValue || '').toLowerCase();
        return salutation === 'mr.' || salutation === 'mr' || salutation === 'prince';
    }

    isFemaleSalutation() {
        const salutation = (this.salutationValue || '').toLowerCase();
        return salutation === 'ms.' || salutation === 'ms' || salutation === 'princess';
    }

    getGenderValueByLabel(label) {
        const matchingOption = this.genderOptions.find(
            (option) => (option.label || '').toLowerCase() === label.toLowerCase()
        );

        return matchingOption ? matchingOption.value : '';
    }

    getGenderLabelByValue(value) {
        const matchingOption = this.genderOptions.find(
            (option) => option.value === value
        );

        return matchingOption ? matchingOption.label : '';
    }

    updateGenderFieldOnUi() {
        window.setTimeout(() => {
            const genderField = this.template.querySelector('[data-field="GenderIdentity"]');
            if (genderField) {
                genderField.value = this.genderValue;
            }
        }, 0);
    }

    buildPayload() {
        const fieldValues = {};

        this.addToPayload(fieldValues, 'Salutation', this.salutationValue);
        this.addToPayload(fieldValues, 'FirstName', this.firstNameValue);
        this.addToPayload(fieldValues, 'MiddleName', this.middleNameValue);
        this.addToPayload(fieldValues, 'LastName', this.lastNameValue);
        this.addToPayload(
            fieldValues,
            'RES_Full_Arabic_Name__c',
            this.fullArabicNameValue
        );
        this.addToPayload(fieldValues, 'MobilePhone', this.mobileValue);
        this.addToPayload(fieldValues, 'Email', this.emailValue);
        this.addToPayload(fieldValues, 'LeadSource', this.leadSourceValue);
        this.addToPayload(
            fieldValues,
            'RES_Cityscape_Year__c',
            this.cityscapeYearValue
        );

        if (this.isResidentialIndividual === true) {
            this.addToPayload(fieldValues, 'GenderIdentity', this.genderValue);
            this.addToPayload(
                fieldValues,
                'RES_Identification_Type__c',
                this.identificationTypeValue
            );
            this.addToPayload(
                fieldValues,
                'RES_Identification_Number__c',
                this.identificationNumberValue
            );
        }

        if (this.isResidentialCompany === true) {
            this.addToPayload(fieldValues, 'Company', this.companyValue);
            this.addToPayload(fieldValues, 'Website', this.websiteValue);
            this.addToPayload(
                fieldValues,
                'RES_Corporate_Title__c',
                this.corporateTitleValue
            );
            this.addToPayload(fieldValues, 'RES_CR_Number__c', this.crNumberValue);
        }

        return fieldValues;
    }

    addToPayload(fieldValues, fieldApiName, value) {
        if (value !== null && value !== undefined && value !== '') {
            fieldValues[fieldApiName] = value;
        }
    }

    clearForm() {
        this.salutationValue = '';
        this.firstNameValue = '';
        this.middleNameValue = '';
        this.lastNameValue = '';
        this.fullArabicNameValue = '';
        this.mobileValue = '';
        this.emailValue = '';
        this.leadSourceValue = '';
        this.cityscapeYearValue = '';
        this.genderValue = '';
        this.identificationTypeValue = '';
        this.identificationNumberValue = '';
        this.companyValue = '';
        this.websiteValue = '';
        this.corporateTitleValue = '';
        this.crNumberValue = '';

        this.errors = {};
        this.showCityscapeYear = false;
        this.showIdentificationNumber = false;
        this.isSaving = false;
    }

    clearFieldError(field) {
        if (!this.errors[field]) {
            return;
        }

        const updatedErrors = { ...this.errors };
        delete updatedErrors[field];
        this.errors = updatedErrors;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.body?.fieldErrors) {
            return Object.values(error.body.fieldErrors)
                .flat()
                .map((fieldError) => fieldError.message)
                .join(', ');
        }

        return error?.message || 'An unexpected error occurred.';
    }

    get normalizedRtDevName() {
        return (this._rtDevName || '').toLowerCase().replaceAll(' ', '_');
    }

    get normalizedRtName() {
        return (this._rtName || '').toLowerCase().replaceAll(' ', '_');
    }

    get formTitle() {
        return `New Lead: ${this._rtName || ''}`;
    }

    get isResidentialIndividual() {
        return (
            this.normalizedRtDevName.includes('residential_individual') ||
            this.normalizedRtName.includes('residential_individual')
        );
    }

    get isResidentialCompany() {
        return (
            this.normalizedRtDevName.includes('residential_company') ||
            this.normalizedRtName.includes('residential_company')
        );
    }
}
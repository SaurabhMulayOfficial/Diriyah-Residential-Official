import { LightningElement, track, wire } from 'lwc';
import COMPANY_LOGO from '@salesforce/resourceUrl/CompanyLogo';
import SITE_BG from '@salesforce/resourceUrl/SiteBackground'; // Import Background
import getLeadRecordTypeIds from '@salesforce/apex/RES_EmployeeReferralController.getLeadRecordTypeIds';

export default class EmployeeReferralForm extends LightningElement {
    logoUrl = COMPANY_LOGO;
    bgUrl = SITE_BG; // Reference the background image

    @track isSuccess = false;
    @track showForm = false;
    @track leadType = ''; 
    
    individualRtId;
    companyRtId;

    @wire(getLeadRecordTypeIds)
    wiredRecordTypes({ error, data }) {
        if (data) {
            this.individualRtId = data.Individual;
            this.companyRtId = data.Company;
        } else if (error) {
            console.error('Error fetching record types', error);
        }
    }

    get typeOptions() {
        return [
            { label: 'Individual Lead', value: 'Individual' },
            { label: 'Company Lead', value: 'Company' }
        ];
    }

    get isNextDisabled() { return !this.leadType; }
    get selectedRecordTypeId() { return this.leadType === 'Individual' ? this.individualRtId : this.companyRtId; }
    get isIndividual() { return this.leadType === 'Individual'; }
    get isCompany() { return this.leadType === 'Company'; }

    handleTypeChange(event) { this.leadType = event.detail.value; }
    handleNext() { if (this.leadType) { this.showForm = true; } }
    handleBack() { this.showForm = false; }
    handleSuccess(event) { this.isSuccess = true; }
    handleReset() {
        this.isSuccess = false;
        this.showForm = false;
        this.leadType = '';
    }
    handleError(event) { console.error('Error Details:', JSON.stringify(event.detail)); }
}
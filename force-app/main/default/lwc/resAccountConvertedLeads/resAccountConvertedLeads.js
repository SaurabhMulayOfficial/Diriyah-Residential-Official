import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getConvertedLeadsByAccountId from '@salesforce/apex/RES_AccountConvertedLeadController.getConvertedLeadsByAccountId';

export default class ResAccountConvertedLeads extends NavigationMixin(LightningElement) {
    @api recordId;

    convertedLeads = [];
    totalCount = 0;
    isPersonAccount = false;
    isLoading = true;

    get hasRecords() {
        return this.convertedLeads && this.convertedLeads.length > 0;
    }

    get visibleLeads() {
        return this.convertedLeads.slice(0, 3);
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'RES_Account_Converted_Leads'
            },
            state: {
                c__accountId: this.recordId
            }
        });
    }

    @wire(getConvertedLeadsByAccountId, { accountId: '$recordId' })
    wiredConvertedLeads({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.totalCount = data.totalCount || 0;
            this.isPersonAccount = data.isPersonAccount || false;

            this.convertedLeads = (data.leads || []).map((leadRecord) => ({
                ...leadRecord,
                leadUrl: '/' + leadRecord.id,
                convertedDate: this.formatDate(leadRecord.convertedDate)
            }));
        } else if (error) {
            this.totalCount = 0;
            this.isPersonAccount = false;
            this.convertedLeads = [];
            console.error('Error loading account converted leads', JSON.stringify(error));
        }
    }

    formatDate(dateValue) {
        if (!dateValue) {
            return '';
        }

        const date = new Date(dateValue);

        return new Intl.DateTimeFormat('en-GB', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric'
        }).format(date);
    }
}
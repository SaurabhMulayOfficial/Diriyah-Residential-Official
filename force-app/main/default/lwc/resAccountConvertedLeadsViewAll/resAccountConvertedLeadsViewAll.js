import { LightningElement, wire } from 'lwc';
import {
    NavigationMixin,
    CurrentPageReference
} from 'lightning/navigation';

import getConvertedLeadsByAccountId from '@salesforce/apex/RES_AccountConvertedLeadController.getConvertedLeadsByAccountId';
import getAccountName from '@salesforce/apex/RES_AccountConvertedLeadController.getAccountName';

export default class ResAccountConvertedLeadsViewAll extends NavigationMixin(LightningElement) {
    accountId;
    accountName = '';
    convertedLeads = [];
    totalCount = 0;
    isPersonAccount = false;
    isLoading = true;

    get columns() {

        const nameColumn = {
            label: 'Name',
            fieldName: 'leadUrl',
            type: 'url',
            typeAttributes: {
                label: {
                    fieldName: 'name'
                },
                target: '_blank'
            }
        };
    
        const convertedDate = {
            label: 'Converted Date',
            fieldName: 'convertedDate',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
            }
        };
    
        if (this.isPersonAccount) {
    
            return [
                nameColumn,
                {
                    label: 'Email',
                    fieldName: 'email',
                    type: 'email'
                },
                {
                    label: 'Mobile',
                    fieldName: 'mobilePhone',
                    type: 'phone'
                },
                convertedDate
            ];
        }
    
        return [
            nameColumn,
            {
                label: 'Email',
                fieldName: 'email',
                type: 'email'
            },
            {
                label: 'Mobile',
                fieldName: 'mobilePhone',
                type: 'phone'
            },
            convertedDate
        ];
    }

    get hasRecords() {
        return this.convertedLeads && this.convertedLeads.length > 0;
    }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.accountId = currentPageReference.state.c__accountId;
            this.loadData();
        }
    }

    async loadData() {
        if (!this.accountId) {
            this.isLoading = false;
            return;
        }

        this.isLoading = true;

        try {
            const [accountName, result] = await Promise.all([
                getAccountName({ accountId: this.accountId }),
                getConvertedLeadsByAccountId({ accountId: this.accountId })
            ]);

            this.accountName = accountName || '';
            this.totalCount = result?.totalCount || 0;
            this.isPersonAccount = result?.isPersonAccount || false;

            this.convertedLeads = (result?.leads || []).map((leadRecord) => ({
                ...leadRecord,
                leadUrl: '/' + leadRecord.id
            }));
        } catch (error) {
            this.accountName = '';
            this.totalCount = 0;
            this.isPersonAccount = false;
            this.convertedLeads = [];
            console.error('Error loading converted leads view all', JSON.stringify(error));
        } finally {
            this.isLoading = false;
        }
    }

    navigateToAccountsList() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Account',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });
    }

    navigateToAccountRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }
}
import { LightningElement, wire } from 'lwc';
import getConvertedLeads from '@salesforce/apex/RES_ConvertedLeadController.getConvertedLeads';

export default class ResConvertedLeads extends LightningElement {
    heading = 'Converted Leads';
    convertedLeads = [];
    isLoading = true;

    columns = [
        {
            label: 'Lead Name',
            fieldName: 'leadUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'name' },
                target: '_blank'
            }
        },
        { label: 'Owner', fieldName: 'ownerName', type: 'text' },
        { label: 'Status', fieldName: 'statusLabel', type: 'text' },
        { label: 'Company', fieldName: 'company', type: 'text' },
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Mobile', fieldName: 'mobilePhone', type: 'phone' },
        { label: 'Lead Source', fieldName: 'leadSourceLabel', type: 'text' },
        {
            label: 'Created Date',
            fieldName: 'createdDate',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
            }
        },
        {
            label: 'Converted Date',
            fieldName: 'convertedDate',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
            }
        }    
    ];

    get hasRecords() {
        return this.convertedLeads && this.convertedLeads.length > 0;
    }

    @wire(getConvertedLeads)
    wiredConvertedLeads({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.heading = data.heading || 'Converted Leads';

            this.convertedLeads = (data.leads || []).map((leadRecord) => ({
                ...leadRecord,
                leadUrl: '/' + leadRecord.id
            }));
        } else if (error) {
            this.convertedLeads = [];
            console.error('Error loading converted leads', JSON.stringify(error));
        }
    }
}
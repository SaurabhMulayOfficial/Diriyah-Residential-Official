import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import APPROVAL_STATUS_FIELD from '@salesforce/schema/Contract.RES_Approval_Status__c';

const FIELDS = [APPROVAL_STATUS_FIELD];

export default class ResToastMessage extends LightningElement {
    @api recordId;
    initialized = false;
    previousStatus;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredContract({ error, data }) {
        if (data) {
            const currentStatus = data.fields.RES_Approval_Status__c.value;
            if (!this.initialized) {
                this.previousStatus = currentStatus;
                this.initialized = true;
                return;
            }
            if (this.previousStatus !== currentStatus && currentStatus === 'Pending Finance Approval') {
                this.showToast(
                    'Success',
                    'Record has been successfully submitted for approval',
                    'success'
                );
            }
            else if (this.previousStatus !== currentStatus && currentStatus === 'Pending Operations') {
                this.showToast(
                    'Success',
                    'Record has been successfully submitted for approval',
                    'success'
                );
            }
            this.previousStatus = currentStatus;
        } else if (error) {
            console.error('Error loading Contract:', error);
        }
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
}
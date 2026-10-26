import { LightningElement, api } from 'lwc';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';

export default class ResRefreshPageAfterApprovalSubmission extends LightningElement {
    @api recordId;
    hasRefreshed = false;

    renderedCallback() {
        if (this.hasRefreshed || !this.recordId) return;
        this.hasRefreshed = true;
        getRecordNotifyChange([{ recordId: this.recordId }]);
    }
}
import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import BANNER_FIELD from '@salesforce/schema/Product2.RES_Payment_Plan_Modification_Banner__c';

const FIELDS = [BANNER_FIELD];
const LINE_DELIMITER = '~~NL~~';

export default class ResPaymentPlanModificationBanner extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    product;

    get bannerLines() {
        const text = getFieldValue(this.product?.data, BANNER_FIELD);
        return text ? text.split(LINE_DELIMITER) : [];
    }

    get isPending() {
        return this.bannerLines.length > 0;
    }
}

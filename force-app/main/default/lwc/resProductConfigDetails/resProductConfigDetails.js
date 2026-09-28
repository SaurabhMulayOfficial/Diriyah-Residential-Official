import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import PRODUCT_OBJECT from '@salesforce/schema/Product2';

// Picklist fields in the "Fixtures / Fittings" tab, shown as label: value when populated
const PICKLIST_FIELDS = ['RES_Orientation__c', 'RES_ID_Finish__c', 'RES_Condition__c'];

// Checkbox fields shown in the "Fixtures / Fittings" tab of the Product record page, in page order
const FITTING_FIELDS = [
    'RES_Storeroom__c',
    'RES_Elevated__c',
    'RES_Terrace__c',
    'RES_Roof_Terrace__c',
    'RES_Maids_Room__c',
    'RES_Wadi_View__c',
    'RES_Golf_View__c',
    'RES_Furnished__c',
    'RES_Entry_Courtyard__c',
    'RES_Garage__c',
    'RES_Pool__c',
    'RES_Drivers_Room__c',
    'RES_Panoramic_View__c',
    'RES_Private__c'
];

const MEASUREMENT_TYPE = 'RES_Measurement__c.RES_Measurement_Type__c';
const MEASUREMENT_AMOUNT = 'RES_Measurement__c.RES_Measurement_Amount__c';
const MEASUREMENT_FROM = 'RES_Measurement__c.RES_Measurement_From__c';
const MEASUREMENT_TO = 'RES_Measurement__c.RES_Measurement_To__c';

const MEASUREMENT_COLUMNS = [
    { label: 'Measurement Type', fieldName: 'type', type: 'text' },
    { label: 'Amount', fieldName: 'amount', type: 'number', cellAttributes: { alignment: 'left' } }
];

export default class ResProductConfigDetails extends LightningElement {
    @api productId;

    measurementColumns = MEASUREMENT_COLUMNS;
    productInfo;
    product;
    measurements = [];
    error;

    @wire(getObjectInfo, { objectApiName: PRODUCT_OBJECT })
    wiredObjectInfo({ data }) {
        if (data) {
            this.productInfo = data;
        }
    }

    // optionalFields so a user missing FLS on one field still sees the rest
    @wire(getRecord, { recordId: '$productId', optionalFields: [...PICKLIST_FIELDS, ...FITTING_FIELDS].map((f) => `Product2.${f}`) })
    wiredProduct({ data, error }) {
        if (data) {
            this.product = data;
        } else if (error) {
            this.error = this.reduceError(error);
        }
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$productId',
        relatedListId: 'Measurements__r',
        fields: [MEASUREMENT_TYPE, MEASUREMENT_AMOUNT, MEASUREMENT_FROM, MEASUREMENT_TO],
        sortBy: [MEASUREMENT_TYPE],
        pageSize: 200
    })
    wiredMeasurements({ data, error }) {
        if (data) {
            const today = this.todayInUserTimeZone();
            // Blank From/To are treated as open-ended validity
            this.measurements = data.records
                .filter((rec) => {
                    const from = rec.fields.RES_Measurement_From__c.value;
                    const to = rec.fields.RES_Measurement_To__c.value;
                    return (!from || from <= today) && (!to || to >= today);
                })
                .map((rec) => ({
                    id: rec.id,
                    type: rec.fields.RES_Measurement_Type__c.displayValue || rec.fields.RES_Measurement_Type__c.value,
                    amount: rec.fields.RES_Measurement_Amount__c.value
                }));
        } else if (error) {
            this.error = this.reduceError(error);
        }
    }

    get picklistValues() {
        if (!this.product) {
            return [];
        }
        return PICKLIST_FIELDS.filter((f) => this.product.fields[f]?.value).map((f) => ({
            apiName: f,
            label: this.productInfo?.fields[f]?.label || f,
            value: this.product.fields[f].displayValue || this.product.fields[f].value
        }));
    }

    get hasPicklistValues() {
        return this.picklistValues.length > 0;
    }

    get fittings() {
        if (!this.product) {
            return [];
        }
        return FITTING_FIELDS.filter((f) => this.product.fields[f]?.value === true).map((f) => ({
            apiName: f,
            label: this.productInfo?.fields[f]?.label || f
        }));
    }

    get hasFittings() {
        return this.fittings.length > 0;
    }

    get hasAnyFittingData() {
        return this.hasPicklistValues || this.hasFittings;
    }

    get hasMeasurements() {
        return this.measurements.length > 0;
    }

    get isLoading() {
        return this.productId && !this.product && !this.error;
    }

    // en-CA formats as YYYY-MM-DD, matching UI API date values
    todayInUserTimeZone() {
        return new Intl.DateTimeFormat('en-CA', { timeZone: TIME_ZONE }).format(new Date());
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unable to load product details.';
    }
}

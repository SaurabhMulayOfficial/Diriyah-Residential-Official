import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getInstallments from '@salesforce/apex/RES_InstallmentListController.getInstallments';

const COLUMNS = [
    { label: '#', fieldName: 'sequence', type: 'number', initialWidth: 60 },
    {
        label: 'Installment',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    { label: 'Product Code', fieldName: 'productCode' },
    { label: 'Condition Type', fieldName: 'conditionType' },
    { label: 'Payment Type', fieldName: 'paymentType' },
    { label: 'Percentage', fieldName: 'percentFraction', type: 'percent', typeAttributes: { maximumFractionDigits: 2 } },
    { label: 'POC %', fieldName: 'pocFraction', type: 'percent', typeAttributes: { maximumFractionDigits: 2 } },
    { label: 'Condition Months', fieldName: 'conditionMonths', type: 'number' },
    { label: 'Condition Days', fieldName: 'conditionDays', type: 'number' },
    {
        label: 'Due Date',
        fieldName: 'dueDate',
        type: 'date-local',
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
    },
    {
        label: 'Amount',
        fieldName: 'amount',
        type: 'currency',
        typeAttributes: { currencyCode: { fieldName: 'currencyIsoCode' }, currencyDisplayAs: 'code' }
    },
    { label: 'Active', fieldName: 'isActive', type: 'boolean', initialWidth: 80 }
];

export default class ResPaymentPlanInstallmentList extends LightningElement {
    @api recordId;
    @api cardTitle = 'Installments';

    columns = COLUMNS;
    installments = [];
    error;
    isLoaded = false;
    wiredResult;

    @wire(getInstallments, { paymentPlanId: '$recordId' })
    wiredInstallments(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.installments = data;
            this.error = undefined;
            this.isLoaded = true;
        } else if (error) {
            this.installments = [];
            this.error = error?.body?.message || error?.message || 'Could not load the payment plan installments.';
            this.isLoaded = true;
        }
    }

    // Percent columns expect a fraction; Salesforce Percent fields store whole numbers
    get rows() {
        return this.installments.map((row) => ({
            ...row,
            recordUrl: `/lightning/r/Product2/${row.productId}/view`,
            percentFraction: row.percentage == null ? null : row.percentage / 100,
            pocFraction: row.pocPercentage == null ? null : row.pocPercentage / 100
        }));
    }

    get hasRows() {
        return this.installments.length > 0;
    }

    get isLoading() {
        return !this.isLoaded;
    }

    get title() {
        return this.isLoaded ? `${this.cardTitle} (${this.installments.length})` : this.cardTitle;
    }

    get totalPercentFraction() {
        return this.installments.reduce((sum, row) => sum + (row.percentage ?? 0), 0) / 100;
    }

    handleRefresh() {
        this.isLoaded = false;
        return refreshApex(this.wiredResult).finally(() => {
            this.isLoaded = true;
        });
    }
}

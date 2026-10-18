import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getInstallments from '@salesforce/apex/RES_InstallmentListController.getInstallments';
import { INSTALLMENT_COLUMNS, toInstallmentRows, errorMessage } from 'c/resInstallmentTable';

export default class ResPaymentPlanInstallmentList extends LightningElement {
    @api recordId;
    @api cardTitle = 'Installments';

    columns = INSTALLMENT_COLUMNS;
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
            this.error = errorMessage(error, 'Could not load the payment plan installments.');
            this.isLoaded = true;
        }
    }

    get rows() {
        return toInstallmentRows(this.installments);
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

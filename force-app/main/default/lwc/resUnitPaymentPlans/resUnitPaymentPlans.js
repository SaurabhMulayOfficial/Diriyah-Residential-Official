import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPaymentPlans from '@salesforce/apex/RES_InstallmentListController.getPaymentPlans';
import { INSTALLMENT_COLUMNS, toInstallmentRows, recordUrl, toFraction, errorMessage } from 'c/resInstallmentTable';

export default class ResUnitPaymentPlans extends LightningElement {
    @api recordId;
    @api cardTitle = 'Payment Plans';

    columns = INSTALLMENT_COLUMNS;
    paymentPlans = [];
    activeSections = [];
    error;
    isLoaded = false;
    hasOpenedDefault = false;
    wiredResult;

    @wire(getPaymentPlans, { unitId: '$recordId' })
    wiredPaymentPlans(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.paymentPlans = data;
            this.error = undefined;
            // Open the default plan on first load only, so a refresh keeps the user's open sections
            if (!this.hasOpenedDefault) {
                this.activeSections = data.filter((plan) => plan.isDefault).map((plan) => plan.productId);
                this.hasOpenedDefault = true;
            }
            this.isLoaded = true;
        } else if (error) {
            this.paymentPlans = [];
            this.error = errorMessage(error, 'Could not load the payment plans.');
            this.isLoaded = true;
        }
    }

    get plans() {
        return this.paymentPlans.map((plan) => ({
            ...plan,
            label: this.sectionLabel(plan),
            recordUrl: recordUrl(plan.productId),
            duration: this.duration(plan),
            statusLabel: plan.isActive ? 'Active' : 'Inactive',
            statusClass: plan.isActive ? 'slds-theme_success' : '',
            rows: toInstallmentRows(plan.installments),
            hasInstallments: plan.installments?.length > 0,
            totalPercentFraction: toFraction(plan.totalPercentage)
        }));
    }

    sectionLabel(plan) {
        const count = plan.installments?.length ?? 0;
        const suffix = plan.isDefault ? ' · Default' : '';
        return `${plan.name} (${count} installment${count === 1 ? '' : 's'})${suffix}`;
    }

    duration(plan) {
        const parts = [];
        if (plan.numberOfYears != null) {
            parts.push(`${plan.numberOfYears} year(s)`);
        }
        if (plan.numberOfMonths != null) {
            parts.push(`${plan.numberOfMonths} month(s)`);
        }
        return parts.join(', ');
    }

    get hasPlans() {
        return this.paymentPlans.length > 0;
    }

    get isLoading() {
        return !this.isLoaded;
    }

    get title() {
        return this.isLoaded ? `${this.cardTitle} (${this.paymentPlans.length})` : this.cardTitle;
    }

    handleSectionToggle(event) {
        this.activeSections = event.detail.openSections;
    }

    handleRefresh() {
        this.isLoaded = false;
        return refreshApex(this.wiredResult).finally(() => {
            this.isLoaded = true;
        });
    }
}

import { LightningElement, api } from 'lwc';
import getPreview from '@salesforce/apex/RES_PaymentPlanPreviewController.getPreview';

export default class ResPaymentPlanPreview extends LightningElement {
    @api contextId;
    @api rootProductId;

    preview;
    error;
    isLoading = false;
    requestCount = 0;
    _isApiInProgress = false;

    // Reload when a configurator call (option change, pricing) finishes so the context is up to date
    @api
    get isApiInProgress() {
        return this._isApiInProgress;
    }
    set isApiInProgress(value) {
        const finished = this._isApiInProgress && !value;
        this._isApiInProgress = value;
        if (finished) {
            this.load();
        }
    }

    connectedCallback() {
        this.load();
    }

    async load() {
        if (!this.contextId) {
            return;
        }
        const request = ++this.requestCount;
        this.isLoading = true;
        try {
            const result = await getPreview({ contextId: this.contextId, rootProductId: this.rootProductId });
            if (request === this.requestCount) {
                this.preview = result;
                this.error = undefined;
            }
        } catch (e) {
            if (request === this.requestCount) {
                this.error = e?.body?.message || e?.message || 'Could not load the payment plan installments.';
            }
        } finally {
            if (request === this.requestCount) {
                this.isLoading = false;
            }
        }
    }

    get hasInstallments() {
        return this.preview?.installments?.length > 0;
    }

    get title() {
        return this.preview?.planName ? `Installments: ${this.preview.planName}` : 'Installments';
    }

    get currencyCode() {
        return this.preview?.currencyIsoCode || 'SAR';
    }

    get showUnpricedHint() {
        return this.hasInstallments && !this.preview.isPriced;
    }

    // lightning-formatted-number expects a fraction for percent style
    get rows() {
        return (this.preview?.installments || []).map((row, index) => ({
            ...row,
            key: row.productId || String(index),
            number: row.sequence ?? index + 1,
            percentFraction: row.percentage == null ? null : row.percentage / 100,
            hasAmount: row.amount != null
        }));
    }

    get totalPercentFraction() {
        return (this.preview?.totalPercentage ?? 0) / 100;
    }

    get hasTotalAmount() {
        return this.preview?.totalAmount != null;
    }
}

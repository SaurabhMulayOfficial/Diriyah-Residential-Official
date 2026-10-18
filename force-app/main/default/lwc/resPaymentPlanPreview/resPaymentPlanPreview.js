import { LightningElement, api } from 'lwc';
import getPreview from '@salesforce/apex/RES_PaymentPlanPreviewController.getPreview';

export default class ResPaymentPlanPreview extends LightningElement {
    @api rootProductId;
    // Unused; kept because earlier flow versions bind them
    @api contextId;
    @api isApiInProgress;

    preview;
    error;
    isLoading = false;
    requestCount = 0;
    selectionKey;
    _salesTransactionItems;
    _optionGroups;

    // Both are pushed by the configurator on every change; a different product set means the selection changed
    @api
    get salesTransactionItems() {
        return this._salesTransactionItems;
    }
    set salesTransactionItems(value) {
        this._salesTransactionItems = value;
        this.refresh();
    }

    @api
    get optionGroups() {
        return this._optionGroups;
    }
    set optionGroups(value) {
        this._optionGroups = value;
        this.refresh();
    }

    refresh() {
        const itemProductIds = (this._salesTransactionItems || []).map((item) => item?.product);
        const productIds = [...new Set([...selectedOptionIds(this._optionGroups), ...itemProductIds].filter((id) => typeof id === 'string' && id))];
        const key = productIds.slice().sort().join(',');
        if (key !== this.selectionKey) {
            this.selectionKey = key;
            this.load(productIds);
        }
    }

    async load(productIds) {
        const request = ++this.requestCount;
        if (!productIds.length) {
            this.preview = undefined;
            this.error = undefined;
            return;
        }
        this.isLoading = true;
        try {
            const result = await getPreview({ selectedProductIds: productIds, rootProductId: this.rootProductId });
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

    get showNoAmountHint() {
        return this.hasInstallments && this.preview.totalAmount == null;
    }

    // lightning-formatted-number expects a fraction for percent style
    get rows() {
        return (this.preview?.installments || []).map((row, index) => ({
            ...row,
            key: row.productId || String(index),
            number: row.sequence ?? index + 1,
            percentFraction: row.percentage == null ? null : row.percentage / 100,
            pocFraction: row.pocPercentage == null ? null : row.pocPercentage / 100,
            hasPoc: row.pocPercentage != null,
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

// Ids of the selected options in the configurator's option groups, including nested groups
function selectedOptionIds(groups) {
    const ids = [];
    (groups || []).forEach((group) => {
        (group?.components || []).forEach((component) => {
            if (component?.isSelected && component.id) {
                ids.push(component.id);
            }
            ids.push(...selectedOptionIds(component?.productComponentGroups));
        });
        ids.push(...selectedOptionIds(group?.childGroups));
    });
    return ids;
}

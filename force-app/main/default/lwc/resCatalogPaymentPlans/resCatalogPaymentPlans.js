import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPaymentPlans from '@salesforce/apex/RES_CatalogPaymentPlansController.getPaymentPlans';
import { recordUrl, errorMessage } from 'c/resInstallmentTable';

const COLUMNS = [
    {
        label: 'Payment Plan',
        fieldName: 'recordUrl',
        type: 'url',
        initialWidth: 300,
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    { label: 'Version', fieldName: 'versionLabel', initialWidth: 100 },
    { label: 'Status', fieldName: 'statusLabel', initialWidth: 100, cellAttributes: { class: { fieldName: 'statusClass' } } },
    { label: 'Approval Status', fieldName: 'approvalStatus' },
    { label: 'Installments', fieldName: 'installmentCount', type: 'number', initialWidth: 120 },
    { label: 'Valid From', fieldName: 'validFrom', type: 'date-local' },
    { label: 'Validity End Date', fieldName: 'validityEndDate', type: 'date-local' },
    { label: 'Price Option', fieldName: 'priceOption' },
    { label: 'Product Code', fieldName: 'productCode' }
];

/**
 * Catalog record page tab: every Payment Plan of the catalog, one row per plan showing its latest version,
 * with earlier POC versions (and the original plan) nested underneath. "Active only" hides inactive versions.
 */
export default class ResCatalogPaymentPlans extends LightningElement {
    @api recordId;
    @api cardTitle = 'Payment Plans';

    columns = COLUMNS;
    families = [];
    activeOnly = false;
    expandedRows = [];
    error;
    isLoaded = false;
    wiredResult;

    @wire(getPaymentPlans, { catalogId: '$recordId' })
    wiredPlans(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.families = data;
            this.error = undefined;
            this.isLoaded = true;
            this.expandAll();
        } else if (error) {
            this.families = [];
            this.error = errorMessage(error, 'Could not load the payment plans.');
            this.isLoaded = true;
        }
    }

    // Top row = latest (visible) version of each plan; older versions become its children
    get rows() {
        return this.families
            .map((family) => family.versions.filter((v) => !this.activeOnly || v.isActive).map((v) => this.toRow(v)))
            .filter((versions) => versions.length > 0)
            .map(([latest, ...older]) => (older.length ? { ...latest, _children: older } : latest))
            .sort((a, b) => Number(b.isActive) - Number(a.isActive) || a.name.localeCompare(b.name));
    }

    toRow(version) {
        return {
            ...version,
            recordUrl: recordUrl(version.id),
            versionLabel: version.version == null ? 'Original' : `v${Number(version.version)}`,
            statusLabel: version.isActive ? 'Active' : 'Inactive',
            statusClass: version.isActive ? 'slds-text-color_success' : 'slds-text-color_weak'
        };
    }

    expandAll() {
        this.expandedRows = this.families.flatMap((family) => family.versions.map((v) => v.id));
    }

    handleToggle(event) {
        this.activeOnly = event.target.checked;
        this.expandAll();
    }

    handleExpandAll() {
        this.expandAll();
    }

    handleCollapseAll() {
        this.expandedRows = [];
    }

    handleToggleRow(event) {
        this.expandedRows = event.detail.isExpanded
            ? [...this.expandedRows, event.detail.name]
            : this.expandedRows.filter((id) => id !== event.detail.name);
    }

    handleRefresh() {
        return refreshApex(this.wiredResult);
    }

    get activeCount() {
        return this.families.reduce((sum, family) => sum + family.versions.filter((v) => v.isActive).length, 0);
    }

    get totalCount() {
        return this.families.reduce((sum, family) => sum + family.versions.length, 0);
    }

    get summary() {
        return `${this.families.length} plan${this.families.length === 1 ? '' : 's'} · ${this.totalCount} version${
            this.totalCount === 1 ? '' : 's'
        } · ${this.activeCount} active`;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isLoading() {
        return !this.isLoaded;
    }

    get emptyMessage() {
        return this.activeOnly ? 'No active payment plans for this catalog.' : 'No payment plans for this catalog.';
    }
}

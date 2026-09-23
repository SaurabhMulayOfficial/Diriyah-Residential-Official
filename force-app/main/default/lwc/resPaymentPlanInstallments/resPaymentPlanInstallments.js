import { LightningElement, api } from 'lwc';

const MAX_INSTALLMENTS = 24;
const MIN_INSTALLMENTS_TO_START = 2;
const PERCENTAGE_TOLERANCE = 0.01;
const PERCENTAGE_TARGET = 100;

/**
 * Flow screen component for the "Create Payment Plan" flow (RES_Create_Payment_Plan).
 * Lets a non-admin configurator build the installment schedule as an editable, reorderable
 * table (percentage, POC %, due date) instead of typing one flow screen per installment,
 * and blocks Next/Finish until the percentages add up to 100% - the exact validation gap
 * seen in the org's own incomplete sample Payment Plan bundle.
 */
export default class ResPaymentPlanInstallments extends LightningElement {
    @api planName;

    rows = [];
    nextRowKey = 1;

    @api
    get installmentsJson() {
        return JSON.stringify(this.toPayload());
    }
    set installmentsJson(value) {
        const parsedRows = this.parseInitial(value);
        this.rows = parsedRows.length > 0 ? parsedRows : this.rows;
    }

    connectedCallback() {
        if (!this.rows || this.rows.length === 0) {
            for (let i = 0; i < MIN_INSTALLMENTS_TO_START; i++) {
                this.addRow();
            }
        }
    }

    parseInitial(value) {
        if (!value) {
            return [];
        }
        try {
            const parsed = JSON.parse(value);
            return parsed.map((row, idx) => ({
                key: this.nextRowKey++,
                name: row.name || '',
                percentage: row.percentage != null ? row.percentage : null,
                pocPercentage: row.pocPercentage != null ? row.pocPercentage : null,
                dueDate: row.dueDate || null,
                sequence: row.sequence != null ? row.sequence : idx + 1
            }));
        } catch (e) {
            return [];
        }
    }

    addRow() {
        if (this.rows.length >= MAX_INSTALLMENTS) {
            return;
        }
        this.rows = [
            ...this.rows,
            { key: this.nextRowKey++, name: '', percentage: null, pocPercentage: null, dueDate: null, sequence: this.rows.length + 1 }
        ];
    }

    handleAddRow() {
        this.addRow();
    }

    handleRemoveRow(event) {
        const key = Number(event.currentTarget.dataset.key);
        this.rows = this.rows.filter((row) => row.key !== key);
        this.renumber();
    }

    handleMoveUp(event) {
        this.moveRow(Number(event.currentTarget.dataset.key), -1);
    }

    handleMoveDown(event) {
        this.moveRow(Number(event.currentTarget.dataset.key), 1);
    }

    moveRow(key, direction) {
        const index = this.rows.findIndex((row) => row.key === key);
        const newIndex = index + direction;
        if (index === -1 || newIndex < 0 || newIndex >= this.rows.length) {
            return;
        }
        const updated = [...this.rows];
        const [movedRow] = updated.splice(index, 1);
        updated.splice(newIndex, 0, movedRow);
        this.rows = updated;
        this.renumber();
    }

    renumber() {
        this.rows = this.rows.map((row, idx) => ({ ...row, sequence: idx + 1 }));
    }

    handleFieldChange(event) {
        const key = Number(event.target.dataset.key);
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (field === 'percentage' || field === 'pocPercentage') {
            value = value === '' ? null : Number(value);
        }
        this.rows = this.rows.map((row) => (row.key === key ? { ...row, [field]: value } : row));
    }

    get totalPercentage() {
        return this.rows.reduce((sum, row) => sum + (row.percentage || 0), 0);
    }

    get totalPercentageDisplay() {
        return this.totalPercentage.toFixed(2);
    }

    get isTotalValid() {
        return Math.abs(this.totalPercentage - PERCENTAGE_TARGET) <= PERCENTAGE_TOLERANCE;
    }

    get totalBadgeClass() {
        return this.isTotalValid
            ? 'slds-text-heading_small slds-text-color_success'
            : 'slds-text-heading_small slds-text-color_error';
    }

    get cannotRemoveRows() {
        return this.rows.length <= 1;
    }

    get isRowLimitReached() {
        return this.rows.length >= MAX_INSTALLMENTS;
    }

    toPayload() {
        return this.rows.map((row) => ({
            name: row.name,
            percentage: row.percentage,
            pocPercentage: row.pocPercentage,
            dueDate: row.dueDate,
            sequence: row.sequence
        }));
    }

    @api
    validate() {
        const errors = [];

        if (this.rows.length === 0) {
            errors.push('Add at least one installment.');
        }

        this.rows.forEach((row) => {
            if (!row.name || !row.name.trim()) {
                errors.push(`Installment ${row.sequence}: enter a name.`);
            }
            if (row.percentage == null || row.percentage <= 0 || row.percentage > 100) {
                errors.push(`Installment ${row.sequence}: enter a percentage greater than 0 and no more than 100.`);
            }
        });

        if (!this.isTotalValid) {
            errors.push(`Installment percentages must add up to 100% (currently ${this.totalPercentageDisplay}%).`);
        }

        if (errors.length > 0) {
            return { isValid: false, errorMessage: errors.join(' ') };
        }
        return { isValid: true };
    }
}
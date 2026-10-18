import { LightningElement, api } from 'lwc';

const MAX_INSTALLMENTS = 24;
const MIN_INSTALLMENTS_TO_START = 2;
const PERCENTAGE_TOLERANCE = 0.01;
const PERCENTAGE_TARGET = 100;
const PHASE_ON_PLAN = 'On-Plan';
const PHASE_OFF_PLAN = 'Off-Plan';
const ON_PLAN_POC_PERCENTAGE = 100;
const MONTHS_PER_YEAR = 12;
const NUMERIC_FIELDS = ['percentage', 'pocPercentage', 'conditionMonths', 'conditionDays'];
const CONDITION_TYPE_OPTIONS = [
    { label: 'Reservation', value: 'Y001' },
    { label: 'Down payment', value: 'Y002' },
    { label: 'Installments', value: 'Y003' },
    { label: 'Final Payment', value: 'Y004' }
];

/**
 * Flow screen component for the "Create Payment Plan" flow (RES_Create_Payment_Plan).
 * Lets a non-admin configurator build the installment schedule as an editable, reorderable
 * table (installment type, percentage, POC %, condition months/days) instead of typing one flow screen per installment,
 * and blocks Next/Finish until the percentages add up to 100% - the exact validation gap
 * seen in the org's own incomplete sample Payment Plan bundle.
 */
export default class ResPaymentPlanInstallments extends LightningElement {
    @api planName;
    // Caps how far the last installment can fall: Condition Months/Days can't exceed numberOfYears x 12 months
    @api numberOfYears;

    rows = [];
    nextRowKey = 1;
    _developmentPhase;

    // Development Phase of the selected catalog: On-Plan locks POC at 100%, Off-Plan makes POC mandatory
    @api
    get developmentPhase() {
        return this._developmentPhase;
    }
    set developmentPhase(value) {
        this._developmentPhase = value;
        this.applyPhaseDefaults();
    }

    get isOnPlan() {
        return this._developmentPhase === PHASE_ON_PLAN;
    }

    get isOffPlan() {
        return this._developmentPhase === PHASE_OFF_PLAN;
    }

    get pocPlaceholder() {
        return this.isOffPlan ? 'Required' : 'Optional';
    }

    applyPhaseDefaults() {
        if (this.isOnPlan) {
            this.rows = this.rows.map((row) => ({ ...row, pocPercentage: ON_PLAN_POC_PERCENTAGE }));
        }
    }

    @api
    get installmentsJson() {
        return JSON.stringify(this.toPayload());
    }
    set installmentsJson(value) {
        const parsedRows = this.parseInitial(value);
        this.rows = parsedRows.length > 0 ? parsedRows : this.rows;
        this.applyPhaseDefaults();
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
                percentage: row.percentage != null ? row.percentage : null,
                pocPercentage: row.pocPercentage != null ? row.pocPercentage : null,
                conditionType: row.conditionType || null,
                conditionMonths: row.conditionMonths != null ? row.conditionMonths : null,
                conditionDays: row.conditionDays != null ? row.conditionDays : null,
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
            {
                key: this.nextRowKey++,
                percentage: null,
                pocPercentage: this.isOnPlan ? ON_PLAN_POC_PERCENTAGE : null,
                conditionType: null,
                conditionMonths: null,
                conditionDays: null,
                sequence: this.rows.length + 1
            }
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
        let value = event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (NUMERIC_FIELDS.includes(field)) {
            value = value === '' || value == null ? null : Number(value);
        }
        this.rows = this.rows.map((row) => (row.key === key ? { ...row, [field]: value } : row));
    }

    // Relative due date (today + condition months/days) used only to compare installments; Apex sets the real one from Valid From or the quote configuration date
    dueDateFor(row) {
        if (row.conditionMonths == null) {
            return null;
        }
        const now = new Date();
        const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
        const due = this.addMonths(today, row.conditionMonths) + (row.conditionDays || 0) * 86400000;
        return new Date(due).toISOString().slice(0, 10);
    }

    // Mirrors Apex Date.addMonths: clamps to the last day of the target month
    addMonths(utcMillis, months) {
        const date = new Date(utcMillis);
        const target = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + months, 1));
        const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
        target.setUTCDate(Math.min(date.getUTCDate(), lastDay));
        return target.getTime();
    }

    get maxMonths() {
        return this.numberOfYears ? this.numberOfYears * MONTHS_PER_YEAR : null;
    }

    get latestDueDate() {
        return this.maxMonths ? this.dueDateFor({ conditionMonths: this.maxMonths, conditionDays: 0 }) : null;
    }

    get monthsLimitDisplay() {
        if (!this.maxMonths) {
            return null;
        }
        const last = this.rows.length ? this.rows[this.rows.length - 1] : null;
        const lastMonths = last && last.conditionMonths != null ? last.conditionMonths : 0;
        return `Last installment: ${lastMonths} of ${this.maxMonths} months`;
    }

    get conditionTypeOptions() {
        return CONDITION_TYPE_OPTIONS;
    }

    conditionTypeLabel(value) {
        const option = CONDITION_TYPE_OPTIONS.find((opt) => opt.value === value);
        return option ? option.label : value;
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
            percentage: row.percentage,
            pocPercentage: row.pocPercentage,
            conditionType: row.conditionType,
            conditionMonths: row.conditionMonths,
            conditionDays: row.conditionDays != null ? row.conditionDays : 0,
            sequence: row.sequence
        }));
    }

    @api
    validate() {
        const errors = [];

        if (this.rows.length === 0) {
            errors.push('Add at least one installment.');
        }

        const seenConditionKeys = new Map();
        const latestDueDate = this.latestDueDate;
        let previous = null;
        this.rows.forEach((row) => {
            if (!row.conditionType) {
                errors.push(`Installment ${row.sequence}: select an Installment Type.`);
            }
            if (row.conditionMonths == null || row.conditionMonths < 0 || !Number.isInteger(row.conditionMonths)) {
                errors.push(`Installment ${row.sequence}: Condition Months is required and must be a whole number of 0 or more.`);
            }
            if (row.conditionDays != null && (row.conditionDays < 0 || !Number.isInteger(row.conditionDays))) {
                errors.push(`Installment ${row.sequence}: Condition Days must be a whole number of 0 or more.`);
            }
            if (this.isOffPlan && (row.pocPercentage == null || row.pocPercentage < 0 || row.pocPercentage > 100)) {
                errors.push(`Installment ${row.sequence}: enter a POC % between 0 and 100 (required for Off-Plan catalogs).`);
            }
            const dueDate = this.dueDateFor(row);
            if (dueDate) {
                if (previous && previous.dueDate && dueDate < previous.dueDate) {
                    errors.push(`Installment ${row.sequence}: Condition Months/Days cannot fall before installment ${previous.sequence}.`);
                }
                if (latestDueDate && dueDate > latestDueDate) {
                    errors.push(
                        `Installment ${row.sequence}: Condition Months/Days cannot exceed ${this.maxMonths} months (${this.numberOfYears} year(s)).`
                    );
                }
                if (row.conditionType) {
                    const conditionKey = `${row.conditionType}|${dueDate}`;
                    if (seenConditionKeys.has(conditionKey)) {
                        errors.push(
                            `Installments ${seenConditionKeys.get(conditionKey)} and ${row.sequence} have the same Installment Type ` +
                                `(${this.conditionTypeLabel(row.conditionType)}) and the same Condition Months/Days.`
                        );
                    } else {
                        seenConditionKeys.set(conditionKey, row.sequence);
                    }
                }
            }
            previous = { sequence: row.sequence, dueDate };
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
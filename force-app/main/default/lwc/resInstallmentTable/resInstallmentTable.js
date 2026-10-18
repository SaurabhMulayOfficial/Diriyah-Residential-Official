// Shared installment datatable columns and row shaping for resPaymentPlanInstallmentList and resUnitPaymentPlans
export const INSTALLMENT_COLUMNS = [
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

export function recordUrl(productId) {
    return `/lightning/r/Product2/${productId}/view`;
}

// Percent columns expect a fraction; Salesforce Percent fields store whole numbers
export function toFraction(value) {
    return value == null ? null : value / 100;
}

export function toInstallmentRows(installments) {
    return (installments || []).map((row) => ({
        ...row,
        recordUrl: recordUrl(row.productId),
        percentFraction: toFraction(row.percentage),
        pocFraction: toFraction(row.pocPercentage)
    }));
}

export function errorMessage(error, fallback) {
    return error?.body?.message || error?.message || fallback;
}

import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import fireIntegrationEvents from '@salesforce/apex/RES_IntegrationSyncController.fireIntegrationEvents';

const SUCCESS_MESSAGE =
    'Sync request submitted. It runs asynchronously, so results are not shown here. ' +
    'If the integration fails you will receive a failure log; if it succeeds, the record’s Last Sync Date will be populated.';

export default class IntegrationSync extends LightningElement {
    serviceName;
    requestMethod = 'GET';
    triggerContext = 'I';
    recordIds = '';
    isBusy = false;
    message;
    isError = false;

    serviceOptions = [
        'Sales_Contract_Creation',
        'Sales_Contract_Update',
        'Sales_Contract_Termination',
        'Account_Sync',
        'Unit_Sync',
        'ProductCategory_Sync',
        'Measurement_Sync',
        'Measurement_Sync_Catalog',
        'ProductCatalog_Sync'
    ].map((v) => ({ label: v.replace(/_/g, ' '), value: v }));

    methodOptions = ['GET', 'POST', 'PATCH', 'PUT'].map((v) => ({ label: v, value: v }));

    get idCount() {
        return this.parseIds().length;
    }
    get insertClass() {
        return this.triggerContext === 'I' ? 'ctx-btn active' : 'ctx-btn';
    }
    get updateClass() {
        return this.triggerContext === 'U' ? 'ctx-btn active' : 'ctx-btn';
    }
    get messageClass() {
        return this.isError ? 'notice error' : 'notice success';
    }

    parseIds() {
        return [...new Set((this.recordIds || '').split(/[,;\s]+/).map((s) => s.trim()).filter(Boolean))];
    }

    handleChange(event) {
        this[event.target.dataset.field] = event.detail.value;
    }

    handleContext(event) {
        this.triggerContext = event.currentTarget.dataset.value;
    }

    async handleSubmit() {
        const inputs = [...this.template.querySelectorAll('.field')];
        const valid = inputs.reduce((ok, c) => {
            c.reportValidity();
            return ok && c.checkValidity();
        }, true);
        if (!valid) return;

        this.isBusy = true;
        this.message = null;
        try {
            const res = await fireIntegrationEvents({
                serviceName: this.serviceName,
                triggerContext: this.triggerContext,
                requestMethod: this.requestMethod,
                recordIds: this.recordIds
            });
            this.isError = false;
            this.message = `${res.eventsFired} event(s) fired. ${SUCCESS_MESSAGE}`;
            this.dispatchEvent(new ShowToastEvent({ title: 'Sync submitted', message: SUCCESS_MESSAGE, variant: 'success' }));
            this.recordIds = '';
        } catch (e) {
            this.isError = true;
            this.message = e?.body?.message || e?.message || 'Unexpected error.';
        } finally {
            this.isBusy = false;
        }
    }
}

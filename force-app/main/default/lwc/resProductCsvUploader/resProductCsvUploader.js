import { LightningElement, track, wire } from 'lwc';
import isInventoryFeatureEnabledLabel from '@salesforce/label/c.RES_Inventory_Config';
import getLayouts from '@salesforce/apex/RES_CsvIngestionController.getLayouts';
import startBatchFromCsv from '@salesforce/apex/RES_CsvIngestionController.startBatchFromCsv';
import getJobStatus from '@salesforce/apex/RES_CsvIngestionController.getJobStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const POLL_INTERVAL_MS = 3000;

export default class ResProductCsvUploader extends LightningElement {
    @track layoutOptions = [];
    @track selectedLayout;
    @track selectedOperation;

    operationOptions = [
        { label: 'Insert', value: 'Insert' },
        { label: 'Update', value: 'Update' }
    ];
    @track fileName = '';
    @track isLoading = false;
    @track uploadResult;
    @track jobStatus;

    layoutsByCode = {};
    rawCsvContent = '';
    pollTimer;

    // ------------------------------------------------------------------
    // Feature Flag Check
    // ------------------------------------------------------------------

    get isFeatureEnabled() {
        return isInventoryFeatureEnabledLabel ? isInventoryFeatureEnabledLabel.toLowerCase() === 'true' : false;
    }

    // ------------------------------------------------------------------
    // Layout options come from RES_Ingestion_Layout__mdt
    // ------------------------------------------------------------------

    @wire(getLayouts)
    wiredLayouts({ data, error }) {
        if (data) {
            this.layoutOptions = data.map((l) => ({ label: l.label, value: l.code }));
            this.layoutsByCode = data.reduce((acc, l) => ({ ...acc, [l.code]: l }), {});
            if (data.length === 1) {
                this.selectedLayout = data[0].code;
            }
        } else if (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    // ------------------------------------------------------------------
    // Selection
    // ------------------------------------------------------------------

    handleOperationChange(event) {
        this.selectedOperation = event.detail.value;
        this.resetResults();
    }

    handleLayoutChange(event) {
        this.selectedLayout = event.detail.value;
        this.resetResults();
    }

    handleFileSelected(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) {
            return;
        }

        this.resetResults();
        this.fileName = file.name;
        this.isLoading = true;

        const reader = new FileReader();

        reader.onload = () => {
            this.rawCsvContent = reader.result;
            this.isLoading = false;
        };
        reader.onerror = () => {
            this.isLoading = false;
            this.showToast('Error', `Could not read ${file.name}.`, 'error');
        };
        reader.readAsText(file);
    }

    // ------------------------------------------------------------------
    // Run
    // ------------------------------------------------------------------

    runBatchJob() {
        this.isLoading = true;
        this.jobStatus = undefined;

        startBatchFromCsv({
            rawCsvText: this.rawCsvContent,
            fileName: this.fileName,
            layoutCode: this.selectedLayout,
            operation: this.selectedOperation
        })
            .then((result) => {
                this.isLoading = false;
                this.uploadResult = result;
                if (result.jobId) {
                    this.showToast(
                        'Staged',
                        `${result.rowsInserted} row(s) staged from the input file. Processing...`,
                        'success'
                    );
                    this.startPolling(result.jobId, result.batchId);
                } else {
                    this.showToast(
                        'Nothing to process',
                        `${result.rowsInvalid} row(s) did not pass validation. No records were staged.`,
                        'warning'
                    );
                }
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', this.reduceError(error), 'error');
            });
    }

    // ------------------------------------------------------------------
    // Job polling
    // ------------------------------------------------------------------

    startPolling(jobId, batchId) {
        this.stopPolling();
        this.pollTimer = setInterval(() => {
            getJobStatus({ jobId, batchId })
                .then((status) => {
                    this.jobStatus = status;
                    if (status.isComplete) {
                        this.stopPolling();
                        this.showToast(
                            `Batch ${status.status}`,
                            `${status.stagingCompleted} row(s) completed, ${status.stagingErrored} errored.`,
                            status.stagingErrored > 0 ? 'warning' : 'success'
                        );
                    }
                })
                .catch((error) => {
                    this.stopPolling();
                    this.showToast('Error', this.reduceError(error), 'error');
                });
        }, POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = undefined;
        }
    }

    // ------------------------------------------------------------------
    // Derived state
    // ------------------------------------------------------------------

    get isRunDisabled() {
        return this.isLoading || !this.selectedOperation || !this.selectedLayout || !this.rawCsvContent;
    }

    get isLayoutDisabled() {
        return !this.selectedOperation;
    }

    get isFileDisabled() {
        return !this.selectedOperation || !this.selectedLayout;
    }

    get hasUploadResult() {
        return !!this.uploadResult;
    }

    get hasParseErrors() {
        return !!this.uploadResult?.errors?.length;
    }

    get parseErrors() {
        return (this.uploadResult?.errors || []).map((message, i) => ({ key: `err-${i}`, message }));
    }

    get hasJobStatus() {
        return !!this.jobStatus;
    }

    get jobHadErrors() {
        return !!this.jobStatus && this.jobStatus.stagingErrored > 0;
    }

    get jobThemeClass() {
        if (this.jobStatus && !this.jobStatus.isComplete) {
            return 'slds-box slds-box_x-small slds-m-top_medium slds-theme_info';
        }
        return this.jobHadErrors
            ? 'slds-box slds-box_x-small slds-m-top_medium slds-theme_warning'
            : 'slds-box slds-box_x-small slds-m-top_medium slds-theme_success';
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    resetResults() {
        this.stopPolling();
        this.uploadResult = undefined;
        this.jobStatus = undefined;
        this.rawCsvContent = '';
        this.fileName = '';
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error.';
    }

    showToast(title, message, variant) {
        const mode = variant === 'error' ? 'sticky' : 'dismissable';
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode }));
    }
}
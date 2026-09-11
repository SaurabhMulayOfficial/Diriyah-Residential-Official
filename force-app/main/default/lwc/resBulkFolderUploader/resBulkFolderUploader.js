import { LightningElement, api, track } from 'lwc';
import processUploadedFiles from '@salesforce/apex/RES_BulkFolderUploaderController.processUploadedFiles';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ResBulkFolderUploader extends LightningElement {
    @api recordId;
    @track uploadedFiles = [];

    isUploading = false;
    showSuccessMessage = false;
    successMessageText = 'Files uploaded and linked successfully.';
    successMessageTimer;

    acceptedFormats = [
        '.pdf',
        '.doc',
        '.docx',
        '.xls',
        '.xlsx',
        '.ppt',
        '.pptx',
        '.jpg',
        '.jpeg',
        '.png',
        '.zip'
    ];

    get acceptedFormatsString() {
        return this.acceptedFormats.join(',');
    }

    async handleUploadFinished(event) {
        const files = event.detail.files || [];
        if (!files.length) {
            return;
        }

        this.showSuccessMessage = false;

        if (this.successMessageTimer) {
            clearTimeout(this.successMessageTimer);
            this.successMessageTimer = null;
        }

        this.isUploading = true;

        try {
            this.uploadedFiles = files.map(file => ({
                name: file.name,
                documentId: file.documentId
            }));

            const result = await processUploadedFiles({
                uploadedFilesJson: JSON.stringify(this.uploadedFiles)
            });

            this.isUploading = false;

            if (result.failedCount > 0) {
                this.showToast(
                    'Warning',
                    `${result.successCount} file(s) linked successfully. ${result.failedCount} file(s) failed.`,
                    'warning'
                );
                return;
            }

            this.showSuccessMessage = true;

            this.successMessageTimer = setTimeout(() => {
                this.showSuccessMessage = false;
                this.successMessageTimer = null;
            }, 2000);
        } catch (error) {
            this.isUploading = false;
            this.showSuccessMessage = false;
            console.error('File processing error:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'An unexpected error occurred while processing the uploaded files.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    disconnectedCallback() {
        if (this.successMessageTimer) {
            clearTimeout(this.successMessageTimer);
            this.successMessageTimer = null;
        }
    }
}
import { LightningElement, track } from 'lwc';
import saveFileChunk from '@salesforce/apex/RES_BulkFolderUploaderController.saveFileChunk';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// 1.5 MB binary chunk size (~2 MB base64 payload per Apex call)
const CHUNK_SIZE = 1500 * 1024; 

export default class ResBulkFolderUploader extends LightningElement {
    @track fileDataList = [];
    selectedFilesCount = 0;
    folderLabelText = 'No folder chosen';
    isLoading = false;

    get hasFiles() {
        return this.selectedFilesCount > 0;
    }

    triggerFolderSelect() {
        const fileInput = this.template.querySelector('[data-id="folderInput"]');
        if (fileInput) {
            fileInput.click();
        }
    }

    handleFileSelection(event) {
        const files = Array.from(event.target.files || []);
        this.fileDataList = [];

        if (files.length === 0) {
            this.selectedFilesCount = 0;
            this.folderLabelText = 'No folder chosen';
            return;
        }

        const samplePath = files[0].webkitRelativePath;
        if (samplePath && samplePath.includes('/')) {
            this.folderLabelText = samplePath.split('/')[0];
        } else {
            this.folderLabelText = `${files.length} file(s) selected`;
        }

        // Filter out hidden OS system files
        this.fileDataList = files.filter(file => !file.name.startsWith('.'));
        this.selectedFilesCount = this.fileDataList.length;
    }

    async processAndUpload() {
        if (this.fileDataList.length === 0) return;
        this.isLoading = true;

        let successCount = 0;
        let failCount = 0;

        for (const file of this.fileDataList) {
            try {
                await this.uploadSingleFile(file);
                successCount++;
            } catch (error) {
                console.error(`Error uploading ${file.name}:`, error);
                failCount++;
            }
        }

        this.isLoading = false;

        if (successCount > 0) {
            const msg = failCount > 0 
                ? `${successCount} file(s) uploaded successfully, ${failCount} failed.`
                : `${successCount} file(s) successfully attached across matched Product records.`;
            this.showToast(failCount > 0 ? 'Warning' : 'Success', msg, failCount > 0 ? 'warning' : 'success');
        } else {
            this.showToast('Error', 'Failed to upload files or match Product Codes.', 'error');
        }

        this.resetForm();
    }

    uploadSingleFile(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();

            reader.onload = async () => {
                const arrayBuffer = reader.result;
                const totalBytes = arrayBuffer.byteLength;
                let startPosition = 0;
                let documentId = null;

                try {
                    while (startPosition < totalBytes) {
                        const endPosition = Math.min(startPosition + CHUNK_SIZE, totalBytes);
                        const slice = arrayBuffer.slice(startPosition, endPosition);
                        const base64Chunk = this.arrayBufferToBase64(slice);

                        // Call Apex controller with chunk + optional documentId
                        documentId = await saveFileChunk({
                            fileName: file.name,
                            base64Data: base64Chunk,
                            documentId: documentId
                        });

                        startPosition = endPosition;
                    }
                    resolve(documentId);
                } catch (err) {
                    reject(err);
                }
            };

            reader.onerror = (err) => reject(err);
            reader.readAsArrayBuffer(file);
        });
    }

    arrayBufferToBase64(buffer) {
        let binary = '';
        const bytes = new Uint8Array(buffer);
        const len = bytes.byteLength;
        for (let i = 0; i < len; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        return window.btoa(binary);
    }

    resetForm() {
        this.fileDataList = [];
        this.selectedFilesCount = 0;
        this.folderLabelText = 'No folder chosen';

        const fileInput = this.template.querySelector('[data-id="folderInput"]');
        if (fileInput) {
            fileInput.value = '';
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
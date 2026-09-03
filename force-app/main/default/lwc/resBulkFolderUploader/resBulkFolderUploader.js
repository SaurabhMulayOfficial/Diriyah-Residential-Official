import { LightningElement, track } from 'lwc';
import uploadAndAttachFilesToProduct from '@salesforce/apex/RES_BulkFolderUploaderController.uploadAndAttachFilesToProduct';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

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
        const files = event.target.files;
        this.fileDataList = [];

        if (!files || files.length === 0) {
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

        let loadedCount = 0;
        const totalFiles = files.length;

        for (let i = 0; i < totalFiles; i++) {
            const file = files[i];
            
            if (file.name.startsWith('.')) {
                loadedCount++;
                continue;
            }

            const reader = new FileReader();
            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                this.fileDataList.push({
                    fileName: file.name,
                    base64Data: base64
                });

                loadedCount++;
                if (loadedCount === totalFiles) {
                    this.selectedFilesCount = this.fileDataList.length;
                }
            };
            reader.readAsDataURL(file);
        }
    }

    processAndUpload() {
        // Removed recordId validation so global Home Page uploads proceed
        if (this.fileDataList.length === 0) return;
        this.isLoading = true;

        uploadAndAttachFilesToProduct({ 
            filePayloads: this.fileDataList 
        })
            .then(result => {
                this.isLoading = false;
                this.showToast('Success', result, 'success');
                this.fileDataList = [];
                this.selectedFilesCount = 0;
                this.folderLabelText = 'No folder chosen';
                
                const fileInput = this.template.querySelector('[data-id="folderInput"]');
                if (fileInput) {
                    fileInput.value = '';
                }
            })
            .catch(error => {
                this.isLoading = false;
                const errorMsg = error.body ? error.body.message : error.message;
                this.showToast('Error', errorMsg, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
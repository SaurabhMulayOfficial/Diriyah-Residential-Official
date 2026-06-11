import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import CONTENT_VERSION_OBJECT from '@salesforce/schema/ContentVersion';
import ATTACHMENT_TYPE_FIELD from '@salesforce/schema/ContentVersion.RES_Attachment_Type__c';
import { gql, graphql } from 'lightning/uiGraphQLApi';
import uploadFile from '@salesforce/apex/RES_UploadDocumentClass.uploadFiles';
import getFiles from '@salesforce/apex/RES_UploadDocumentClass.getFiles';
import updateDocumentLabel from '@salesforce/apex/RES_UploadDocumentClass.updateDocumentLabel';
import deleteFile from '@salesforce/apex/RES_UploadDocumentClass.deleteFile';
import canEditDocumentLabel from '@salesforce/apex/RES_UploadDocumentClass.canEditDocumentLabel';
import USER_ID from '@salesforce/user/Id';

export default class ResUploadDocuments extends NavigationMixin(LightningElement) {
    @api recordId;
    userId = USER_ID;

    @track attachmentTypeOptions = [];
    @track allAttachmentTypes = [];
    @track files = [];
    @track filteredFiles = [];

    showSpinner = false;
    cvRecordTypeId;
    isOpen = true;
    showModal = false;
    showDeleteModal = false;
    selectedDeleteContentDocumentId;
    totalFiles = 0;

    searchFileName = '';
    searchDocumentLabel = '';
    searchAttachmentType = '';
    searchCreatedBy = '';

    selectedFiles = [];
    selectedFileNames = '';
    selectedDocumentLabel = '';
    selectedAttachmentType = '';

    editedLabels = {};
    disableDocumentLabel = true;
    isPersonAccount = false;

    resizeColumn;
    startX;
    startWidth;

    connectedCallback() {
        if (this.recordId) {
            this.loadFiles();
        }

        if (this.userId) {
            this.checkForEditDocumentLabel();
        }
    }

    disconnectedCallback() {
        document.removeEventListener('mousemove', this.handleColumnResize);
        document.removeEventListener('mouseup', this.stopColumnResize);
    }

    get graphQLVariables() {
        return {
            recordId: this.recordId
        };
    }

    @wire(getObjectInfo, { objectApiName: CONTENT_VERSION_OBJECT })
    objectInfo({ data, error }) {
        if (data) {
            this.cvRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.error(error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$cvRecordTypeId',
        fieldApiName: ATTACHMENT_TYPE_FIELD
    })
    picklistValues({ data, error }) {
        if (data) {
            this.allAttachmentTypes = data.values;
            this.filterAttachmentTypes();
        } else if (error) {
            console.error(error);
        }
    }

    @wire(graphql, {
        query: gql`
            query getAccount($recordId: ID!) {
                uiapi {
                    query {
                        Account(where: { Id: { eq: $recordId } } first: 1) {
                            edges {
                                node {
                                    Id
                                    IsPersonAccount {
                                        value
                                    }
                                }
                            }
                        }
                    }
                }
            }
        `,
        variables: '$graphQLVariables'
    })
    accountResult({ data, errors }) {
        if (data) {
            const account = data.uiapi.query.Account.edges?.[0]?.node;
            this.isPersonAccount = account?.IsPersonAccount?.value || false;
            this.filterAttachmentTypes();
        } else if (errors) {
            console.error(errors);
        }
    }

    get sectionIcon() {
        return this.isOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get showNoData() {
        return !this.filteredFiles || this.filteredFiles.length === 0;
    }

    toggleSection() {
        this.isOpen = !this.isOpen;
    }

    handleSpinner() {
        this.showSpinner = !this.showSpinner;
    }

    filterAttachmentTypes() {
        if (!this.allAttachmentTypes?.length) {
            return;
        }

        const allowed = this.isPersonAccount
            ? [
                  'National Id',
                  'Iqama Id',
                  'GCC Id',
                  'Passport',
                  'Simah Form',
                  'POA (Power of Attorney)'
              ]
            : [
                  'Company Registration Certificate',
                  'Simah Form',
                  'POA (Power of Attorney)'
              ];

        this.attachmentTypeOptions = this.allAttachmentTypes.filter((option) =>
            allowed.includes(option.value)
        );
    }

    loadFiles() {
        getFiles({ recordId: this.recordId })
            .then((result) => {
                this.files = result || [];
                this.totalFiles = this.files.length;
                this.applyFilters();
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error', 'dismissable');
            });
    }

    checkForEditDocumentLabel() {
        canEditDocumentLabel()
            .then((result) => {
                this.disableDocumentLabel = !result;
            })
            .catch((error) => {
                console.error('Error checking document label access', error);
                this.disableDocumentLabel = true;
            });
    }

    openModal() {
        this.showModal = true;
        this.selectedFiles = [];
        this.selectedFileNames = '';
        this.selectedDocumentLabel = '';
        this.selectedAttachmentType = '';
    }

    closeModal() {
        this.showModal = false;
        this.selectedFiles = [];
        this.selectedFileNames = '';
        this.selectedDocumentLabel = '';
        this.selectedAttachmentType = '';
    }

    handleFileNameSearch(event) {
        this.searchFileName = event.target.value;
        this.applyFilters();
    }

    handleDocumentLabelSearch(event) {
        this.searchDocumentLabel = event.target.value;
        this.applyFilters();
    }

    handleAttachmentTypeSearch(event) {
        this.searchAttachmentType = event.target.value;
        this.applyFilters();
    }

    handleCreatedBySearch(event) {
        this.searchCreatedBy = event.target.value;
        this.applyFilters();
    }

    handleAttachmentTypeChange(event) {
        this.selectedAttachmentType = event.detail.value;
    }

    handleSelectedDocumentLabelChange(event) {
        this.selectedDocumentLabel = event.target.value;
    }

    handleFileSelection(event) {
        const uploadedFiles = event.detail.files || [];
        this.selectedFiles = uploadedFiles;

        this.selectedFileNames = uploadedFiles
            .map((file) => file.name)
            .join(', ');

        if (uploadedFiles.length === 1) {
            this.selectedDocumentLabel = this.removeExtension(uploadedFiles[0].name);
        } else {
            this.selectedDocumentLabel = '';
        }
    }

    applyFilters() {
        const fileName = this.searchFileName?.toLowerCase() || '';
        const docLabel = this.searchDocumentLabel?.toLowerCase() || '';
        const attachType = this.searchAttachmentType?.toLowerCase() || '';
        const createdBy = this.searchCreatedBy?.toLowerCase() || '';

        this.filteredFiles = this.files.filter((file) => {
            const fileNameValue = file.fileName?.toLowerCase() || '';
            const documentLabelValue = file.documentLabel?.toLowerCase() || '';
            const attachmentTypeValue = file.attachmentType?.toLowerCase() || '';
            const createdByValue = file.createdByName?.toLowerCase() || '';

            return (
                fileNameValue.includes(fileName) &&
                documentLabelValue.includes(docLabel) &&
                attachmentTypeValue.includes(attachType) &&
                createdByValue.includes(createdBy)
            );
        });
    }

    uploadSelectedFiles() {
        if (!this.selectedFiles || this.selectedFiles.length === 0) {
            this.showToast(
                'Validation Error',
                'Please select at least one file.',
                'error',
                'dismissable'
            );
            return;
        }

        if (!this.selectedAttachmentType) {
            this.showToast(
                'Validation Error',
                'Attachment Type is required.',
                'error',
                'dismissable'
            );
            return;
        }

        this.handleSpinner();

        const files = this.selectedFiles.map((file) => ({
            documentId: file.documentId,
            fileName: file.name,
            documentLabel: this.selectedDocumentLabel,
            attachmentType: this.selectedAttachmentType
        }));

        uploadFile({
            recordId: this.recordId,
            files
        })
            .then(() => {
                this.showToast('Success', 'File uploaded successfully.', 'success', 'dismissable');
                this.closeModal();

                window.setTimeout(() => {
                    this.loadFiles();
                }, 700);
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error', 'dismissable');
            })
            .finally(() => {
                this.handleSpinner();
            });
    }

    handleDocumentLabelChange(event) {
        const contentVersionId = event.target.dataset.id;
        this.editedLabels[contentVersionId] = event.target.value;
    }

    saveDocumentLabel(event) {
        const contentVersionId = event.target.dataset.id;
        const documentLabel = this.editedLabels[contentVersionId];

        if (documentLabel === undefined) {
            return;
        }

        updateDocumentLabel({
            contentVersionId,
            documentLabel
        })
            .then(() => {
                this.files = this.files.map((file) => {
                    if (file.contentVersionId === contentVersionId) {
                        return {
                            ...file,
                            documentLabel
                        };
                    }

                    return file;
                });

                this.applyFilters();
                delete this.editedLabels[contentVersionId];
                this.showToast('Success', 'Document Label updated.', 'success', 'dismissable');
            })
            .catch(() => {
                this.showToast(
                    'Error',
                    'Insufficient permissions to edit Document Label.',
                    'error',
                    'dismissable'
                );
            });
    }

    previewFile(event) {
        const contentDocumentId = event.currentTarget.dataset.id;

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: contentDocumentId
            }
        });
    }

    downloadFile(event) {
        const contentDocumentId = event.currentTarget.dataset.id;

        const link = document.createElement('a');
        link.href = `/sfc/servlet.shepherd/document/download/${contentDocumentId}`;
        link.download = '';
        link.style.display = 'none';

        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    deleteSelectedFile(event) {
        this.selectedDeleteContentDocumentId = event.currentTarget.dataset.id;
        this.showDeleteModal = true;
    }

    closeDeleteModal() {
        this.showDeleteModal = false;
        this.selectedDeleteContentDocumentId = null;
    }

    confirmDeleteFile() {
        if (!this.selectedDeleteContentDocumentId) {
            return;
        }

        deleteFile({ contentDocumentId: this.selectedDeleteContentDocumentId })
            .then(() => {
                this.showToast('Success', 'File deleted successfully.', 'success', 'dismissable');
                this.closeDeleteModal();
                this.loadFiles();
            })
            .catch(() => {
                this.showToast(
                    'Error',
                    'Insufficient permissions to delete file.',
                    'error',
                    'dismissable'
                );
            });
    }

    startColumnResize(event) {
        event.preventDefault();
        event.stopPropagation();

        this.resizeColumn = event.target.parentElement;
        this.startX = event.clientX;
        this.startWidth = this.resizeColumn.offsetWidth;

        document.addEventListener('mousemove', this.handleColumnResize);
        document.addEventListener('mouseup', this.stopColumnResize);
    }

    handleColumnResize = (event) => {
        if (!this.resizeColumn) {
            return;
        }

        const newWidth = this.startWidth + event.clientX - this.startX;

        if (newWidth > 90) {
            this.resizeColumn.style.width = `${newWidth}px`;
            this.resizeColumn.style.minWidth = `${newWidth}px`;
            this.resizeColumn.style.maxWidth = `${newWidth}px`;
        }
    };

    stopColumnResize = () => {
        this.resizeColumn = null;

        document.removeEventListener('mousemove', this.handleColumnResize);
        document.removeEventListener('mouseup', this.stopColumnResize);
    };

    removeExtension(fileName) {
        if (!fileName || !fileName.includes('.')) {
            return fileName;
        }

        return fileName.substring(0, fileName.lastIndexOf('.'));
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.body?.pageErrors?.length) {
            return error.body.pageErrors[0].message;
        }

        if (error?.body?.fieldErrors) {
            const fieldErrors = Object.values(error.body.fieldErrors).flat();

            if (fieldErrors.length) {
                return fieldErrors[0].message;
            }
        }

        if (error?.message) {
            return error.message;
        }

        return 'Something went wrong.';
    }

    showToast(title, message, variant, mode = 'dismissable') {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode
            })
        );
    }
}
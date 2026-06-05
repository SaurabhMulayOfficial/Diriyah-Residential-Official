import { LightningElement, api, track, wire } from 'lwc';
import {ShowToastEvent} from 'lightning/platformShowToastEvent';
import {NavigationMixin} from 'lightning/navigation'
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
    @track attachmentTypeOptions = [];
    showSpinner = false;
    cvRecordTypeId;
    isOpen = true;
    showModal = false;
    totalFiles;
    searchFileName = '';
    searchDocumentLabel = '';
    searchAttachmentType = '';
    searchCreatedBy = '';
    selectedFiles = [];
    selectedFileNames = '';
    selectedDocumentLabel = '';
    selectedAttachmentType = '';
    editedLabels = {};
    disableDocumentLabel= true;

    connectedCallback() {
        if(this.recordId) {
             this.loadFiles();
        }
         if(this.userId) {
             this.checkForEditDocumentLabel();
        }
    }

    //Getter for Account Graphql Query
    get graphQLVariables() {
    return {
        recordId: this.recordId
    };
}
   //To get ContentVersion object info
    @wire(getObjectInfo, { objectApiName: CONTENT_VERSION_OBJECT })
     objectInfo({ data, error }) {
    if (data) {
        this.cvRecordTypeId = data.defaultRecordTypeId;
    }
}
 //To get Attachment Type Options
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
 
    //Handle loader 
    handleSpinner(){
        this.showSpinner = !this.showSpinner;
    }
 
     //Show Toast notification
    showToast(title, message, variant, mode){
        const evt = new ShowToastEvent({
            title: title,
            message:message,
            variant: variant,
            mode: mode
        });
        this.dispatchEvent(evt);
    } 
    
    
    //Graphql query for Account
    @wire(graphql, {
    query: gql`
        query getAccount($recordId: ID!) {
            uiapi {
                query {
                    Account(
                        where: { Id: { eq: $recordId } }
                        first: 1
                    ) {
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

//wire method Call automatically to get Account Details
accountResult({ data, errors }) {
    if (data) {
        const account =
            data.uiapi.query.Account.edges?.[0]?.node;

        this.isPersonAccount =
            account?.IsPersonAccount?.value || false;

        this.filterAttachmentTypes();
    }
}

//handle file type based on Account RecordType
filterAttachmentTypes() {

    if (!this.allAttachmentTypes?.length) {
        return;
    }

    if (this.isPersonAccount) {

        const allowed = [
            'National Id',
            'Iqama Id',
            'GCC Id',
            'Passport',
            'Simah Form',
            'POA (Power of Attorney)'
        ];

        this.attachmentTypeOptions =
            this.allAttachmentTypes.filter(
                option => allowed.includes(option.value)
            );

    } else {

      const allowed = [
            'Company Registration Certificate',
            'Simah Form',
            'POA (Power of Attorney)'
        ];

        this.attachmentTypeOptions =
            this.allAttachmentTypes.filter(
                option => allowed.includes(option.value)
            );

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

    loadFiles() {
        getFiles({ recordId: this.recordId })
            .then((result) => {
                this.files = result || [];
                this.totalFiles = result.length;
                this.applyFilters();
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
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

    const uploadedFiles = event.detail.files;
    this.selectedFiles = uploadedFiles;
    console.log(JSON.stringify(this.selectedFiles));
    this.selectedFileNames = uploadedFiles
        .map(file => file.name)
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

     
const files = this.selectedFiles.map(file => ({
    documentId: file.documentId,
    fileName: file.name,
    documentLabel: this.selectedDocumentLabel,
    attachmentType: this.selectedAttachmentType
}));
console.log(' in upload files === '+ JSON.stringify(files));

   uploadFile({
    recordId: this.recordId,
    files: files
}).then(() => {
                this.showToast('Success', 'File uploaded successfully.', 'success');
                this.closeModal();

                window.setTimeout(() => {
                    this.loadFiles();
                }, 700);
            })
            
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
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
                this.showToast('Success', 'Document Label updated.', 'success');
            })
            .catch((error) => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
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
        window.open(`/sfc/servlet.shepherd/document/download/${contentDocumentId}`, '_blank');
    }

    deleteSelectedFile(event) {
        const contentDocumentId = event.currentTarget.dataset.id;

        deleteFile({ contentDocumentId })
            .then(() => {
                this.showToast('Success', 'File deleted successfully.', 'success');
                this.loadFiles();
            })
            .catch((error) => {
                this.showToast('Error', 'Insufficient permissions to delete file.', 'error');
            });
    }

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
}
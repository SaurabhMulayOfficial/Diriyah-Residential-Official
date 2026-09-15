import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { updateRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import notifyProductUpdate from '@salesforce/apex/RES_ProductUpdateNotificationController.notifyProductUpdate';

// Product2 fields
import ID_FIELD from '@salesforce/schema/Product2.Id';
import UNIT_STATUS_FIELD from '@salesforce/schema/Product2.RES_Unit_Status__c';
import IS_ACTIVE_FIELD from '@salesforce/schema/Product2.IsActive';
import NAME_FIELD from '@salesforce/schema/Product2.Name';
import PRODUCT_CODE_FIELD from '@salesforce/schema/Product2.ProductCode';
import BUSINESS_ENTITY_FIELD from '@salesforce/schema/Product2.RES_Business_Entity__c';
import TYPE_FIELD from '@salesforce/schema/Product2.RES_Type__c';
import AREA_FIELD from '@salesforce/schema/Product2.RES_Net_Saleable_Area__c';
import FAMILY_FIELD from '@salesforce/schema/Product2.Family';
import HANDOVER_DATE_FIELD from '@salesforce/schema/Product2.RES_Unit_Handover_Date__c';
import IBAN_FIELD from '@salesforce/schema/Product2.RES_Unit_Virtual_IBAN__c';
import DESCRIPTION_FIELD from '@salesforce/schema/Product2.Description';
import UPDATE_COMMENTS_FIELD from '@salesforce/schema/Product2.RES_Update_Comments__c';
import UPDATE_REQUESTED_FIELD from '@salesforce/schema/Product2.RES_Update_Requested__c';

const FIELDS = [
    UNIT_STATUS_FIELD,
    NAME_FIELD,
    PRODUCT_CODE_FIELD,
    BUSINESS_ENTITY_FIELD,
    TYPE_FIELD,
    AREA_FIELD,
    FAMILY_FIELD,
    HANDOVER_DATE_FIELD,
    IBAN_FIELD,
    DESCRIPTION_FIELD
];

const STATUS_AVAILABLE = 'Available'; // Changed from 'Active' to match picklist
const STATUS_SOFT_HOLD = 'Soft Hold';
const STATUS_HARD_BLOCK = 'Hard Block'; // Changed from 'Hard Hold' to match picklist
const STATUS_DRAFT = 'Draft';

export default class ResProductUpdateModal extends LightningElement {
    @api recordId;

    showModal = false;
    showWarningModal = false;
    isProcessing = false;
    warningMessage = '';
    warningTitle = '';
    updateComments = '';

    wiredProductResult;
    currentStatus;
    productName;

    // Fields to display in the form
    nameField = NAME_FIELD;
    productCodeField = PRODUCT_CODE_FIELD;
    businessEntityField = BUSINESS_ENTITY_FIELD;
    typeField = TYPE_FIELD;
    areaField = AREA_FIELD;
    familyField = FAMILY_FIELD;
    handoverDateField = HANDOVER_DATE_FIELD;
    ibanField = IBAN_FIELD;
    descriptionField = DESCRIPTION_FIELD;
    updateCommentsField = UPDATE_COMMENTS_FIELD;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredProduct(result) {
        this.wiredProductResult = result;
        if (result.data) {
            this.currentStatus = getFieldValue(result.data, UNIT_STATUS_FIELD);
            this.productName = getFieldValue(result.data, NAME_FIELD);
        }
    }

    // Auto-open modal when component loads (for Quick Actions)
    connectedCallback() {
        this.showModal = true;
    }

    @api
    openModal() {
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
        this.updateComments = '';
        // Close the Quick Action modal properly
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleUpdateCommentsChange(event) {
        this.updateComments = event.target.value;
    }

    handleSave(event) {
        event.preventDefault(); // Prevent default form submission

        // Validate update comments
        if (!this.updateComments || this.updateComments.trim().length === 0) {
            this.showToast('Required', 'Please provide update comments to explain the reason for this amendment.', 'error');
            return;
        }

        if (this.updateComments.trim().length < 10) {
            this.showToast('Invalid', 'Update comments must be at least 10 characters.', 'error');
            return;
        }

        // Show appropriate warning based on current status
        if (this.currentStatus === STATUS_AVAILABLE) {
            this.warningTitle = 'Confirm Update';
            this.warningMessage = 'Units being updated are already available for sale. Any changes made will put the unit in draft and development approval will be required to make it available again. Do you want to proceed?';
            this.showWarningModal = true;
        } else if (this.currentStatus === STATUS_SOFT_HOLD || this.currentStatus === STATUS_HARD_BLOCK) {
            this.warningTitle = 'Confirm Update';
            this.warningMessage = 'Units being updated are already reserved. This will affect the quote/contract in progress on these units. Do you want to proceed?';
            this.showWarningModal = true;
        } else {
            // For Draft or other statuses, submit form directly
            const form = this.template.querySelector('lightning-record-edit-form');
            if (form) {
                form.submit();
            }
        }
    }

    handleWarningConfirm() {
        this.showWarningModal = false;

        // Get form data and perform update
        const form = this.template.querySelector('lightning-record-edit-form');
        if (form) {
            // Submit the form
            form.submit();
        }
    }

    handleWarningCancel() {
        this.showWarningModal = false;
    }

    async handleSuccess(event) {
        this.isProcessing = true;

        try {
            // Validate recordId exists
            if (!this.recordId) {
                throw new Error('Record ID is missing. Cannot update the unit.');
            }

            // Validate update comments exist and meet minimum length
            if (!this.updateComments || this.updateComments.trim().length < 10) {
                throw new Error('Update comments must be at least 10 characters.');
            }

            // After successful form save, update additional fields
            const fields = {};
            fields[ID_FIELD.fieldApiName] = this.recordId;
            fields[UPDATE_COMMENTS_FIELD.fieldApiName] = this.updateComments.trim();
            fields[UPDATE_REQUESTED_FIELD.fieldApiName] = true;

            console.log('Fields before condition check:', JSON.stringify(fields));

            // Set status to Draft and IsActive to false when updating Active or Hold units
            const shouldUpdateStatus = (this.currentStatus === STATUS_AVAILABLE || this.currentStatus === STATUS_SOFT_HOLD || this.currentStatus === STATUS_HARD_BLOCK);
            if (shouldUpdateStatus) {
                fields[UNIT_STATUS_FIELD.fieldApiName] = STATUS_DRAFT;
                fields[IS_ACTIVE_FIELD.fieldApiName] = false;
            } else {
                console.log('CONDITION FALSE - NOT updating status/IsActive');
            }
            const recordInput = { fields };
            const updateResult = await updateRecord(recordInput);

            // Refresh the wired product data
            if (this.wiredProductResult) {
                await refreshApex(this.wiredProductResult);
            }

            // Send notification to Operations team
            try {
                await notifyProductUpdate({ productId: this.recordId });
                console.log('Update notification sent successfully');
            } catch (notifyError) {
                // Don't fail the whole operation if notification fails
                console.error('Error sending notification:', notifyError);
            }

            this.showToast(
                'Success',
                `Unit "${this.productName || 'Unit'}" has been updated successfully and moved to Draft status. Submit for approval to make it available again.`,
                'success'
            );

            // Close modal and dispatch event to refresh parent
            this.closeModal();
            this.dispatchEvent(new CustomEvent('updatecomplete'));
            // Refresh the page to show updated values
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            console.error('=== ERROR in handleSuccess ===');
            console.error('Error updating product:', error);

            // Handle different error types
            let errorMessage = 'An error occurred while updating the unit.';
            if (error.body?.message) {
                errorMessage = error.body.message;
            } else if (error.body?.fieldErrors) {
                const fieldErrors = Object.values(error.body.fieldErrors).flat();
                if (fieldErrors.length > 0) {
                    errorMessage = fieldErrors.map(e => e.message).join(', ');
                }
            } else if (error.body?.output?.errors) {
                errorMessage = error.body.output.errors.map(e => e.message).join(', ');
            } else if (error.message) {
                errorMessage = error.message;
            }

            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    handleError(event) {
        const error = event.detail;
        let message = 'An error occurred while updating the unit.';

        if (error?.output?.errors?.length > 0) {
            message = error.output.errors.map(e => e.message).join(', ');
        } else if (error?.detail) {
            message = error.detail;
        }

        this.showToast('Error', message, 'error');
        this.isProcessing = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    get modalTitle() {
        return `Update Unit: ${this.productName || ''}`;
    }

    get isActive() {
        return this.currentStatus === STATUS_AVAILABLE;
    }

    get isOnHold() {
        return this.currentStatus === STATUS_SOFT_HOLD || this.currentStatus === STATUS_HARD_BLOCK;
    }

    get statusMessage() {
        if (this.isActive) {
            return 'This unit is currently Active and available for sale.';
        } else if (this.isOnHold) {
            return 'This unit is currently on Hold and may be reserved by a quote/contract.';
        }
        return '';
    }
}

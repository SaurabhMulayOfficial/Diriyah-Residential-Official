import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { refreshApex } from '@salesforce/apex';
import updateAllAndNotify from '@salesforce/apex/RES_ProductUpdateNotificationController.updateAllAndNotify';

// Product2 fields - Core
import UNIT_STATUS_FIELD from '@salesforce/schema/Product2.RES_Unit_Status__c';
import NAME_FIELD from '@salesforce/schema/Product2.Name';
import PRODUCT_CODE_FIELD from '@salesforce/schema/Product2.ProductCode';
import BUSINESS_ENTITY_FIELD from '@salesforce/schema/Product2.RES_Business_Entity__c';
import TYPE_FIELD from '@salesforce/schema/Product2.RES_Type__c';
import FAMILY_FIELD from '@salesforce/schema/Product2.Family';
import DESCRIPTION_FIELD from '@salesforce/schema/Product2.Description';
import UPDATE_COMMENTS_FIELD from '@salesforce/schema/Product2.RES_Update_Comments__c';

// Product2 fields - Details Tab (from screenshots)
import CONSTRUCTION_PHASE_FIELD from '@salesforce/schema/Product2.RES_Construction_Phase__c';
import USAGE_TYPE_ARABIC_FIELD from '@salesforce/schema/Product2.RES_Usage_Type_Arabic__c';
import CIP_TYPE_FIELD from '@salesforce/schema/Product2.RES_CIP_Type__c';

// Product2 fields - Fixtures/Fittings Tab (from screenshots)
import ORIENTATION_FIELD from '@salesforce/schema/Product2.RES_Orientation__c';
import STOREROOM_FIELD from '@salesforce/schema/Product2.RES_Storeroom__c';
import ELEVATED_FIELD from '@salesforce/schema/Product2.RES_Elevated__c';
import TERRACE_FIELD from '@salesforce/schema/Product2.RES_Terrace__c';
import ROOF_TERRACE_FIELD from '@salesforce/schema/Product2.RES_Roof_Terrace__c';
import MAIDS_ROOM_FIELD from '@salesforce/schema/Product2.RES_Maids_Room__c';
import WADI_VIEW_FIELD from '@salesforce/schema/Product2.RES_Wadi_View__c';
import GOLF_VIEW_FIELD from '@salesforce/schema/Product2.RES_Golf_View__c';
import FURNISHED_FIELD from '@salesforce/schema/Product2.RES_Furnished__c';
import ENTRY_COURTYARD_FIELD from '@salesforce/schema/Product2.RES_Entry_Courtyard__c';
import GARAGE_FIELD from '@salesforce/schema/Product2.RES_Garage__c';
import POOL_FIELD from '@salesforce/schema/Product2.RES_Pool__c';
import ID_FINISH_FIELD from '@salesforce/schema/Product2.RES_ID_Finish__c';
import DRIVERS_ROOM_FIELD from '@salesforce/schema/Product2.RES_Drivers_Room__c';
import PANORAMIC_VIEW_FIELD from '@salesforce/schema/Product2.RES_Panoramic_View__c';
import PRIVATE_FIELD from '@salesforce/schema/Product2.RES_Private__c';
import CONDITION_FIELD from '@salesforce/schema/Product2.RES_Condition__c';

const FIELDS = [
    UNIT_STATUS_FIELD,
    NAME_FIELD,
    PRODUCT_CODE_FIELD,
    BUSINESS_ENTITY_FIELD,
    TYPE_FIELD,
    FAMILY_FIELD,
    DESCRIPTION_FIELD
];

const STATUS_AVAILABLE = 'Available';
const STATUS_SOFT_HOLD = 'Soft Hold';
const STATUS_HARD_BLOCK = 'Hard Block';
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

    // Fields to display in the form - Details Tab
    nameField = NAME_FIELD;
    productCodeField = PRODUCT_CODE_FIELD;
    typeField = TYPE_FIELD;
    constructionPhaseField = CONSTRUCTION_PHASE_FIELD;
    businessEntityField = BUSINESS_ENTITY_FIELD;
    familyField = FAMILY_FIELD;
    usageTypeArabicField = USAGE_TYPE_ARABIC_FIELD;
    descriptionField = DESCRIPTION_FIELD;
    cipTypeField = CIP_TYPE_FIELD;
    updateCommentsField = UPDATE_COMMENTS_FIELD;

    // Fixtures/Fittings Tab Fields (from screenshots)
    orientationField = ORIENTATION_FIELD;
    storeroomField = STOREROOM_FIELD;
    elevatedField = ELEVATED_FIELD;
    terraceField = TERRACE_FIELD;
    roofTerraceField = ROOF_TERRACE_FIELD;
    maidsRoomField = MAIDS_ROOM_FIELD;
    wadiViewField = WADI_VIEW_FIELD;
    golfViewField = GOLF_VIEW_FIELD;
    furnishedField = FURNISHED_FIELD;
    entryCourtyardField = ENTRY_COURTYARD_FIELD;
    garageField = GARAGE_FIELD;
    poolField = POOL_FIELD;
    idFinishField = ID_FINISH_FIELD;
    driversRoomField = DRIVERS_ROOM_FIELD;
    panoramicViewField = PANORAMIC_VIEW_FIELD;
    privateField = PRIVATE_FIELD;
    conditionField = CONDITION_FIELD;

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
        event.preventDefault();

        if (!this.updateComments || this.updateComments.trim().length === 0) {
            this.showToast('Required', 'Please provide update comments to explain the reason for this amendment.', 'error');
            return;
        }

        if (this.updateComments.trim().length < 10) {
            this.showToast('Invalid', 'Update comments must be at least 10 characters.', 'error');
            return;
        }

        if (this.currentStatus === STATUS_AVAILABLE) {
            this.warningTitle = 'Confirm Update';
            this.warningMessage = 'Units being updated are already available for sale. Any changes made will put the unit in draft and development approval will be required to make it available again. Do you want to proceed?';
            this.showWarningModal = true;
        } else if (this.currentStatus === STATUS_SOFT_HOLD || this.currentStatus === STATUS_HARD_BLOCK) {
            this.warningTitle = 'Confirm Update';
            this.warningMessage = 'Units being updated are already reserved. This will affect the quote/contract in progress on these units. Do you want to proceed?';
            this.showWarningModal = true;
        } else {
            this.performSave();
        }
    }

    handleWarningConfirm() {
        this.showWarningModal = false;
        this.performSave();
    }

    handleWarningCancel() {
        this.showWarningModal = false;
    }

    // Collect current values from all lightning-input-field elements without calling form.submit().
    // form.submit() triggers the UI API save which enforces sharing and fails for read-only users.
    // Instead, we read values directly from DOM and pass them to Apex (without sharing).
    collectFieldValues() {
        const fields = {};
        this.template.querySelectorAll('lightning-input-field').forEach(field => {
            const fieldName = field.dataset.field;
            if (fieldName && field.value !== undefined && field.value !== null) {
                fields[fieldName] = field.value;
            }
        });
        return fields;
    }

    async performSave() {
        this.isProcessing = true;
        try {
            if (!this.recordId) {
                throw new Error('Record ID is missing. Cannot update the unit.');
            }

            const formFields = this.collectFieldValues();
            const shouldMoveToDraft = (
                this.currentStatus === STATUS_AVAILABLE ||
                this.currentStatus === STATUS_SOFT_HOLD ||
                this.currentStatus === STATUS_HARD_BLOCK
            );

            await updateAllAndNotify({
                productId: this.recordId,
                fieldsJson: JSON.stringify(formFields),
                updateComments: this.updateComments.trim(),
                shouldMoveToDraft: shouldMoveToDraft
            });

            if (this.wiredProductResult) {
                await refreshApex(this.wiredProductResult);
            }

            this.showToast(
                'Success',
                `Unit "${this.productName || 'Unit'}" has been updated successfully. Submit for approval to make it available again.`,
                'success'
            );

            this.closeModal();
            this.dispatchEvent(new CustomEvent('updatecomplete'));
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            console.error('Error updating product:', error);

            let errorMessage = 'An error occurred while updating the unit.';
            if (error.body?.message) {
                errorMessage = error.body.message;
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
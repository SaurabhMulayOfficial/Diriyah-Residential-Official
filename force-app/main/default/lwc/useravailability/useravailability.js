import { LightningElement, track } from 'lwc';
import updateUserStatus from '@salesforce/apex/RES_UserAvailabilityController.updateUserStatus';
import getUserStatus from '@salesforce/apex/RES_UserAvailabilityController.getUserStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class UserAvailability extends LightningElement {

    @track currentStatus = 'Available';
    @track isLoading = false;
    @track showToast = false;
    @track toastMessage = '';
    @track isSuccess = true;

    connectedCallback() {
        this.loadStatus();
    }

    loadStatus() {
        getUserStatus()
            .then(result => {
                console.log('result==>',result);
                this.currentStatus = result;
            })
            .catch(error => {
                this.showError(error);
            });
    }

    handleAvailable() {
        this.updateStatus('Available');
    }

    handleOffline() {
        this.updateStatus('Offline');
    }

    updateStatus(status) {
        this.isLoading = true;

        updateUserStatus({ newStatus: status })
            .then(result => {
                this.currentStatus = result;
                this.showSuccess('Your Status updated to ' + result);
            })
            .catch(error => {
                this.showError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // UI Helpers
    get isAvailable() {
        return this.currentStatus === 'Available';
    }

    get isOffline() {
        return this.currentStatus === 'Offline';
    }

    get computedAvailableClass() {
        return this.isAvailable ? 'btn active available' : 'btn';
    }

    get computedOfflineClass() {
        return this.isOffline ? 'btn active offline' : 'btn';
    }

    showSuccess(msg) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: msg,
                variant: 'success'
            })
        );
    }

    showError(error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Error occurred',
                variant: 'error'
            })
        );
    }
}
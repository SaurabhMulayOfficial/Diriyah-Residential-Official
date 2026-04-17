import { LightningElement, track } from 'lwc';
import getUserStatus from '@salesforce/apex/RES_UserAvailabilityController.getUserStatus';
import updateUserStatus from '@salesforce/apex/RES_UserAvailabilityController.updateUserStatus';

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
                this.showSuccess('Status updated to ' + result);
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

    // Toast handling
    showSuccess(msg) {
        this.isSuccess = true;
        this.toastMessage = msg;
        this.showToast = true;
    }

    showError(error) {
        this.isSuccess = false;
        this.toastMessage = error.body?.message || 'Error occurred';
        this.showToast = true;
    }
}
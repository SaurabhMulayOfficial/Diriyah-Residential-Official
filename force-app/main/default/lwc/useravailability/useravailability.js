import { LightningElement, track } from 'lwc';
import getUserStatusData from '@salesforce/apex/RES_UserAvailabilityController.getUserStatusData';
import updateUserStatus from '@salesforce/apex/RES_UserAvailabilityController.updateUserStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class UserAvailability extends LightningElement {
    @track currentStatus = '';
    @track statusOptions = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track hasData = true;

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        this.isLoading = true;

        getUserStatusData()
            .then(result => {
                this.hasData = true;
                this.errorMessage = '';

                this.currentStatus = result.currentStatus;

                this.statusOptions = result.picklistValues.map(item => {
                    return {
                        label: item,
                        value: item
                    };
                });
            })
            .catch(error => {
                this.hasData = false;
                this.errorMessage =
                    error.body?.message || 'No Assignment record found for user.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleStatusChange(event) {
        const selectedValue = event.detail.value;
        this.updateStatus(selectedValue);
    }

    updateStatus(status) {
        this.isLoading = true;

        updateUserStatus({ newStatus: status })
            .then(result => {
                this.currentStatus = result;

                this.showToast(
                    'Success',
                    'User Status updated to ' + result,
                    'success'
                );
            })
            .catch(error => {
                this.showToast(
                    'Error',
                    error.body?.message,
                    'error'
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
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
}
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUserStatusData from '@salesforce/apex/RES_UserAvailabilityController.getUserStatusData';
import updateUserStatus from '@salesforce/apex/RES_UserAvailabilityController.updateUserStatus';

export default class UserAvailability extends LightningElement {

    @track currentStatus = '';
    @track statusOptions = [];
    @track isLoading = false;

    connectedCallback() {
        this.loadData();
    }

    loadData() {

        this.isLoading = true;

        getUserStatusData()
            .then(result => {

                this.currentStatus = result.currentStatus;

                this.statusOptions = result.picklistValues.map(item => {
                    return {
                        label: item,
                        value: item
                    };
                });
            })
            .catch(error => {
                this.showError(error);
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
                    'My Status updated to ' + result,
                    'success'
                );
            })
            .catch(error => {
                this.showError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showError(error) {

        let msg =
            error.body?.message ||
            'Error occurred';

        this.showToast(
            'Error',
            msg,
            'error'
        );
    }

    showToast(title, message, variant) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
                mode: 'dismissable'
            })
        );
    }
}
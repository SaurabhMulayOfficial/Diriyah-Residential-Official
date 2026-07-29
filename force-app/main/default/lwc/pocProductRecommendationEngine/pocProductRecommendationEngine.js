import { LightningElement, api, track } from 'lwc';
import getComponentData from '@salesforce/apex/POC_ProductRecommendationController.getComponentData';
import saveSelectedProducts from '@salesforce/apex/POC_ProductRecommendationController.saveSelectedProducts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class pocProductRecommendationEngine extends LightningElement {
    @api recordId;
    @api objectApiName;

    @track savedProducts = [];
    @track recommendedProducts = [];
    @track preSelectedRows = [];
    
    isModalOpen = false;
    showRecommendationAlert = false;
    selectedIdsToSave = [];

    columns = [
        { label: 'Product Code', fieldName: 'ProductCode', type: 'text' },
        { label: 'Product Name', fieldName: 'Name', type: 'text' },
        { label: 'Description', fieldName: 'Description', type: 'text' }
    ];

    connectedCallback() {
        this.loadData();
    }

    get isLead() {
        return this.objectApiName === 'Lead';
    }

    get hasSavedProducts() {
        return this.savedProducts && this.savedProducts.length > 0;
    }

    loadData() {
        getComponentData({ recordId: this.recordId, objectApiName: this.objectApiName })
            .then(result => {
                // Populate saved products (Table on UI)
                if (result.savedProducts) {
                    this.savedProducts = result.savedProducts;
                    this.preSelectedRows = this.savedProducts.map(prod => prod.Id);
                }

                // Handle recommendations popup logic for Leads
                if (this.isLead && result.hasRecommendations) {
                    this.recommendedProducts = result.recommendedProducts;
                    // Only show the alert if they haven't saved any products yet, or if you want it always visible, remove the !this.hasSavedProducts check
                    this.showRecommendationAlert = !this.hasSavedProducts; 
                }
            })
            .catch(error => {
                this.showToast('Error', 'Error loading recommendations', 'error');
                console.error(error);
            });
    }

    openModal() {
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedIdsToSave = selectedRows.map(row => row.Id);
    }

    saveSelection() {
        const idString = this.selectedIdsToSave.join(',');

        saveSelectedProducts({ recordId: this.recordId, objectApiName: this.objectApiName, selectedIds: idString })
            .then(() => {
                this.showToast('Success', 'Products saved successfully!', 'success');
                this.closeModal();
                this.showRecommendationAlert = false; // Hide alert after saving
                this.loadData(); // Refresh the table
            })
            .catch(error => {
                this.showToast('Error', 'Error saving selection', 'error');
                console.error(error);
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}